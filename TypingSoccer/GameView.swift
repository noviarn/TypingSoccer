//
//  GameView.swift
//  TypingSoccer
//
//  SwiftUI menu + SpriteKit host view + the coordinator that ties the scene
//  together with GameKit multiplayer, Game Center and the Foundation Models
//  feedback.
//
//  Multiplayer flow (Game Center):
//    • Menu → pick 1v1 or 2v2 → the lobby.
//    • In the lobby you pick your country. For 2v2 you gather a teammate first:
//      the room MASTER taps "Generate Key" to mint a short code; the teammate
//      types that code to join the same private room. 1v1 needs no teammate.
//    • Tapping "Battle" starts matchmaking for the opposing side. Matchmaking
//      keeps running until the match is found or the player taps Cancel.
//

import SwiftUI
import SpriteKit
import GameKit

// MARK: - Coordinator

@MainActor
final class GameCoordinator: ObservableObject {

    enum Screen { case menu, lobby, playing, results }

    @Published var screen: Screen = .menu
    @Published var multiplayerMode: MPMode = .twoVsTwo   // chosen from the menu
    @Published var mySeat: Int? = nil                    // my assigned seat
    @Published var isKeeperRole = false                  // in-match: hide the formation bar

    // Lobby / party state.
    @Published var roomKey: String? = nil                // shown to the master, typed by a joiner
    @Published var joinKeyField: String = ""             // bound to the "enter key" text field
    @Published var isRoomMaster = false                  // I generated the key (host the room)
    @Published var teammatePresent = false               // 2v2: my teammate has joined
    @Published var teammateName: String = ""             // 2v2: my teammate's name
    @Published var battleStarted = false                 // Battle tapped → searching opponents
    @Published var lobbyStatus = ""                      // matchmaking progress line
    @Published var gcAlertShown = false                  // Game Center sign-in required alert

    // Host-side seating bookkeeping, keyed by GameKit gamePlayerID.
    private var helloInfo: [String: (country: String, roomKey: String?)] = [:]
    private var seatAssignment: [String: PeerSeat] = [:]

    @Published var feedbackText: String = ""
    @Published var finalHome = 0
    @Published var finalAway = 0
    @Published var finalHomePens: Int? = nil   // set only if a shootout decided it
    @Published var finalAwayPens: Int? = nil
    @Published var peerConnected = false
    @Published var isGeneratingFeedback = false
    @Published var homeStats: PlayerStats? = nil   // stats for the results screen
    @Published var coachRequested = false          // has the coach note been asked for?
    @Published var homeFormation: Formation = .oneTwo   // persists across matches

    // World Cup team selection. In single player both pickers apply; in
    // multiplayer YOUR TEAM is yours and the rival's pick arrives over the wire.
    @Published var homeWCTeam: WCTeam = WorldCupTeams.all[0]   // France
    @Published var awayWCTeam: WCTeam = WorldCupTeams.all[1]   // Argentina

    private(set) var scene: GameScene?
    private let matchManager = GameKitMatchManager()

    /// Pick a formation from the UI. Applied at the next reset in-game.
    func selectFormation(_ f: Formation) {
        homeFormation = f
        scene?.setHomeFormation(f)
    }

    func startSinglePlayer() {
        matchManager.stop()
        launch(mode: .singlePlayer)
    }

    // MARK: Multiplayer (GameKit)

    /// Enter the multiplayer lobby for the chosen format.
    func startMultiplayer(mode: MPMode) {
        guard GameCenterManager.shared.isAuthenticated else {
            gcAlertShown = true
            GameCenterManager.shared.authenticate()   // re-present the sign-in sheet
            return
        }
        matchManager.stop()
        matchManager.delegate = self
        multiplayerMode = mode
        resetLobby()
        screen = .lobby
        mmLog("enter lobby mode=\(mode == .oneVsOne ? "1v1" : "2v2")")
    }

    /// Cycle the local player's country pick in the lobby (before matchmaking).
    func cycleMyCountry(next: Bool) {
        guard screen == .lobby, !battleStarted else { return }
        let all = WorldCupTeams.all
        guard !all.isEmpty,
              let idx = all.firstIndex(where: { $0.id == homeWCTeam.id }) else { return }
        let n = all.count
        homeWCTeam = all[next ? (idx + 1) % n : (idx - 1 + n) % n]
    }

