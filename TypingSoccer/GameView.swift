//
//  GameView.swift
//  TypingSoccer
//
//  SwiftUI menu + SpriteKit host view + the coordinator that ties the
//  scene together with Multipeer, GameKit and Foundation Models feedback.
//

import SwiftUI
import SpriteKit
import MultipeerConnectivity

// MARK: - Coordinator

@MainActor
final class GameCoordinator: ObservableObject {

    enum Screen { case menu, lobby, playing, results }

    @Published var screen: Screen = .menu
    @Published var isHosting = false                    // lobby role (host vs joiner)
    @Published var seatNames: [Int: String] = [:]       // lobby: seat raw → player name
    @Published var mySeat: Int? = nil                   // lobby: my claimed seat
    @Published var lobbyHostTeamID: String? = nil       // lobby: host's team pick
    @Published var lobbyAwayTeamID: String? = nil       // lobby: away field player's pick
    @Published var isKeeperRole = false                 // in-match: hide the formation bar

    // Host-side lobby bookkeeping.
    private var seatOwners: [Int: MCPeerID] = [:]       // claimed seats (joiners only)
    private var awayFieldTeamID: String? = nil
    private var awayFieldFormation: Formation = .oneTwo
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
    // multiplayer YOUR TEAM is yours and the rival's pick arrives over the
    // wire during the lobby handshake (overwriting awayWCTeam).
    @Published var homeWCTeam: WCTeam = WorldCupTeams.all[0]   // France
    @Published var awayWCTeam: WCTeam = WorldCupTeams.all[1]   // Argentina

    private(set) var scene: GameScene?
    private let multipeer = MultipeerManager()

    /// Pick a formation from the UI. Applied at the next reset in-game.
    func selectFormation(_ f: Formation) {
        homeFormation = f
        scene?.setHomeFormation(f)
    }

    func startSinglePlayer() {
        multipeer.stop()
        launch(mode: .singlePlayer)
    }

    /// Multiplayer entry (2v2): both buttons open the lobby. The host owns
    /// seat 0 (its team's field player); joiners claim the other three seats.
    /// The match launches automatically once all four are filled.
    func startHosting() {
        multipeer.delegate = self
        multipeer.host()
        isHosting = true
        resetLobby()
        mySeat = PeerSeat.homeField.rawValue
        seatNames[PeerSeat.homeField.rawValue] = "\(multipeer.myPeerID.displayName) (host)"
        lobbyHostTeamID = homeWCTeam.id
        screen = .lobby
    }

    func startJoining() {
        multipeer.delegate = self
        multipeer.join()
        isHosting = false
        resetLobby()
        screen = .lobby
    }

    func cancelLobby() {
        multipeer.stop()
        resetLobby()
        screen = .menu
    }

    private func resetLobby() {
        seatNames = [:]
        seatOwners = [:]
        mySeat = nil
        lobbyHostTeamID = nil
        lobbyAwayTeamID = nil
        awayFieldTeamID = nil
        awayFieldFormation = .oneTwo
        peerConnected = false
    }

    /// Joiner: tap a free seat in the lobby.
    func claimSeat(_ raw: Int) {
        guard !isHosting, mySeat == nil, seatNames[raw] == nil else { return }
        multipeer.send(.requestSeat(seat: raw, teamID: homeWCTeam.id,
                                    formation: homeFormation.rawValue))
    }

    /// Host: broadcast the current lobby to everyone.
    private func broadcastLobbyState() {
        guard isHosting else { return }
        let filled = seatNames.keys.sorted()
        multipeer.send(.lobbyState(filledSeats: filled,
                                   names: filled.map { seatNames[$0] ?? "?" },
                                   hostTeamID: homeWCTeam.id,
                                   awayTeamID: awayFieldTeamID))
    }

    /// Host: all four seats filled — tell everyone and launch.
    private func startMatchIfReady() {
        guard isHosting, seatNames.count == PeerSeat.allCases.count else { return }
        let awayID = awayFieldTeamID ?? WorldCupTeams.all[1].id
        multipeer.send(.startMatch(homeTeamID: homeWCTeam.id, awayTeamID: awayID,
                                   homeFormation: homeFormation.rawValue,
                                   awayFormation: awayFieldFormation.rawValue))
        launchMultiplayer(homeTeamID: homeWCTeam.id, awayTeamID: awayID,
                          homeFormationRaw: homeFormation.rawValue,
                          awayFormationRaw: awayFieldFormation.rawValue)
    }

