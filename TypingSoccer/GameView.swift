//
//  GameView.swift
//  TypingSoccer
//
//  SwiftUI menu + SpriteKit host view + the coordinator that ties the
//  scene together with GameKit multiplayer, the profile store and the
//  Foundation Models feedback.
//

import SwiftUI
import SpriteKit
import AppKit

// MARK: - Coordinator

@MainActor
final class GameCoordinator: ObservableObject {
    
    enum Screen {
        case menu
        case teamSelectionSingle
        case lobby
        case playing
        case results
        case profile
        case leaderboard
        case settings
        case howToPlay
    }

    @Published var screen: Screen = .menu
    @Published var multiplayerMode: MPMode = .twoVsTwo  // chosen from the menu
    @Published var mySeat: Int? = nil                   // lobby: my assigned seat
    @Published var lobbyStatus = ""                     // matchmaking progress line
    @Published var isKeeperRole = false                 // in-match: hide the formation bar
    @Published var isGamePaused = false                 // vs AI pause overlay

    // Lobby / party state.
    @Published var roomKey: String? = nil               // shown to the master, typed by a joiner
    @Published var joinKeyField: String = ""            // bound to the "enter key" text field
    @Published var isRoomMaster = false                 // I generated the key (host the room)
    @Published var teammatePresent = false              // 2v2: my teammate has joined
    @Published var teammateName: String = ""            // 2v2: my teammate's display name
    @Published var battleStarted = false                // Battle tapped → searching opponents

    // Host-side seating bookkeeping, keyed by GameKit gamePlayerID.
    private var helloInfo: [String: (country: String, roomKey: String?)] = [:]
    private var seatAssignment: [String: PeerSeat] = [:]
    private var launchHomeTeamID: String? = nil
    private var launchAwayTeamID: String? = nil
    @Published var feedbackText: String = ""
    @Published var finalHome = 0
    @Published var finalAway = 0
    @Published var finalHomePens: Int? = nil   // set only if a shootout decided it
    @Published var finalAwayPens: Int? = nil
    @Published var peerConnected = false
    @Published var matchmakingFailed = false            // lobby: search finished with no full table
    @Published var gcAlertShown = false                 // Game Center sign-in required alert
    @Published var isGeneratingFeedback = false
    @Published var homeStats: PlayerStats? = nil   // stats for the results screen
    @Published var coachRequested = false          // has the coach note been asked for?
    @Published var homeFormation: Formation = .oneTwo   // persists across matches
    
    // World Cup team selection. In single player both pickers apply; in
    // multiplayer YOUR TEAM is yours and the rival's pick arrives over the
    // wire during the lobby handshake (overwriting awayWCTeam).
    @Published var homeWCTeam: WCTeam = WorldCupTeams.all[0]   // France
    @Published var awayWCTeam: WCTeam = WorldCupTeams.all[1]   // Argentina
    
    private(set) var scene: GameScene?
    private let matchManager = GameKitMatchManager()
    
    var isHosting: Bool { matchManager.isHost }
    
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

    /// Enter the multiplayer lobby for the chosen format. The player picks
    /// their country here, gathers a teammate (2v2), then taps Battle.
    func startMultiplayer(mode: MPMode) {
        // Don't enter the lobby if Game Center isn't signed in — matchmaking
        // would fail instantly. Prompt sign-in instead.
        guard GameCenterManager.shared.isAuthenticated else {
            gcAlertShown = true
            GameCenterManager.shared.authenticate()   // re-present the sign-in sheet
            return
        }
        matchManager.stop()          // clear any stale match from a prior session
        matchManager.delegate = self
        multiplayerMode = mode
        resetLobby()
        screen = .lobby
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
        lobbyStatus = L("lobby.waitingTeammate")
        matchManager.hostRoom(mode: .twoVsTwo, key: key)
    }