    /// 2v2 master: mint a room code and open a private room for a teammate.
    func generateRoomKey() {
        guard multiplayerMode == .twoVsTwo, roomKey == nil, !battleStarted else { return }
        let key = GameKitMatchManager.makeRoomKey()
        roomKey = key
        isRoomMaster = true
        lobbyStatus = "Share your key and wait for a teammate…"
        matchManager.hostRoom(mode: .twoVsTwo, key: key)
    }

    /// 2v2 teammate: join a master's room by typing their code.
    func joinRoomByKey() {
        let key = joinKeyField.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard multiplayerMode == .twoVsTwo, roomKey == nil, !battleStarted, key.count >= 3 else { return }
        roomKey = key
        isRoomMaster = false
        joinKeyField = ""
        lobbyStatus = "Joining room…"
        matchManager.joinRoom(mode: .twoVsTwo, key: key)
    }

    /// Whether the Battle button is currently actionable.
    var canTapBattle: Bool {
        guard !battleStarted else { return false }
        switch multiplayerMode {
        case .oneVsOne: return true
        case .twoVsTwo:
            if isRoomMaster { return teammatePresent }
            return roomKey == nil          // solo "quick" 2v2 (teamed with a stranger)
        }
    }

    /// Start matchmaking for the opposing side. Runs until a match is found or
    /// the player cancels — there is no automatic timeout.
    func startBattle() {
        guard screen == .lobby, canTapBattle else { return }
        battleStarted = true
        lobbyStatus = "Finding opponents on Game Center…"
        matchManager.startBattle(mode: multiplayerMode)
    }

    func cancelLobby() {
        matchManager.stop()
        resetLobby()
        screen = .menu
    }

    private func resetLobby() {
        mySeat = nil
        roomKey = nil
        joinKeyField = ""
        isRoomMaster = false
        teammatePresent = false
        teammateName = ""
        battleStarted = false
        peerConnected = false
        lobbyStatus = ""
        helloInfo = [:]
        seatAssignment = [:]
    }

    // MARK: Host-side seat assignment

    /// Once every player's `hello` has arrived, the elected host groups players
    /// into balanced teams and broadcasts the seating inside `startMatch` (so it
    /// can't arrive out of order). The host keeps `homeField`; its real teammate
    /// stays on the home side to satisfy the wire "home = host's team" rule.
    private func tryAssignSeats() {
        guard matchManager.isHost, mySeat == nil else { return }
        let ids = matchManager.allPlayerIDs
        guard ids.allSatisfy({ helloInfo[$0] != nil }) else {
            mmLog("host waiting for hellos (\(helloInfo.count)/\(ids.count))")
            return
        }
        let map = computeSeatAssignment(ids: ids)
        seatAssignment = map

        let host = matchManager.localPlayerID
        let awayFieldID = map.first(where: { $0.value == .awayField })?.key
        let homeID = helloInfo[host]?.country ?? homeWCTeam.id
        let awayID = awayFieldID.flatMap { helloInfo[$0]?.country }
            ?? WorldCupTeams.all.first(where: { $0.id != homeID })?.id
            ?? WorldCupTeams.all[1].id
        let homeForm = homeFormation.rawValue
        let awayForm = Formation.oneTwo.rawValue

        var seatMap: [String: Int] = [:]
        for (pid, seat) in map { seatMap[pid] = seat.rawValue }

        mmLog("host seating: \(seatMap) home=\(homeID) away=\(awayID)")
        matchManager.send(.startMatch(homeTeamID: homeID, awayTeamID: awayID,
                                      homeFormation: homeForm, awayFormation: awayForm,
                                      seatMap: seatMap))
        mySeat = map[host]?.rawValue
        launchMultiplayer(homeTeamID: homeID, awayTeamID: awayID,
                          homeFormationRaw: homeForm, awayFormationRaw: awayForm)
    }