    /// Configure the scene for MY seat: my team is always the local `.home`.
    private func launchMultiplayer(homeTeamID: String, awayTeamID: String,
                                   homeFormationRaw: Int, awayFormationRaw: Int) {
        guard let seatRaw = mySeat, let seat = PeerSeat(rawValue: seatRaw) else { return }
        let myTeamID    = seat.isHome ? homeTeamID : awayTeamID
        let rivalTeamID = seat.isHome ? awayTeamID : homeTeamID
        let myForm    = Formation(rawValue: seat.isHome ? homeFormationRaw : awayFormationRaw) ?? .oneTwo
        let rivalForm = Formation(rawValue: seat.isHome ? awayFormationRaw : homeFormationRaw) ?? .oneTwo
        homeWCTeam = WorldCupTeams.team(named: myTeamID) ?? homeWCTeam
        awayWCTeam = WorldCupTeams.team(named: rivalTeamID) ?? awayWCTeam
        homeFormation = myForm
        isKeeperRole = !seat.isField
        launch(mode: .multipeer, seat: seat, rivalFormation: rivalForm)
    }

    private func launch(mode: MatchMode, seat: PeerSeat = .homeField,
                        rivalFormation: Formation? = nil) {
        let s = GameScene(size: GameConfig.sceneSize)
        s.mode = mode
        s.isNetworkHost = mode == .multipeer && multipeer.isHost
        s.localSeat = seat
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
        multipeer.stop()
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
            guard let seat = self.mySeat else { return }
            self.multipeer.send(.wordCompleted(seat: seat, mistyped: mistyped))
        }
    }

    nonisolated func formationChanged(to formation: Formation) {
        Task { @MainActor in
            self.homeFormation = formation
            if self.scene?.mode == .multipeer,
               let raw = self.mySeat, let seat = PeerSeat(rawValue: raw) {
                self.multipeer.send(.formationUpdate(homeTeam: seat.isHome,
                                                     formation: formation.rawValue))
            }
        }
    }

    nonisolated func peerSend(_ message: PeerMessage) {
        Task { @MainActor in self.multipeer.send(message) }
    }
}

extension GameCoordinator: MultipeerManagerDelegate {
    nonisolated func peersChanged(connected: [MCPeerID]) {
        Task { @MainActor in
            self.peerConnected = !connected.isEmpty
            switch self.screen {
            case .lobby:
                if self.isHosting {
                    // Free the seats of anyone who left, then re-sync everyone.
                    for (seat, owner) in self.seatOwners where !connected.contains(owner) {
                        self.seatOwners[seat] = nil
                        self.seatNames[seat] = nil
                        if seat == PeerSeat.awayField.rawValue {
                            self.awayFieldTeamID = nil
                            self.lobbyAwayTeamID = nil
                        }
                    }
                    self.broadcastLobbyState()
                } else if connected.isEmpty {
                    // Lost the host — back to searching with a clean slate.
                    self.resetLobby()
                }
            case .playing:
                // A 2v2 match needs all 4 machines. The host watches all
                // three joiners (and announces the end via `breakNow`);
                // joiners only need to notice losing the host.
                let required = self.isHosting ? MultipeerManager.requiredRemotePeers : 1
                if self.scene?.mode == .multipeer, connected.count < required {
                    self.scene?.peerDidDisconnect()
                }
            default:
                break
            }
        }
    }