    /// 2v2 teammate: join a master's room by typing their code.
    func joinRoomByKey() {
        let key = joinKeyField.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard multiplayerMode == .twoVsTwo, roomKey == nil, !battleStarted, key.count >= 3 else { return }
        roomKey = key
        isRoomMaster = false
        joinKeyField = ""
        lobbyStatus = L("lobby.joining")
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

    /// Start matchmaking for the opposing side.
    func startBattle() {
        guard screen == .lobby, canTapBattle else { return }
        battleStarted = true
        matchmakingFailed = false
        lobbyStatus = L("lobby.searching")
        beginBattleTimeout()
        matchManager.startBattle(mode: multiplayerMode)
    }

    /// Retry after opponent search timed out (keeps a formed 2v2 party).
    func retryBattle() {
        guard screen == .lobby, GameCenterManager.shared.isAuthenticated else { return }
        battleStarted = true
        matchmakingFailed = false
        lobbyStatus = L("lobby.searching")
        beginBattleTimeout()
        matchManager.startBattle(mode: multiplayerMode)
    }

    // Give the opponent search `searchTimeout` seconds before offering retry.
    private static let searchTimeout: Double = 60
    private var searchTask: Task<Void, Never>? = nil

    private func beginBattleTimeout() {
        searchTask?.cancel()
        searchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.searchTimeout * 1_000_000_000))
            guard let self, !Task.isCancelled,
                  self.screen == .lobby, self.battleStarted else { return }
            self.failSearch()
        }
    }

    private func failSearch() {
        matchManager.cancelSearch()
        searchTask?.cancel()
        searchTask = nil
        battleStarted = false
        matchmakingFailed = true
        lobbyStatus = L("lobby.noPlayers")
    }

    /// A match connected, or we're leaving the lobby — stop the countdown.
    private func endSearch() {
        searchTask?.cancel()
        searchTask = nil
    }

    func cancelLobby() {
        endSearch()
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
        matchmakingFailed = false
        lobbyStatus = ""
        helloInfo = [:]
        seatAssignment = [:]
        launchHomeTeamID = nil
        launchAwayTeamID = nil
    }

    // MARK: Host-side seat assignment

    /// Group the connected players into two balanced teams and hand out seats.
    /// The elected host keeps `homeField`; its real teammate (same room key, or
    /// a leftover solo) stays on the home side so the wire "home = host's team"
    /// convention holds. Runs only once every player's `hello` has arrived.
    private func tryAssignSeats() {
        guard matchManager.isHost, mySeat == nil else { return }
        let ids = matchManager.allPlayerIDs
        guard ids.allSatisfy({ helloInfo[$0] != nil }) else { return }   // await all hellos

        let map = computeSeatAssignment(ids: ids)
        seatAssignment = map

        let host = matchManager.localPlayerID
        let awayFieldID = map.first(where: { $0.value == .awayField })?.key
        let homeID = helloInfo[host]?.country ?? homeWCTeam.id
        let awayID = awayFieldID.flatMap { helloInfo[$0]?.country }
            ?? WorldCupTeams.all.first(where: { $0.id != homeID })?.id
            ?? WorldCupTeams.all[1].id
        launchHomeTeamID = homeID
        launchAwayTeamID = awayID

        let homeForm = homeFormation.rawValue
        let awayForm = Formation.oneTwo.rawValue
        for (pid, seat) in map {
            if pid == host { mySeat = seat.rawValue }
            else { matchManager.send(.seatAssigned(seat: seat.rawValue), to: [pid]) }
        }
        matchManager.send(.startMatch(homeTeamID: homeID, awayTeamID: awayID,
                                      homeFormation: homeForm, awayFormation: awayForm))
        launchMultiplayer(homeTeamID: homeID, awayTeamID: awayID,
                          homeFormationRaw: homeForm, awayFormationRaw: awayForm)
    }

    private func computeSeatAssignment(ids: [String]) -> [String: PeerSeat] {
        let host = matchManager.localPlayerID
        // A player's room key, flattened (nil for solo searchers).
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
            // Host searched solo: pair it with a leftover, keeping any opposing
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
        endSearch()
        guard let seatRaw = mySeat, let seat = PeerSeat(rawValue: seatRaw) else { return }
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
        launch(mode: .multiplayer, seat: seat,
               teamSize: multiplayerMode.teamSize, rivalFormation: rivalForm)
    }

    private func launch(mode: MatchMode, seat: PeerSeat = .homeField,
                        teamSize: Int = 2, rivalFormation: Formation? = nil) {
        let s = GameScene(size: GameConfig.sceneSize)
        s.mode = mode
        s.isNetworkHost = mode == .multiplayer && matchManager.isHost
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
        isGamePaused = false
        finalHomePens = nil
        finalAwayPens = nil
        if mode == .singlePlayer { isKeeperRole = false }
        screen = .playing
    }
    
    // MARK: Pause (vs AI only)
    
    func pauseGame() {
        guard scene?.mode == .singlePlayer, !isGamePaused else { return }
        isGamePaused = true
        scene?.setGamePaused(true)
    }
    
    func resumeGame() {
        guard isGamePaused else { return }
        isGamePaused = false
        scene?.setGamePaused(false)
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
        endSearch()
        matchManager.stop()
        scene = nil
        isGamePaused = false
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
            
            // Book the match into the persistent profile (both modes) and,
            // for multiplayer, push the bests to the Game Center boards.
            let isMP = self.scene?.mode == .multiplayer
            let record = MatchRecord(date: Date(),
                                     isMultiplayer: isMP,
                                     myTeamID: self.homeWCTeam.id,
                                     rivalTeamID: self.awayWCTeam.id,
                                     myScore: homeScore, rivalScore: awayScore,
                                     myPens: penaltyHome, rivalPens: penaltyAway,
                                     stats: homeStats)
            PlayerProfileStore.shared.record(record)
            if isMP {
                GameCenterManager.shared.submitMultiplayerStats(
                    from: PlayerProfileStore.shared.profile)
            }
        }
    }
    
    nonisolated func localPlayerCompletedWord(mistyped: Bool) {
        Task { @MainActor in
            guard let seat = self.mySeat, self.scene?.mode == .multiplayer else { return }
            self.matchManager.send(.wordCompleted(seat: seat, mistyped: mistyped))
        }
    }
    
    nonisolated func formationChanged(to formation: Formation) {
        Task { @MainActor in
            self.homeFormation = formation
            if self.scene?.mode == .multiplayer,
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
            self.teammateName = self.matchManager.match?.players.first?.displayName
                ?? L("lobby.teammate")
            self.lobbyStatus = self.isRoomMaster
                ? L("lobby.teammateJoined")
                : L("lobby.waitingHost")
        }
    }

    /// The full table connected: everyone announces their country + room key,
    /// and the elected host groups players into balanced teams and seats them.
    nonisolated func matchReady() {
        Task { @MainActor in
            guard self.screen == .lobby else { return }
            self.endSearch()
            self.peerConnected = true
            self.battleStarted = true
            self.lobbyStatus = L("lobby.starting")
            self.helloInfo[self.matchManager.localPlayerID] =
                (country: self.homeWCTeam.id, roomKey: self.matchManager.roomKey)
            self.matchManager.send(.hello(country: self.homeWCTeam.id,
                                          roomKey: self.matchManager.roomKey))
            self.tryAssignSeats()
        }
    }

    nonisolated func matchFailed(error: Error?) {
        Task { @MainActor in
            if let error { NSLog("Matchmaking failed: \(error.localizedDescription)") }
            guard self.screen == .lobby else { return }
            if !GameCenterManager.shared.isAuthenticated {
                self.cancelLobby()
                self.gcAlertShown = true
                GameCenterManager.shared.authenticate()
                return
            }
            // Authenticated but the search errored: only surface a failure while
            // actively battling; a party search just quietly stops.
            if self.battleStarted { self.failSearch() }
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
                        // Re-open the same room and keep waiting for a teammate.
                        self.matchManager.hostRoom(mode: .twoVsTwo, key: key)
                        self.roomKey = key
                        self.isRoomMaster = true
                        self.lobbyStatus = L("lobby.waitingTeammate")
                    } else {
                        // The master I joined left — clear my room membership.
                        self.matchManager.stop()
                        self.roomKey = nil
                        self.lobbyStatus = ""
                    }
                } else if wasHost && !self.matchManager.isHost {
                    // Lost the elected host before the match launched — bail out.
                    self.failSearch()
                }
            case .playing:
                guard self.scene?.mode == .multiplayer else { break }
                if wasHost && !self.matchManager.isHost {
                    // The sim owner is gone — the match can't continue.
                    self.scene?.peerDidDisconnect()
                } else if self.matchManager.isHost {
                    // A player quit: promote their seat to AI and play on.
                    if let seat = self.seatAssignment[playerID] {
                        self.scene?.seatDidDisconnect(seatRaw: seat.rawValue)
                    }
                }
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

            case .seatAssigned(let seat):
                guard !self.matchManager.isHost, self.screen == .lobby else { break }
                self.mySeat = seat

            case .startMatch(let homeTeamID, let awayTeamID, let homeF, let awayF):
                guard !self.matchManager.isHost, self.screen == .lobby, self.mySeat != nil else { break }
                self.launchMultiplayer(homeTeamID: homeTeamID, awayTeamID: awayTeamID,
                                       homeFormationRaw: homeF, awayFormationRaw: awayF)

                // ---- In-match traffic, routed into the scene ----
                // GKMatch delivers `sendDataToAllPlayers` to every machine, so
                // no host relay is needed (unlike the old Multipeer mesh).
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
            case .seatWentAI(let seat):
                self.scene?.applyRemoteSeatAI(seatRaw: seat)
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
    @ObservedObject private var settings = SettingsStore.shared   // re-render on language change
    
    var body: some View {
        ZStack {
            Image("game-main-bg")
                .resizable()
                .ignoresSafeArea()
            Color.black.opacity(scrimOpacity)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.25), value: coordinator.screen)
            switch coordinator.screen {
            case .menu:
                MenuView()
            case .teamSelectionSingle:
                TeamSelectionView(isMultiplayer: false)
            case .lobby:
                LobbyView()
            case .playing:
                PlayingView()
            case .results:
                ResultsView()
            case .profile:
                ProfileView()
            case .leaderboard:
                LeaderboardView()
            case .settings:
                SettingsView()
            case .howToPlay:
                HowToPlayView()
            }
            if coordinator.screen == .menu {
                VStack {
                    TopBar()
                    Spacer()
                }
            }
        }
        .alert(L("gc.needSignIn"), isPresented: $coordinator.gcAlertShown) {
            Button(L("alert.ok"), role: .cancel) { }
        } message: {
            Text(L("gc.needSignInDetail"))
        }
    }
    
    private var scrimOpacity: Double {
        switch coordinator.screen {
        case .menu:    0.30
        case .teamSelectionSingle: 0.25
        case .lobby:   0.55
        case .playing: 0.75
        case .results: 0.55
        case .profile, .leaderboard, .settings, .howToPlay: 0.55
        }
    }
}