    private func computeSeatAssignment(ids: [String]) -> [String: PeerSeat] {
        let host = matchManager.localPlayerID
        func key(_ id: String) -> String? { helloInfo[id]?.roomKey ?? nil }

        guard multiplayerMode == .twoVsTwo else {
            // 1v1: host = homeField, the other player = awayField.
            var map: [String: PeerSeat] = [host: .homeField]
            for id in ids where id != host { map[id] = .awayField }
            return map
        }
        // 2v2: keep the host's real teammate (same room key) on the home side.
        var home: [String] = [host]
        if let hostKey = key(host),
           let mate = ids.first(where: { $0 != host && key($0) == hostKey }) {
            home.append(mate)
        }
        if home.count < 2 {
            // Host searched solo: pair with a leftover, keeping any opposing
            // party (a pair sharing a key) together on the away side.
            let remaining = ids.filter { !home.contains($0) }
            var keyGroups: [String: [String]] = [:]
            for id in remaining {
                if let k = key(id) { keyGroups[k, default: []].append(id) }
            }
            let awayPair = Set(keyGroups.values.first(where: { $0.count >= 2 })
                .map { Array($0.prefix(2)) } ?? [])
            if let mate = remaining.sorted().first(where: { !awayPair.contains($0) }) {
                home.append(mate)
            }
        }
        let away = ids.filter { !home.contains($0) }.sorted()
        var map: [String: PeerSeat] = [host: .homeField]
        for id in home where id != host { map[id] = .homeKeeper }
        if let f = away.first { map[f] = .awayField }
        for id in away.dropFirst() { map[id] = .awayKeeper }
        return map
    }

    /// Configure the scene for MY seat: my team is always the local `.home`.
    private func launchMultiplayer(homeTeamID: String, awayTeamID: String,
                                   homeFormationRaw: Int, awayFormationRaw: Int) {
        guard let seatRaw = mySeat, let seat = PeerSeat(rawValue: seatRaw) else {
            mmLog("launchMultiplayer aborted — no seat"); return
        }
        let myTeamID    = seat.isHome ? homeTeamID : awayTeamID
        let rivalTeamID = seat.isHome ? awayTeamID : homeTeamID
        let myForm    = Formation(rawValue: seat.isHome ? homeFormationRaw : awayFormationRaw) ?? .oneTwo
        let rivalForm = Formation(rawValue: seat.isHome ? awayFormationRaw : homeFormationRaw) ?? .oneTwo
        homeWCTeam = WorldCupTeams.team(named: myTeamID) ?? homeWCTeam
        awayWCTeam = WorldCupTeams.team(named: rivalTeamID) ?? awayWCTeam
        homeFormation = myForm
        // In 1v1 the sole player controls the whole team (keeper included), so
        // the formation bar stays visible; only a 2v2 keeper hides it.
        isKeeperRole = multiplayerMode.teamSize == 2 && !seat.isField
        mmLog("LAUNCH seat=\(seat) team=\(myTeamID) vs \(rivalTeamID) isHost=\(matchManager.isHost)")
        launch(mode: .multipeer, seat: seat,
               teamSize: multiplayerMode.teamSize, rivalFormation: rivalForm)
    }

    private func launch(mode: MatchMode, seat: PeerSeat = .homeField,
                        teamSize: Int = 2, rivalFormation: Formation? = nil) {
        let s = GameScene(size: GameConfig.sceneSize)
        s.mode = mode
        s.isNetworkHost = mode == .multipeer && matchManager.isHost
        s.localSeat = seat
        s.teamSize = teamSize
        s.gameDelegate = self
        s.homeFormation = homeFormation   // carry the chosen shape into the new match
        if let rivalFormation { s.awayFormation = rivalFormation }
        s.homeTeam = homeWCTeam           // real squads with FC 26 pace-based speeds
        s.awayTeam = awayWCTeam           // (multiplayer: the other field player's pick)
        scene = s
        feedbackText = ""
        homeStats = nil
        coachRequested = false
        isGeneratingFeedback = false
        finalHomePens = nil
        finalAwayPens = nil
        if mode == .singlePlayer { isKeeperRole = false }
        screen = .playing
    }