    nonisolated func didReceive(_ message: PeerMessage, from peer: MCPeerID) {
        Task { @MainActor in
            switch message {

            // ---- Lobby ----
            case .requestSeat(let seat, let teamID, let formation):
                guard self.isHosting, self.screen == .lobby,
                      PeerSeat(rawValue: seat) != nil, self.seatNames[seat] == nil,
                      !self.seatOwners.values.contains(peer) else {   // one seat per player
                    self.multipeer.send(.seatDenied(seat: seat), to: [peer])
                    break
                }
                self.seatOwners[seat] = peer
                self.seatNames[seat] = peer.displayName
                if seat == PeerSeat.awayField.rawValue {
                    self.awayFieldTeamID = teamID
                    self.lobbyAwayTeamID = teamID
                    self.awayFieldFormation = Formation(rawValue: formation) ?? .oneTwo
                }
                self.multipeer.send(.seatAssigned(seat: seat), to: [peer])
                self.broadcastLobbyState()
                self.startMatchIfReady()

            case .lobbyState(let filled, let names, let hostTeamID, let awayTeamID):
                guard !self.isHosting, self.screen == .lobby else { break }
                var map: [Int: String] = [:]
                for (i, seat) in filled.enumerated() where i < names.count {
                    map[seat] = names[i]
                }
                self.seatNames = map
                self.lobbyHostTeamID = hostTeamID
                self.lobbyAwayTeamID = awayTeamID
                if let seat = self.mySeat, map[seat] == nil { self.mySeat = nil }

            case .seatAssigned(let seat):
                guard !self.isHosting, self.screen == .lobby else { break }
                self.mySeat = seat

            case .seatDenied:
                break   // lobbyState already shows who got there first

            case .startMatch(let homeTeamID, let awayTeamID, let homeF, let awayF):
                guard !self.isHosting, self.screen == .lobby, self.mySeat != nil else { break }
                self.launchMultiplayer(homeTeamID: homeTeamID, awayTeamID: awayTeamID,
                                       homeFormationRaw: homeF, awayFormationRaw: awayF)

            // ---- In-match traffic, routed into the scene ----
            // The host relays client-authored cosmetic messages so every
            // machine sees them even if the mesh between joiners is patchy.
            // (Duplicates are harmless — the handlers are idempotent, and a
            // machine ignores echoes about its own team's typist/shape.)
            case .formationUpdate(let homeTeam, let raw):
                self.scene?.applyRemoteFormationUpdate(homeTeamWire: homeTeam, raw: raw)
                if self.isHosting { self.multipeer.send(message) }
            case .typingProgress(let seat, let count):
                self.scene?.applyRemoteTypingProgress(seatRaw: seat, count: count)
                if self.isHosting { self.multipeer.send(message) }
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
            // in multiplayer the other human's own pick is used instead.
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
                menuButton("MULTIPLAYER 2v2 — HOST") { coordinator.startHosting() }
                menuButton("MULTIPLAYER 2v2 — JOIN") { coordinator.startJoining() }
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

/// 2v2 waiting room. The host owns the top-left seat; joiners tap a free
/// seat to claim it. The match starts automatically when all four are taken.
struct LobbyView: View {
    @EnvironmentObject var coordinator: GameCoordinator

    var body: some View {
        VStack(spacing: 18) {
            Text(coordinator.isHosting ? "HOSTING 2v2 MATCH" : "JOINING 2v2 MATCH")
                .font(.system(size: 28, weight: .heavy, design: .monospaced))
                .foregroundColor(.yellow)

            HStack(spacing: 26) {
                teamColumn(title: coordinator.lobbyHostTeamID ?? coordinator.homeWCTeam.id,
                           seats: [.homeField, .homeKeeper])
                Text("vs")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                teamColumn(title: coordinator.lobbyAwayTeamID ?? "— away —",
                           seats: [.awayField, .awayKeeper])
            }

            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(statusLine)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65))
            }
            .padding(.top, 4)

            Text("All four Macs must be on the same network (Wi-Fi or Bluetooth on).\nField players run the 3 outfielders; keeper players guard the goal.\nThe away FIELD seat brings its team pick from the menu.")
                .multilineTextAlignment(.center)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            Button(action: { coordinator.cancelLobby() }) {
                Text("CANCEL")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .frame(width: 200, height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow, lineWidth: 1.5))
                    .foregroundColor(.yellow)
            }
            .buttonStyle(.plain)
        }
        .padding(40)
    }

    private var statusLine: String {
        let filled = coordinator.seatNames.count
        if !coordinator.peerConnected && !coordinator.isHosting { return "Looking for a nearby host…" }
        if filled == PeerSeat.allCases.count { return "All seats filled — starting…" }
        return "\(filled)/4 seats filled — waiting for players…"
    }

    private func teamColumn(title: String, seats: [PeerSeat]) -> some View {
        VStack(spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
            ForEach(seats, id: \.rawValue) { seat in seatCard(seat) }
        }
    }

    private func seatCard(_ seat: PeerSeat) -> some View {
        let name = coordinator.seatNames[seat.rawValue]
        let isMine = coordinator.mySeat == seat.rawValue
        let claimable = !coordinator.isHosting && coordinator.mySeat == nil
            && name == nil && coordinator.peerConnected

        return Button(action: { coordinator.claimSeat(seat.rawValue) }) {
            VStack(spacing: 3) {
                Text(seat.roleLabel)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(isMine ? .yellow : .white.opacity(0.85))
                Text(name ?? (claimable ? "TAP TO CLAIM" : "— open —"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(name != nil ? .green : .white.opacity(0.45))
                    .lineLimit(1)
            }
            .frame(width: 190, height: 52)
            .background(isMine ? Color.yellow.opacity(0.15) : Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(isMine ? Color.yellow : (claimable ? Color.cyan : Color.white.opacity(0.2)),
                        lineWidth: 1.4))
        }
        .buttonStyle(.plain)
        .disabled(!claimable)
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