/// Back arrow used by the profile / leaderboard / settings / how-to screens.
struct BackButton: View {
    @EnvironmentObject var coordinator: GameCoordinator
    
    var body: some View {
        Button {
            coordinator.screen = .menu
        } label: {
            Image(systemName: "arrowshape.turn.up.backward.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

struct TopBar: View {
    @EnvironmentObject var coordinator: GameCoordinator
    @ObservedObject private var gameCenter = GameCenterManager.shared
    
    var body: some View {
        HStack {
            // Profile chip → Profile screen.
            Button(action: { coordinator.screen = .profile }) {
                HStack(alignment: .center, spacing: 5) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 24))
                    
                    Text(gameCenter.playerName)
                        .font(.custom("Silom", size: 16))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(
                    Color(red: 203/255, green: 197/255, blue: 197/255)
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Color(red: 109/255, green: 112/255, blue: 116/255)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Trophy → Leaderboards.
            Button(action: { coordinator.screen = .leaderboard }) {
                Circle()
                    .fill(Color(red: 109/255, green: 112/255, blue: 116/255))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(
                                Color(red: 238/255, green: 170/255, blue: 82/255)
                            )
                    )
            }
            .buttonStyle(.plain)
            
            // Gear → Settings.
            Button(action: { coordinator.screen = .settings }) {
                Circle()
                    .fill(Color(red: 109/255, green: 112/255, blue: 116/255))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(
                                Color(red: 203/255, green: 197/255, blue: 197/255)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

struct MenuView: View {
    @EnvironmentObject var coordinator: GameCoordinator
    
    var body: some View {
        VStack(spacing: 22) {
            Text(L("menu.title"))
                .font(.system(size: 44, weight: .heavy, design: .monospaced))
                .foregroundColor(.yellow)
            Text(L("menu.tagline"))
                .font(.system(.title3, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
            
            VStack(spacing: 14) {
                menuButton(L("menu.single")) {
                    coordinator.screen = .teamSelectionSingle
                }
                menuButton(L("menu.multi1v1")) {
                    coordinator.startMultiplayer(mode: .oneVsOne)
                }
                menuButton(L("menu.multi2v2")) {
                    coordinator.startMultiplayer(mode: .twoVsTwo)
                }
                menuButton(L("menu.howto")) {
                    coordinator.screen = .howToPlay
                }
                menuButton(L("EXIT")) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.top, 12)
            
            Text(L("menu.hint"))
                .multilineTextAlignment(.center)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 8)
        }
        .padding(40)
    }
    
    private func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .frame(width: 340, height: 46)
                .background(Color.yellow.opacity(0.15))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow, lineWidth: 1.5))
                .foregroundColor(.yellow)
        }
        .buttonStyle(.plain)
    }
}

struct TeamSelectionView: View {
    @EnvironmentObject var coordinator: GameCoordinator
    
    let isMultiplayer: Bool
    
    @State private var selectedTeam: WCTeam?
    @State private var aiTeam: WCTeam?
    
    private let columns = Array(
        repeating: GridItem(.fixed(170), spacing: 20),
        count: 3
    )
    
    var body: some View {
        VStack(spacing: 28) {
            
            ZStack {
                VStack(spacing: 8) {
                    Text(isMultiplayer ? "Multiplayer Match Setup" : "Single Player Match Setup")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(.yellow)
                        .multilineTextAlignment(.center)
                        .textCase(.uppercase)
                    
                    Text("Choose Your Nationality")
                        .font(.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    
                    Text(isMultiplayer
                         ? "Pick the nationality you want to play as, then find a match on Game Center."
                         : "Pick the nationality you want to play as. The AI will automatically choose a different team.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                }
                
                HStack {
                    Button {
                        coordinator.screen = .menu
                    } label: {
                        Image(systemName: "arrowshape.turn.up.backward.fill")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            LazyVGrid(columns: columns, spacing: 18) {
                
                ForEach(WorldCupTeams.all.sorted { $0.name < $1.name }) { team in
                    
                    Button {
                        selectedTeam = team
                        coordinator.homeWCTeam = team
                        
                        guard !isMultiplayer else { return }
                        let opponents = WorldCupTeams.all.filter {
                            $0.id != team.id
                        }
                        aiTeam = nil   // Clear previous AI selection
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            let randomOpponent = opponents.randomElement()!
                            aiTeam = randomOpponent
                            coordinator.awayWCTeam = randomOpponent
                        }
                        
                    } label: {
                        
                        ZStack(alignment: .topTrailing) {
                            
                            VStack(spacing: 8) {
                                
                                Text(team.flag)
                                    .font(.system(size: 48))
                                
                                Text(team.name)
                                    .font(.system(size: 14,
                                                  weight: .bold,
                                                  design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 170, height: 120)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(
                                        selectedTeam?.id == team.id
                                        ? Color.black.opacity(0.65)
                                        : Color.black.opacity(0.45)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(
                                        selectedTeam?.id == team.id
                                        ? Color.yellow
                                        : Color.white.opacity(0.15),
                                        lineWidth: selectedTeam?.id == team.id ? 3 : 1
                                    )
                            )
                            
                            if selectedTeam?.id == team.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.yellow)
                                    .offset(x: -8, y: 8)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if !isMultiplayer {
                HStack {
                    // MARK: Player
                    
                    VStack(spacing: 12) {
                        
                        Text(L("common.you"))
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.8))
                        
                        if let selectedTeam {
                            
                            VStack {
                                Text(selectedTeam.flag)
                                    .font(.system(size: 60))
                                
                                Text(selectedTeam.name)
                                    .font(.title3.bold())
                                    .foregroundColor(.white)
                            }
                            
                        } else {
                            Text("Waiting...")
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    
                    VStack {
                        Spacer()
                        
                        Text("VS")
                            .font(.system(size: 28,
                                          weight: .black,
                                          design: .monospaced))
                            .foregroundColor(.yellow)
                        
                        Spacer()
                    }
                    .frame(width: 60)
                    
                    // MARK: AI
                    
                    VStack(spacing: 12) {
                        
                        Text(L("common.ai"))
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.8))
                        
                        if let aiTeam {
                            
                            VStack {
                                Text(aiTeam.flag)
                                    .font(.system(size: 60))
                                
                                Text(aiTeam.name)
                                    .font(.title3.bold())
                                    .foregroundColor(.white)
                            }
                            
                        } else {
                            
                            Text("Waiting...")
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
            }
            
            if isMultiplayer ? selectedTeam != nil : aiTeam != nil {

                Button {
                    coordinator.startSinglePlayer()
                } label: {

                    Text(isMultiplayer ? "Find Match" : "Start Match")
                        .font(.title2.bold())
                        .bold(true)
                        .textCase(.uppercase)
                        .frame(width: 200, height: 25)
                        .padding()
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(30)
    }
}

/// Pre-match lobby. The player picks their country here. In 2v2 they gather a
/// teammate first (the master mints a key; the teammate types it), then tap
/// Battle to matchmake a balanced opposing side. 1v1 just taps Battle.
struct LobbyView: View {
    @EnvironmentObject var coordinator: GameCoordinator

    private var is2v2: Bool { coordinator.multiplayerMode == .twoVsTwo }

    var body: some View {
        VStack(spacing: 18) {
            Text(is2v2 ? L("lobby.title2v2") : L("lobby.title1v1"))
                .font(.system(size: 26, weight: .heavy, design: .monospaced))
                .foregroundColor(.yellow)

            countryPicker

            if is2v2 { partySection }

            if coordinator.battleStarted {
                searchingRow
            } else if !coordinator.matchmakingFailed {
                battleButton
            }

            if coordinator.matchmakingFailed {
                Text(L("lobby.noPlayers"))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.orange)
                actionButton(L("lobby.retry"), filled: true) { coordinator.retryBattle() }
            }

            actionButton(L("lobby.cancel"), filled: false) { coordinator.cancelLobby() }
        }
        .padding(36)
        .frame(maxWidth: 560)
    }

    // MARK: My country

    private var countryPicker: some View {
        VStack(spacing: 8) {
            Text(L("lobby.yourCountry"))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
            HStack(spacing: 16) {
                arrow("‹") { coordinator.cycleMyCountry(next: false) }
                    .disabled(coordinator.battleStarted)
                VStack(spacing: 4) {
                    Text(coordinator.homeWCTeam.flag).font(.system(size: 40))
                    Text(coordinator.homeWCTeam.name.uppercased())
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                }
                .frame(minWidth: 150)
                arrow("›") { coordinator.cycleMyCountry(next: true) }
                    .disabled(coordinator.battleStarted)
            }
        }
    }

    // MARK: 2v2 party

    private var partySection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                playerSlot(name: L("lobby.you"), filled: true)
                Text("+").font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                playerSlot(name: coordinator.teammatePresent ? coordinator.teammateName
                                                             : L("lobby.waitingTeammateShort"),
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

    /// Master view: show the code to share, plus the waiting status.
    private func roomKeyDisplay(_ key: String) -> some View {
        VStack(spacing: 6) {
            Text(coordinator.isRoomMaster ? L("lobby.shareKey") : L("lobby.joinedRoom"))
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

    /// Not-yet-in-a-room view: generate a key, or type someone else's.
    private var roomJoinControls: some View {
        VStack(spacing: 10) {
            actionButton(L("lobby.generateKey"), filled: true) { coordinator.generateRoomKey() }
            Text(L("lobby.or"))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            HStack(spacing: 8) {
                TextField(L("lobby.enterKey"), text: $coordinator.joinKeyField)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(width: 150, height: 38)
                    .background(Color.white.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.7), lineWidth: 1.4))
                    .onSubmit { coordinator.joinRoomByKey() }
                Button(action: { coordinator.joinRoomByKey() }) {
                    Text(L("lobby.join"))
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
            Text(L("lobby.battle"))
                .font(.system(size: 18, weight: .black, design: .monospaced))
                .textCase(.uppercase)
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
            Text(coordinator.lobbyStatus.isEmpty ? L("lobby.searching") : coordinator.lobbyStatus)
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
            ZStack(alignment: .topLeading) {
                if let scene = coordinator.scene {
                    SpriteHostView(scene: scene)
                        .aspectRatio(GameConfig.sceneSize.width / GameConfig.sceneSize.height, contentMode: .fit)
                }
                
                // vs AI only: pause button, top-left corner.
                if coordinator.scene?.mode == .singlePlayer && !coordinator.isGamePaused {
                    Button(action: { coordinator.pauseGame() }) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 38, height: 38)
                            .overlay(
                                Image(systemName: "pause.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.black)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
                
                if coordinator.scene?.mode == .multiplayer {
                    HStack {
                        Spacer()
                        Text(coordinator.peerConnected ? "● connected" : "○ connection lost…")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(coordinator.peerConnected ? .green : .orange)
                            .padding(10)
                    }
                }
                
                if coordinator.isGamePaused {
                    PauseOverlay()
                }
            }
        }
    }
}

/// Pause menu shown over the frozen pitch (vs AI only).
struct PauseOverlay: View {
    @EnvironmentObject var coordinator: GameCoordinator
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            
            VStack(spacing: 26) {
                Text(L("pause.title"))
                    .font(.system(size: 26, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                
                Button(action: { coordinator.resumeGame() }) {
                    Text(L("pause.resume"))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                Button(action: { coordinator.returnToMenu() }) {
                    Text(L("pause.menu"))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 36)
            .padding(.horizontal, 70)
            .background(Color(white: 0.45).opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 10))
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
            Text(L("results.fulltime"))
                .font(.system(size: 36, weight: .heavy, design: .monospaced))
                .foregroundColor(.yellow)
            Text("\(coordinator.finalHome)  –  \(coordinator.finalAway)")
                .font(.system(size: 56, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            if let hp = coordinator.finalHomePens, let ap = coordinator.finalAwayPens {
                Text("(\(hp) – \(ap) \(L("results.penalties")))")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow.opacity(0.85))
            }
            
            if let stats = coordinator.homeStats {
                StatsPanel(stats: stats)
            }
            
            coachSection
                .padding(.vertical, 4)
            
            Button(action: { coordinator.returnToMenu() }) {
                Text(L("results.back"))
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
            ProgressView(L("results.coachWait"))
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
                Text(L("results.coach"))
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
            Text(L("results.stats"))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
            
            LazyVGrid(columns: columns, spacing: 14) {
                stat("WPM", "\(wpm)")
                stat("ACCURACY", "\(accuracy)%")
                stat("WORDS", "\(stats.wordsCompleted)")
                stat("DUELS W-L", "\(stats.duelsWon)-\(stats.duelsLost)")
                stat("MISTAKES", "\(stats.mistakes)")
                stat("FASTEST", fastest)
                stat("SHOTS", "\(stats.shotsScored)/\(stats.shotsTaken)")
                stat("SAVES", "\(stats.savesMade)/\(stats.savesFaced)")
                stat("BEST COMBO", "\(stats.bestCombo)")
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

// Preview
#Preview("Menu") {
    let coordinator = GameCoordinator()
    coordinator.screen = .menu
    
    return ContentView()
        .environmentObject(coordinator)
}