    /// Generate the coach's note on demand (after the player taps the button on
    /// the results screen). Kept off the match-finish path so nothing blocks or
    /// stutters the game — the on-device model only runs when explicitly asked.
    func requestCoachAnalysis() {
        guard let stats = homeStats, !coachRequested else { return }
        coachRequested = true
        isGeneratingFeedback = true
        Task { @MainActor in
            let text = await MatchFeedback.generate(stats: stats,
                                                    homeScore: finalHome,
                                                    awayScore: finalAway)
            self.feedbackText = text
            self.isGeneratingFeedback = false
        }
    }

    func returnToMenu() {
        matchManager.stop()
        scene = nil
        screen = .menu
    }
}

extension GameCoordinator: GameSceneDelegate {
    nonisolated func matchDidFinish(homeStats: PlayerStats, homeScore: Int, awayScore: Int,
                                    penaltyHome: Int?, penaltyAway: Int?) {
        Task { @MainActor in
            self.finalHome = homeScore
            self.finalAway = awayScore
            self.finalHomePens = penaltyHome
            self.finalAwayPens = penaltyAway
            self.homeStats = homeStats
            self.feedbackText = ""
            self.coachRequested = false
            self.isGeneratingFeedback = false
            self.screen = .results
            GameCenterManager.shared.submit(score: Int(homeStats.averageWPM.rounded()))
            // Coach note is generated later, only if the player taps the button.
        }
    }

    nonisolated func localPlayerCompletedWord(mistyped: Bool) {
        Task { @MainActor in
            guard let seat = self.mySeat, self.scene?.mode == .multipeer else { return }
            self.matchManager.send(.wordCompleted(seat: seat, mistyped: mistyped))
        }
    }

    nonisolated func formationChanged(to formation: Formation) {
        Task { @MainActor in
            self.homeFormation = formation
            if self.scene?.mode == .multipeer,
               let raw = self.mySeat, let seat = PeerSeat(rawValue: raw) {
                self.matchManager.send(.formationUpdate(homeTeam: seat.isHome,
                                                        formation: formation.rawValue))
            }
        }
    }

    nonisolated func peerSend(_ message: PeerMessage) {
        Task { @MainActor in self.matchManager.send(message) }
    }
}

extension GameCoordinator: MatchManagerDelegate {

    nonisolated func matchStateChanged() {
        Task { @MainActor in
            self.peerConnected = self.matchManager.connectedRemoteCount > 0
        }
    }

    /// 2v2: the room master's teammate connected — the party is formed.
    nonisolated func partyReady() {
        Task { @MainActor in
            guard self.screen == .lobby, !self.battleStarted else { return }
            self.teammatePresent = true
            self.teammateName = self.matchManager.match?.players.first?.displayName ?? "Teammate"
            self.lobbyStatus = self.isRoomMaster
                ? "Teammate ready — tap Battle!"
                : "Joined — waiting for the host to start…"
        }
    }

    /// The full table connected: everyone announces their country + room key,
    /// and the elected host groups players into balanced teams and seats them.
    nonisolated func matchReady() {
        Task { @MainActor in
            guard self.screen == .lobby else { return }
            self.peerConnected = true
            self.battleStarted = true
            self.lobbyStatus = "Match found — starting…"
            self.helloInfo[self.matchManager.localPlayerID] =
                (country: self.homeWCTeam.id, roomKey: self.matchManager.roomKey)
            self.matchManager.send(.hello(country: self.homeWCTeam.id,
                                          roomKey: self.matchManager.roomKey))
            self.tryAssignSeats()
        }
    }

    nonisolated func matchFailed(error: Error?) {
        Task { @MainActor in
            if let error { mmLog("matchFailed: \(error.localizedDescription)") }
            guard self.screen == .lobby else { return }
            if !GameCenterManager.shared.isAuthenticated {
                self.cancelLobby()
                self.gcAlertShown = true
                GameCenterManager.shared.authenticate()
                return
            }
            // Authenticated but the search errored. Keep trying until the player
            // cancels — re-issue the request after a short pause.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard self.screen == .lobby else { return }
            if self.battleStarted {
                self.matchManager.startBattle(mode: self.multiplayerMode)
            } else if let key = self.roomKey {
                if self.isRoomMaster { self.matchManager.hostRoom(mode: .twoVsTwo, key: key) }
                else { self.matchManager.joinRoom(mode: .twoVsTwo, key: key) }
            }
        }
    }

    nonisolated func playerLeft(playerID: String, wasHost: Bool) {
        Task { @MainActor in
            switch self.screen {
            case .lobby:
                if !self.battleStarted {
                    // Party phase: my teammate dropped out.
                    self.teammatePresent = false
                    self.teammateName = ""
                    if self.isRoomMaster, let key = self.roomKey {
                        self.matchManager.hostRoom(mode: .twoVsTwo, key: key)
                        self.roomKey = key
                        self.isRoomMaster = true
                        self.lobbyStatus = "Share your key and wait for a teammate…"
                    } else {
                        self.matchManager.stop()
                        self.roomKey = nil
                        self.lobbyStatus = ""
                    }
                }
                // If a player drops mid-search, matchmaking simply keeps going.
            case .playing:
                guard self.scene?.mode == .multipeer else { break }
                // No mid-match AI takeover: any disconnect ends the match.
                self.scene?.peerDidDisconnect()
            default:
                break
            }
        }
    }

    nonisolated func didReceive(_ message: PeerMessage, fromPlayerID playerID: String) {
        Task { @MainActor in
            switch message {

            // ---- Lobby / seating ----
            case .hello(let country, let roomKey):
                guard self.matchManager.isHost, self.screen == .lobby else { break }
                self.helloInfo[playerID] = (country: country, roomKey: roomKey)
                self.tryAssignSeats()

            case .startMatch(let homeTeamID, let awayTeamID, let homeF, let awayF, let seatMap):
                guard !self.matchManager.isHost, self.screen == .lobby else { break }
                guard let raw = seatMap[self.matchManager.localPlayerID] else {
                    mmLog("startMatch missing my seat — ignoring"); break
                }
                self.mySeat = raw
                for (pid, s) in seatMap { if let seat = PeerSeat(rawValue: s) { self.seatAssignment[pid] = seat } }
                self.launchMultiplayer(homeTeamID: homeTeamID, awayTeamID: awayTeamID,
                                       homeFormationRaw: homeF, awayFormationRaw: awayF)

            // ---- In-match traffic, routed into the scene ----
            case .formationUpdate(let homeTeam, let raw):
                self.scene?.applyRemoteFormationUpdate(homeTeamWire: homeTeam, raw: raw)
            case .typingProgress(let seat, let count):
                self.scene?.applyRemoteTypingProgress(seatRaw: seat, count: count)
            case .wordCompleted(let seat, let mistyped):
                self.scene?.applyRemoteWordCompleted(seatRaw: seat, mistyped: mistyped)
            case .shotMistyped(let seat):
                self.scene?.applyRemoteShotMistype(seatRaw: seat)
            case .passRequest(let seat, let lane):
                self.scene?.applyPeerPassRequest(seatRaw: seat, toLane: lane)
            case .chaseRequest(let seat, let lane):
                self.scene?.applyChaseRequest(seatRaw: seat, laneRaw: lane)
            case .chaseState(let homeTeam, let lane):
                self.scene?.applyRemoteChaseState(homeTeamWire: homeTeam, laneRaw: lane)
            case .duelStart(let kind, let word, let attacker, let defender):
                self.scene?.applyRemoteDuelStart(kindCode: kind, word: word,
                                                 attacker: attacker, defender: defender)
            case .duelResult(let winnerHome, let shotOutcome):
                self.scene?.applyRemoteDuelResult(winnerHome: winnerHome,
                                                  shotOutcomeCode: shotOutcome)
            case .possession(let player, let x, let y, let mustPass):
                self.scene?.applyRemotePossession(playerRef: player, x: x, y: y,
                                                  mustPass: mustPass)
            case .passStarted(let target, let offside, let lineX):
                self.scene?.applyRemotePass(targetRef: target, offside: offside, lineX: lineX)
            case .addedTime:
                self.scene?.applyRemoteAddedTime()
            case .breakNow(let kind, let shootoutGoalRight):
                self.scene?.applyRemoteBreak(kind: kind, shootoutGoalRight: shootoutGoalRight)
            }
        }
    }
}

// MARK: - SpriteKit host (NSViewRepresentable so we control first responder)

struct SpriteHostView: NSViewRepresentable {
    let scene: GameScene

    func makeNSView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        view.ignoresSiblingOrder = true
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ nsView: SKView, context: Context) {
        if nsView.scene !== scene { nsView.presentScene(scene) }
        // Grab keyboard focus so the scene receives keyDown events.
        DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
    }
}

// MARK: - Root UI

struct ContentView: View {
    @EnvironmentObject var coordinator: GameCoordinator

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch coordinator.screen {
            case .menu:    MenuView()
            case .lobby:   LobbyView()
            case .playing: PlayingView()
            case .results: ResultsView()
            }
        }
        .alert("Sign in to Game Center", isPresented: $coordinator.gcAlertShown) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Multiplayer needs Game Center. Open System Settings › Game Center to sign in, then try again.")
        }
    }
}

struct MenuView: View {
    @EnvironmentObject var coordinator: GameCoordinator

    var body: some View {
        VStack(spacing: 22) {
            Text("TYPING SOCCER")
                .font(.system(size: 44, weight: .heavy, design: .monospaced))
                .foregroundColor(.yellow)
            Text("Type fast. Win the ball. Score.")
                .font(.system(.title3, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))

            // World Cup team selection. RIVAL TEAM applies to single player;
            // in multiplayer you set your own country in the lobby.
            HStack(spacing: 18) {
                teamPicker("YOUR TEAM", selection: $coordinator.homeWCTeam)
                Text("vs")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                teamPicker("RIVAL TEAM (VS AI)", selection: $coordinator.awayWCTeam)
            }
            .padding(.top, 8)

            VStack(spacing: 14) {
                menuButton("SINGLE PLAYER (vs AI)") { coordinator.startSinglePlayer() }
                menuButton("MULTIPLAYER 1v1 (GAME CENTER)") { coordinator.startMultiplayer(mode: .oneVsOne) }
                menuButton("MULTIPLAYER 2v2 (GAME CENTER)") { coordinator.startMultiplayer(mode: .twoVsTwo) }
            }
            .padding(.top, 12)

            Text("Countdown whistle → type the word → first to finish gets the ball.\nCarriers auto-run to goal; defenders intercept with new words.\nKeys 1·2·3: pass when attacking, pick your chaser when defending.")
                .multilineTextAlignment(.center)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 8)
        }
        .padding(40)
    }

    private func teamPicker(_ label: String, selection: Binding<WCTeam>) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
            Picker(label, selection: selection) {
                ForEach(WorldCupTeams.all) { team in
                    Text(team.name).tag(team)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 150)
        }
    }

    private func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .frame(width: 320, height: 46)
                .background(Color.yellow.opacity(0.15))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow, lineWidth: 1.5))
                .foregroundColor(.yellow)
        }
        .buttonStyle(.plain)
    }
}

/// Pre-match lobby. Pick your country; in 2v2 gather a teammate via a room key,
/// then tap Battle to matchmake a balanced opposing side over Game Center.
struct LobbyView: View {
    @EnvironmentObject var coordinator: GameCoordinator

    private var is2v2: Bool { coordinator.multiplayerMode == .twoVsTwo }

    var body: some View {
        VStack(spacing: 18) {
            Text(is2v2 ? "2v2 LOBBY" : "1v1 LOBBY")
                .font(.system(size: 26, weight: .heavy, design: .monospaced))
                .foregroundColor(.yellow)

            countryPicker

            if is2v2 { partySection }

            if coordinator.battleStarted {
                searchingRow
            } else {
                battleButton
            }

            actionButton("CANCEL", filled: false) { coordinator.cancelLobby() }
        }
        .padding(36)
        .frame(maxWidth: 560)
    }

    // MARK: My country

    private var countryPicker: some View {
        VStack(spacing: 8) {
            Text("YOUR COUNTRY")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
            HStack(spacing: 16) {
                arrow("‹") { coordinator.cycleMyCountry(next: false) }
                    .disabled(coordinator.battleStarted)
                Text(coordinator.homeWCTeam.name.uppercased())
                    .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(minWidth: 170)
                arrow("›") { coordinator.cycleMyCountry(next: true) }
                    .disabled(coordinator.battleStarted)
            }
        }
    }

    // MARK: 2v2 party

    private var partySection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                playerSlot(name: "YOU", filled: true)
                Text("+").font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                playerSlot(name: coordinator.teammatePresent ? coordinator.teammateName : "waiting…",
                           filled: coordinator.teammatePresent)
            }

            if !coordinator.battleStarted {
                if let key = coordinator.roomKey {
                    roomKeyDisplay(key)
                } else {
                    roomJoinControls
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func playerSlot(name: String, filled: Bool) -> some View {
        Text(name)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(filled ? .green : .white.opacity(0.45))
            .lineLimit(1)
            .frame(width: 150, height: 46)
            .background(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(filled ? Color.green.opacity(0.7) : Color.white.opacity(0.2), lineWidth: 1.4))
    }

    private func roomKeyDisplay(_ key: String) -> some View {
        VStack(spacing: 6) {
            Text(coordinator.isRoomMaster ? "SHARE THIS KEY" : "JOINED ROOM")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
            Text(key)
                .font(.system(size: 30, weight: .black, design: .monospaced))
                .tracking(8)
                .foregroundColor(.yellow)
                .padding(.horizontal, 20).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow, lineWidth: 1.5))
        }
    }

    private var roomJoinControls: some View {
        VStack(spacing: 10) {
            actionButton("GENERATE KEY", filled: true) { coordinator.generateRoomKey() }
            Text("— or —")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            HStack(spacing: 8) {
                TextField("ENTER KEY", text: $coordinator.joinKeyField)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(width: 150, height: 38)
                    .background(Color.white.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.7), lineWidth: 1.4))
                    .onSubmit { coordinator.joinRoomByKey() }
                Button(action: { coordinator.joinRoomByKey() }) {
                    Text("JOIN")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .frame(width: 74, height: 38)
                        .background(Color.cyan.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan, lineWidth: 1.4))
                        .foregroundColor(.cyan)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Battle / status

    private var battleButton: some View {
        Button(action: { coordinator.startBattle() }) {
            Text("BATTLE")
                .font(.system(size: 18, weight: .black, design: .monospaced))
                .frame(width: 240, height: 50)
                .background(coordinator.canTapBattle ? Color.yellow : Color.yellow.opacity(0.2))
                .foregroundColor(coordinator.canTapBattle ? .black : .white.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!coordinator.canTapBattle)
    }

    private var searchingRow: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(coordinator.lobbyStatus.isEmpty ? "Finding opponents…" : coordinator.lobbyStatus)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.top, 4)
    }

    // MARK: Small helpers

    private func arrow(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 24, weight: .black, design: .monospaced))
                .foregroundColor(.yellow)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
    }

    private func actionButton(_ title: String, filled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .frame(width: 220, height: 40)
                .background(filled ? Color.yellow.opacity(0.15) : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow, lineWidth: 1.5))
                .foregroundColor(.yellow)
        }
        .buttonStyle(.plain)
    }
}

struct PlayingView: View {
    @EnvironmentObject var coordinator: GameCoordinator

    var body: some View {
        VStack(spacing: 0) {
            if coordinator.isKeeperRole {
                // Keeper players don't set formations — show their controls.
                Text("KEEPER — type when a shot comes in · press 1·2·3 to distribute after a save")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.8))
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
            } else {
                FormationBar()
            }
            ZStack(alignment: .topTrailing) {
                if let scene = coordinator.scene {
                    SpriteHostView(scene: scene)
                        .aspectRatio(GameConfig.sceneSize.width / GameConfig.sceneSize.height, contentMode: .fit)
                }
                if coordinator.scene?.mode == .multipeer {
                    Text(coordinator.peerConnected ? "● connected" : "○ connection lost…")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(coordinator.peerConnected ? .green : .orange)
                        .padding(10)
                }
            }
        }
    }
}

/// Formation picker shown above the pitch. Each card is a little diagram of
/// where the three outfielders line up. Click a card, or use ← / → to cycle.
struct FormationBar: View {
    @EnvironmentObject var coordinator: GameCoordinator

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("FORMATION  ← →")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                Text("PASS / CHASE  1 · 2 · 3")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.7))
            }

            ForEach(Formation.allCases, id: \.self) { f in
                let selected = coordinator.homeFormation == f
                Button(action: { coordinator.selectFormation(f) }) {
                    VStack(spacing: 3) {
                        MiniFormation(formation: f, selected: selected)
                            .frame(width: 48, height: 32)
                        Text(f.label)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(selected ? .yellow : .white.opacity(0.8))
                    }
                    .padding(.horizontal, 7).padding(.vertical, 6)
                    .background(selected ? Color.yellow.opacity(0.18) : Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .stroke(selected ? Color.yellow : Color.white.opacity(0.15), lineWidth: 1.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }
}

/// A tiny half-pitch diagram showing the three outfield players' spots for a
/// formation (own goal on the left; players advance rightward).
struct MiniFormation: View {
    let formation: Formation
    let selected: Bool

    private func yNorm(_ lane: Lane) -> CGFloat {
        if formation == .oneOneOne { return 0.5 }          // stacked on the centre axis
        switch lane { case .top: return 0.24; case .middle: return 0.5; case .bottom: return 0.76 }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.15), lineWidth: 1))
                // own goal line on the left
                Rectangle().fill(Color.white.opacity(0.2))
                    .frame(width: 1.5)
                    .position(x: 2, y: geo.size.height / 2)
                ForEach(Lane.allCases, id: \.self) { lane in
                    let depth = formation.depthFraction(for: lane)     // 0.15…0.42
                    let xN = min(0.88, depth / 0.5)                    // spread across the card
                    Circle()
                        .fill(selected ? Color.yellow : Color.cyan)
                        .frame(width: 7, height: 7)
                        .position(x: geo.size.width * xN, y: geo.size.height * yNorm(lane))
                }
            }
        }
    }
}

struct ResultsView: View {
    @EnvironmentObject var coordinator: GameCoordinator

    var body: some View {
        VStack(spacing: 18) {
            Text("FULL TIME")
                .font(.system(size: 36, weight: .heavy, design: .monospaced))
                .foregroundColor(.yellow)
            Text("\(coordinator.finalHome)  –  \(coordinator.finalAway)")
                .font(.system(size: 56, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            if let hp = coordinator.finalHomePens, let ap = coordinator.finalAwayPens {
                Text("(\(hp) – \(ap) on penalties)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow.opacity(0.85))
            }

            if let stats = coordinator.homeStats {
                StatsPanel(stats: stats)
            }

            coachSection
                .padding(.vertical, 4)

            Button(action: { coordinator.returnToMenu() }) {
                Text("BACK TO MENU")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .frame(width: 240, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow, lineWidth: 1.5))
                    .foregroundColor(.yellow)
            }
            .buttonStyle(.plain)
        }
        .padding(40)
    }

    /// Either the "get coach analysis" button, a loading spinner, or the note.
    @ViewBuilder
    private var coachSection: some View {
        if coordinator.isGeneratingFeedback {
            ProgressView("Your coach is reviewing the match…")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
        } else if coordinator.coachRequested {
            Text(coordinator.feedbackText)
                .font(.system(size: 15, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        } else {
            Button(action: { coordinator.requestCoachAnalysis() }) {
                Text("GET COACH ANALYSIS")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .frame(width: 300, height: 44)
                    .background(Color.yellow.opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow, lineWidth: 1.5))
                    .foregroundColor(.yellow)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Compact grid of the match statistics shown on the results screen.
struct StatsPanel: View {
    let stats: PlayerStats

    private var wpm: Int { Int(stats.averageWPM.rounded()) }
    private var accuracy: Int { Int((stats.accuracy * 100).rounded()) }
    private var fastest: String {
        stats.fastestWordSeconds.map { String(format: "%.1fs", $0) } ?? "—"
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 10) {
            Text("MATCH STATS")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))

            LazyVGrid(columns: columns, spacing: 14) {
                stat("WPM", "\(wpm)")
                stat("ACCURACY", "\(accuracy)%")
                stat("WORDS", "\(stats.wordsCompleted)")
                stat("DUELS W-L", "\(stats.duelsWon)-\(stats.duelsLost)")
                stat("MISTAKES", "\(stats.mistakes)")
                stat("FASTEST", fastest)
            }
        }
        .padding(18)
        .frame(maxWidth: 460)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.15), lineWidth: 1))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(.yellow)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }
}
