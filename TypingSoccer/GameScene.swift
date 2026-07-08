//
//  GameScene.swift
//  TypingSoccer
//
//  The whole match runs here: countdown whistle → kickoff word →
//  possession → carriers auto-run to goal → defenders intercept and
//  trigger word duels → slow penalty on the loser → final duel vs the
//  goalkeeper → goal or miss → reset. Time-boxed match with a scoreboard.
//
//  Single-player: the rival side is driven by AIOpponent.
//  Multiplayer:   the rival side is driven by MultipeerManager messages.
//

import SpriteKit
import AppKit

protocol GameSceneDelegate: AnyObject {
    /// Fired when the match ends, with the local player's stats and final score.
    /// `penaltyHome`/`penaltyAway` are non-nil only if a shootout decided it.
    func matchDidFinish(homeStats: PlayerStats, homeScore: Int, awayScore: Int,
                        penaltyHome: Int?, penaltyAway: Int?)
    /// Called when the human completes a word — forwarded to peers in multiplayer.
    func localPlayerCompletedWord(mistyped: Bool)
    /// Fired when the local team's formation changes (e.g. via keyboard) so the
    /// UI can keep its picker in sync.
    func formationChanged(to formation: Formation)
    /// Ship a network message to the connected peer (multiplayer only).
    func peerSend(_ message: PeerMessage)
}

final class GameScene: SKScene {

    weak var gameDelegate: GameSceneDelegate?
    var mode: MatchMode = .singlePlayer
    /// In multiplayer, whether this machine is the authoritative host.
    var isNetworkHost = false
    /// This machine's chair. The host is always `.homeField`. Single player
    /// uses the default (the human controls the whole team).
    var localSeat: PeerSeat = .homeField
    /// Humans per team: 2 in 2v2 (field + keeper), 1 in 1v1 (one human runs the
    /// whole team, keeper included). Single player leaves this at the default.
    var teamSize: Int = 2

    /// A mirroring joiner in a multiplayer match: renders and animates
    /// locally, but every game decision comes from the host.
    private var isNetPeer: Bool { mode == .multipeer && !isNetworkHost }
    /// Single-player or multiplayer host: allowed to make game decisions.
    private var isAuthority: Bool { !isNetPeer }
    /// Does this human control the three outfielders (vs the goalkeeper)?
    private var localIsField: Bool { localSeat.isField }
    /// Is this machine's team the wire-"home" team (the host's team)?
    private var myTeamIsWireHome: Bool { localSeat.isHome }

    /// Which local nodes THIS human controls: everything in single player;
    /// in 2v2 the field player owns the outfielders, the keeper player the GK.
    private func localControls(_ node: PlayerNode) -> Bool {
        guard node.team == .home else { return false }
        // Single player, or 1v1: one human runs the entire team (keeper too).
        if mode == .singlePlayer || teamSize == 1 { return true }
        return node.isGoalkeeper ? !localIsField : localIsField
    }

    /// World Cup mode (single player): real squads whose FC 26 pace ratings
    /// drive each player's base speed. Nil = generic dummy teams.
    var homeTeam: WCTeam?
    var awayTeam: WCTeam?

    // Chosen outfield shapes. In a waiting phase (pre-match pick or countdown)
    // a change applies IMMEDIATELY; during live play it's stored as pending
    // and only applied at the next round (kickoff / half time / after a goal).
    var homeFormation: Formation = .oneTwo
    var awayFormation: Formation = .oneTwo
    private var pendingHomeFormation: Formation?

    // MARK: Nodes / state
    private let world = SKNode()
    private var hud: HUD!
    private var geometry: FieldBuilder.Geometry!

    private var homePlayers: [PlayerNode] = []
    private var awayPlayers: [PlayerNode] = []
    // Cached rosters — avoid re-concatenating / re-filtering arrays every frame.
    private var allPlayers: [PlayerNode] = []
    private var homeOutfield: [PlayerNode] = []
    private var awayOutfield: [PlayerNode] = []
    private var homeKeeper: PlayerNode!
    private var awayKeeper: PlayerNode!
    private let ball = BallNode.make()

    private var phase: GamePhase = .countdown
    private var carrier: PlayerNode?
    private var ballInFlight = false          // true while a shot is animating to goal

    // Passing (manual, via number keys 1–3)
    private var passTargetRef: PlayerNode?
    private var passTimer: TimeInterval = 0

    // Defender assignments, refreshed at most once per `defenderSwitchDelay`
    // so defenders don't jitter between targets.
    private enum DefenderRole: Equatable {
        case press, coverRunner(PlayerNode), coverMid
        static func == (lhs: DefenderRole, rhs: DefenderRole) -> Bool {
            switch (lhs, rhs) {
            case (.press, .press), (.coverMid, .coverMid): return true
            case let (.coverRunner(a), .coverRunner(b)):   return a === b
            default:                                       return false
            }
        }
    }
    private var defenderRoles: [ObjectIdentifier: DefenderRole] = [:]
    // Target-switch debounce: when the ideal marking differs from the current
    // one, wait `defenderSwitchDelay` before re-checking. If it still differs,
    // switch instantly; if the situation resolved itself, cancel.
    private var switchPending = false
    private var switchTimer: TimeInterval = 0

    // Offside. Each off-ball runner walks a small state machine:
    // normal → (offside past grace) → retreating (0.5s jog back) →
    // waiting (hold until onside for 0.2s) → normal again.
    private enum OffsideRunState {
        case normal(offsideTime: TimeInterval)
        case retreating(remaining: TimeInterval)
        case waiting(onsideTime: TimeInterval)
    }
    private var offsideStates: [ObjectIdentifier: OffsideRunState] = [:]
    private let offsideLineNode = SKShapeNode()
    // Pre-built line paths at x = 0; the node is MOVED each frame instead of
    // assigning a new path (SKShapeNode re-tessellates on every path change).
    private var liveOffsidePath: CGPath?
    private var whistleOffsidePath: CGPath?
    private var offsideLineLiveStyle = false
    private var carrierMustPass = false        // free-kick taker must pass before dribbling

    /// If set, the post-countdown restart hands the ball straight to this team
    /// (used after a goal) instead of running the opening word contest.
    private var restartWithBallFor: Team?

    // Duel bookkeeping
    private let typing = TypingController()
    private let ai = AIOpponent()
    private var duelKind: DuelKind = .kickoff
    private var duelAttacker: PlayerNode?     // carrier / shooter (nil for kickoff)
    private var duelDefender: PlayerNode?     // interceptor / goalkeeper
    // Per-duel completion. Each side's flag is set by the participating human
    // on this machine (always "home" locally) or by a network message from
    // whichever seat controls the participating node.
    private var homeDuelDone = false
    private var awayDuelDone = false
    private var homeDuelMistyped = false
    private var awayDuelMistyped = false
    private var duelResolved = false

    /// Defensive chase override (rule: the defending field player picks which
    /// outfielder presses the carrier). Keyed by the DEFENDING team; cleared
    /// whenever possession changes.
    private var chaseChoice: [Team: Lane] = [:]

    // Network event buffering (joiner side). Events that arrive while this
    // scene is mid-countdown or mid-break are held and applied when the
    // waiting phase ends, keeping presentation in step with the host.
    private var pendingRemoteDuel: (kind: DuelKind, word: String,
                                    attacker: PlayerNode?, defender: PlayerNode?)?
    private var pendingRemotePossession: (player: PlayerNode, x: CGFloat,
                                          y: CGFloat, mustPass: Bool)?
    /// True while the joiner plays out a local animation (e.g. the offside
    /// whistle) that must finish before the next possession is applied.
    private var holdingPossessionEvents = false

    // Stats & score
    private var homeStats = PlayerStats()
    private var awayScore = 0
    private var homeScore = 0

    // Clocks
    private var statPanelAccumulator: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0
    private var elapsed: TimeInterval = 0            // real seconds of play so far

    /// Where we are in the match: regular halves, extra-time halves (played
    /// only if the score is level after 90'), or the penalty shootout.
    private enum MatchStage { case regular1, regular2, et1, et2, shootout }
    private var stage: MatchStage = .regular1

    // Stoppage / added time. When the clock hits a break point we don't stop
    // immediately — we play on (shown as "+N") until a shot is taken or the
    // cutoff passes (10s regular → up to +5, 6s extra time → up to +3).
    private enum BreakKind { case half, full, etHalf, etFull }
    private var pendingBreak: BreakKind?
    private var addedTimeElapsed: TimeInterval = 0

    // Penalty shootout bookkeeping.
    private var penHome = 0
    private var penAway = 0
    private var homeKicks = 0
    private var awayKicks = 0
    private var currentKicker: Team = .home
    /// Goal used for EVERY kick of the shootout (picked at random once).
    private var penGoalRight = true
    /// If set, the next countdown runs this instead of the kickoff logic
    /// (used for the 3s countdown before each penalty).
    private var countdownCompletion: (() -> Void)?
    private var countdownRemaining = Double(GameConfig.countdownSeconds)
    private var countdownShown = -1

    // Pre-match formation pick window.
    private var strategyRemaining: TimeInterval = 0
    private var strategyShown = -1

    /// Which end each team attacks this half. Flips at half time.
    private var homeAttacksRight = true

    // MARK: Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.03, green: 0.05, blue: 0.09, alpha: 1)
        scaleMode = .aspectFit
        addChild(world)

        geometry = FieldBuilder.build(in: world, sceneSize: size)
        hud = HUD(sceneSize: size)
        addChild(hud)
        if let home = homeTeam, let away = awayTeam {
            hud.setTeamNames(home: home.name, away: away.name)
        }

        offsideLineNode.zPosition = 30
        offsideLineNode.isHidden = true
        world.addChild(offsideLineNode)

        // Build the two dashed line paths once (at x = 0, spanning the pitch).
        let linePath = CGMutablePath()
        linePath.move(to: CGPoint(x: 0, y: geometry.rect.minY))
        linePath.addLine(to: CGPoint(x: 0, y: geometry.rect.maxY))
        liveOffsidePath = linePath.copy(dashingWithPhase: 0, lengths: [6, 9])
        whistleOffsidePath = linePath.copy(dashingWithPhase: 0, lengths: [9, 6])

        world.addChild(ball)
        spawnTeams()
        resetFormation()
        ball.isHidden = true

        // Single-player opens with a 5s formation-pick window; multiplayer
        // keeps the straight countdown so both peers stay in sync.
        if mode == .singlePlayer { startStrategyPick() } else { startCountdown() }
        // Ensure we receive key events.
        view.window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: Team setup

    private func laneY(_ lane: Lane) -> CGFloat { geometry.laneY[lane.rawValue] }

    /// Which end a team attacks this half (sides swap at half time).
    private func attacksRight(_ team: Team) -> Bool {
        team == .home ? homeAttacksRight : !homeAttacksRight
    }

    /// Triangle formation in the team's OWN half: the two wing players
    /// (top & bottom lanes) push forward toward halfway, the central player
    /// sits deeper. Automatically mirrors when the team switches ends.
    private func formationX(for team: Team, lane: Lane) -> CGFloat {
        let form = (team == .home) ? homeFormation : awayFormation
        let frac = form.depthFraction(for: lane)
        return attacksRight(team) ? geometry.rect.minX + geometry.rect.width * frac
                                  : geometry.rect.maxX - geometry.rect.width * frac
    }

    /// Change the local team's formation. In a waiting phase (pre-match pick
    /// or countdown) the players slide to their new spots immediately; once
    /// the ball is live the change is queued and applied at the next round.
    func setHomeFormation(_ f: Formation) {
        guard stage != .shootout else { return }   // no formations during penalties
        guard mode == .singlePlayer || localIsField else { return }   // keepers don't set shapes
        guard (pendingHomeFormation ?? homeFormation) != f else { return }
        switch phase {
        case .strategyPick, .countdown:
            homeFormation = f
            pendingHomeFormation = nil
            applyHomeFormationPositions(animated: true)
            hud?.showToast("FORMATION \(f.label)")
        default:
            pendingHomeFormation = f
            hud?.showToast("FORMATION \(f.label) — NEXT ROUND")
        }
        gameDelegate?.formationChanged(to: f)
    }

    /// Slide the home outfielders to their formation spots (waiting phases only).
    private func applyHomeFormationPositions(animated: Bool) {
        for p in outfield(homePlayers) {
            let spot = CGPoint(x: formationX(for: .home, lane: p.lane),
                               y: formationY(for: .home, lane: p.lane))
            if animated {
                let slide = SKAction.move(to: spot, duration: 0.25)
                slide.timingMode = .easeOut
                p.run(slide)
            } else {
                p.position = spot
            }
        }
    }

    /// Step through formations with the arrow keys.
    private func cycleFormation(_ delta: Int) {
        let all = Formation.allCases
        guard let idx = all.firstIndex(of: pendingHomeFormation ?? homeFormation) else { return }
        setHomeFormation(all[(idx + delta + all.count) % all.count])
    }

    /// Row (y) a player lines up on at reset. Normally its lane row, but the
    /// 1-1-1 shape stacks all three on the central axis (like the keeper).
    private func formationY(for team: Team, lane: Lane) -> CGFloat {
        let form = (team == .home) ? homeFormation : awayFormation
        return form == .oneOneOne ? geometry.rect.midY : laneY(lane)
    }

    /// Where a team's goalkeeper stands (out in front of its own goal line).
    private func keeperX(for team: Team) -> CGFloat {
        attacksRight(team) ? geometry.rect.minX + GameConfig.keeperStandoff
                           : geometry.rect.maxX - GameConfig.keeperStandoff
    }

    private func spawnTeams() {
        let homeRoster = homeTeam?.players    // [top, mid, bottom, GK] or nil
        let awayRoster = awayTeam?.players
        for lane in Lane.allCases {
            let hp = homeRoster?[lane.rawValue]
            let ap = awayRoster?[lane.rawValue]
            let h = PlayerNode(team: .home, role: .outfield(lane),
                               baseSpeed: hp.map { WorldCupTeams.outfieldSpeed(pace: $0.pace) } ?? GameConfig.baseCarrierSpeed,
                               playerName: hp?.name)
            let a = PlayerNode(team: .away, role: .outfield(lane),
                               baseSpeed: ap.map { WorldCupTeams.outfieldSpeed(pace: $0.pace) } ?? GameConfig.baseCarrierSpeed,
                               playerName: ap?.name)
            homePlayers.append(h); awayPlayers.append(a)
            world.addChild(h); world.addChild(a)
        }
        let hgk = homeRoster?[3]
        let agk = awayRoster?[3]
        let hk = PlayerNode(team: .home, role: .goalkeeper,
                            baseSpeed: hgk.map { WorldCupTeams.keeperSpeed(gkSpeed: $0.pace) } ?? GameConfig.baseDefenderSpeed,
                            playerName: hgk?.name)
        let ak = PlayerNode(team: .away, role: .goalkeeper,
                            baseSpeed: agk.map { WorldCupTeams.keeperSpeed(gkSpeed: $0.pace) } ?? GameConfig.baseDefenderSpeed,
                            playerName: agk?.name)
        homePlayers.append(hk); awayPlayers.append(ak)
        world.addChild(hk); world.addChild(ak)

        // Cache the derived rosters once — they never change mid-match.
        homeKeeper = hk
        awayKeeper = ak
        homeOutfield = homePlayers.filter { !$0.isGoalkeeper }
        awayOutfield = awayPlayers.filter { !$0.isGoalkeeper }
        allPlayers = homePlayers + awayPlayers
    }

    private func outfield(_ team: [PlayerNode]) -> [PlayerNode] { team.filter { !$0.isGoalkeeper } }
    private func keeper(_ team: [PlayerNode]) -> PlayerNode { team.first { $0.isGoalkeeper }! }

    private func resetFormation() {
        // A formation picked during live play lands here, at the next round.
        if let f = pendingHomeFormation {
            homeFormation = f
            pendingHomeFormation = nil
        }
        for p in allPlayers {
            p.setHasBall(false)     // energy deliberately NOT reset — it lasts the match
            if p.isGoalkeeper {
                p.position = CGPoint(x: keeperX(for: p.team), y: geometry.rect.midY)
            } else {
                p.position = CGPoint(x: formationX(for: p.team, lane: p.lane),
                                     y: formationY(for: p.team, lane: p.lane))
            }
        }
        carrier = nil
        passTargetRef = nil
        passTimer = 0
        carrierMustPass = false
        offsideStates.removeAll()
        offsideLineNode.isHidden = true
        ball.position = CGPoint(x: geometry.rect.midX, y: geometry.rect.midY)
    }

    // MARK: Pre-match formation pick

    private func startStrategyPick() {
        phase = .strategyPick
        strategyRemaining = TimeInterval(GameConfig.strategyPickSeconds)
        strategyShown = -1
        hud.showStatus("PICK FORMATION ← →   \(GameConfig.strategyPickSeconds)", fontSize: 34)
    }

    private func updateStrategyPick(_ dt: TimeInterval) {
        strategyRemaining -= dt
        let shown = Int(ceil(strategyRemaining))
        if shown != strategyShown && shown > 0 {
            strategyShown = shown
            hud.showStatus("PICK FORMATION ← →   \(shown)", fontSize: 34)
        }
        if strategyRemaining <= 0 {
            hud.hideStatus()
            hud.showToast("FORMATION \(homeFormation.label) LOCKED")
            startCountdown()
        }
    }

    // MARK: Countdown

    private func startCountdown() {
        phase = .countdown
        countdownRemaining = Double(GameConfig.countdownSeconds)
        countdownShown = -1
        hud.showStatus("\(GameConfig.countdownSeconds)")
    }

    private func beginKickoffDuel() {
        Audio.whistle()
        startDuel(kind: .kickoff, attacker: nil, defender: nil, intensity: 0.2)
        hud.showStatus("TYPE!", fontSize: 40)
        run(.sequence([.wait(forDuration: 0.6), .run { [weak self] in self?.hud.hideStatus() }]))
    }

    // MARK: Duels

    /// Authority only: pick the word, tell the peer (multiplayer), start the duel.
    private func startDuel(kind: DuelKind, attacker: PlayerNode?, defender: PlayerNode?, intensity: Double) {
        // The final shot uses a long, high-pressure word (8–12 letters).
        let word = (kind == .shot) ? WordProvider.shotWord()
                                   : WordProvider.word(intensity: intensity)
        if isNetworkHost {
            broadcast(.duelStart(kind: kind.netCode, word: word,
                                 attacker: attacker.map(playerRef),
                                 defender: defender.map(playerRef)))
        }
        beginDuel(kind: kind, word: word, attacker: attacker, defender: defender)
        if mode == .singlePlayer {
            // Away difficulty: keeper shots are a touch harder.
            let skill: Double = (kind == .shot && (defender?.team == .away)) ? 0.75 : 0.5
            ai.begin(word: word, skill: skill)
        }
    }

    /// Shared duel setup — used by the authority directly and by the joiner
    /// when the host's `duelStart` message arrives.
    private func beginDuel(kind: DuelKind, word: String, attacker: PlayerNode?, defender: PlayerNode?) {
        duelKind = kind
        duelAttacker = attacker
        duelDefender = defender
        passTargetRef = nil          // cancel any pending pass while battling
        passTimer = 0
        homeDuelDone = false
        awayDuelDone = false
        homeDuelMistyped = false
        awayDuelMistyped = false
        duelResolved = false
        typing.begin(word: word)
        phase = .duel(kind)
        offsideLineNode.isHidden = true      // hide the live line while play is frozen
        hud.showPrompt(typed: "", remaining: word)
        hud.updateEnemyProgress(word: word, typedCount: 0)
    }

    /// Does THIS human type in the current duel? (Their controlled unit —
    /// outfielders or goalkeeper — must be a participant. Kickoff words are
    /// contested by the two field players.)
    private var localTypesThisDuel: Bool {
        if duelKind == .kickoff { return mode == .singlePlayer || teamSize == 1 || localIsField }
        if let a = duelAttacker, localControls(a) { return true }
        if let d = duelDefender, localControls(d) { return true }
        return false
    }

    /// Host-side: which seat controls a node (host frame == wire frame).
    private func controllerSeat(of node: PlayerNode) -> PeerSeat {
        switch (node.team == .home, node.isGoalkeeper) {
        case (true, false):  return .homeField
        // In 1v1 the keeper is run by the same human as the outfielders.
        case (true, true):   return teamSize == 1 ? .homeField : .homeKeeper
        case (false, false): return .awayField
        case (false, true):  return teamSize == 1 ? .awayField : .awayKeeper
        }
    }

    /// Host-side: may this seat submit a completion for the current duel?
    private func seatParticipates(_ seat: PeerSeat) -> Bool {
        if duelKind == .kickoff { return seat.isField }
        if let a = duelAttacker, controllerSeat(of: a) == seat { return true }
        if let d = duelDefender, controllerSeat(of: d) == seat { return true }
        return false
    }

    /// How a shot/penalty duel ends once the winner is known.
    private enum ShotOutcome: Int {
        case goal = 0, wide = 1, saved = 2
    }

    /// Decide a shot's fate (authority only). Mirrors the original rules:
    /// a mistyped shot sails wide (in the shootout only if the keeper didn't
    /// win outright), and the single-player AI can fluff its own shot.
    private func computeShotOutcome(winner: Team) -> ShotOutcome {
        let shooter = duelAttacker!
        let shooterMistyped = shooter.team == .home ? homeDuelMistyped
                                                    : (mode == .multipeer && awayDuelMistyped)
        if winner != shooter.team {
            // Keeper was faster. In open play a mistype still means "wide";
            // in the shootout the save stands regardless.
            if stage != .shootout && shooterMistyped { return .wide }
            return .saved
        }
        if shooterMistyped { return .wide }
        if mode == .singlePlayer && shooter.team == .away
            && Double.random(in: 0...1) < GameConfig.aiShotMissChance { return .wide }
        return .goal
    }

    /// Resolve who won (authority only), tell the peer, apply consequences.
    private func resolveDuel(winner: Team) {
        guard !duelResolved else { return }
        duelResolved = true
        let outcome: ShotOutcome? = (duelKind == .shot) ? computeShotOutcome(winner: winner) : nil
        if isNetworkHost {
            broadcast(.duelResult(winnerHome: wireHome(for: winner), shotOutcome: outcome?.rawValue))
        }
        applyDuelResolution(winner: winner, outcome: outcome)
    }

    /// Apply a resolved duel — runs on the authority right away and on the
    /// joiner when the host's `duelResult` message arrives.
    private func applyDuelResolution(winner: Team, outcome: ShotOutcome?) {
        hud.hidePrompt()

        // Record the local human's typing effort — only if they actually
        // took part in this duel (in 2v2 half the duels are someone else's).
        if localTypesThisDuel {
            homeStats.record(word: typing.target,
                             seconds: max(0.001, typing.elapsedSeconds),
                             mistakes: typing.mistakes)
            if winner == .home { homeStats.duelsWon += 1 } else { homeStats.duelsLost += 1 }
        }
        defer {
            ai.reset()
            typing.reset()
        }

        // Penalty shootout kicks resolve through their own path.
        if stage == .shootout {
            applyPenaltyOutcome(outcome ?? .saved)
            return
        }

        switch duelKind {
        case .kickoff:
            if isAuthority {
                giveBallToRandomOutfielder(of: winner)
                beginRunning()
            } else {
                phase = .kickoff     // wait for the host's possession message
            }

        case .interception:
            let attacker = duelAttacker!     // current carrier
            let defender = duelDefender!     // interceptor
            if winner == attacker.team {
                // Carrier keeps the ball; defender is beaten and slowed.
                defender.applySlow()
            } else {
                // Turnover: defender wins the ball; old carrier slowed.
                attacker.applySlow()
                setCarrier(defender)
            }
            beginRunning()

        case .shot:
            let shooter = duelAttacker!
            let gk = duelDefender!
            switch outcome ?? .saved {
            case .goal:  shootBall(scored: true, shooter: shooter)
            case .wide:  shootBall(scored: false, shooter: shooter)
            case .saved: keeperCatch(keeper: gk, shooter: shooter)
            }
        }
    }

    private func celebrateGoal(scoringTeam: Team) {
        phase = .goalScored(scoringTeam)
        hud.showStatus(scoringTeam == .home ? "GOAL!" : "RIVAL SCORES", fontSize: 48)
        run(.sequence([.wait(forDuration: 1.4), .run { [weak self] in
            guard let self else { return }
            // A network break/match-end may have preempted the celebration.
            guard case .goalScored = self.phase else { return }
            self.hud.hideStatus()
            // If this shot came in added time, the half/match ends now.
            if self.pendingBreak != nil { self.triggerBreak(); return }
            self.resetFormation()
            // The conceding team restarts with the ball, after a countdown.
            self.restartWithBallFor = scoringTeam.opponent
            self.startCountdown()
        }]))
    }

    // MARK: Half time / extra time

    /// Shared stoppage: freeze play, show `title` for 2s, then run `then`.
    private func stopPlayForBreak(title: String, then: @escaping () -> Void) {
        phase = .halftime
        hud.hidePrompt()
        carrier?.setHasBall(false)
        carrier = nil
        passTargetRef = nil
        passTimer = 0
        ball.isHidden = true
        Audio.whistle()
        hud.showStatus(title, fontSize: 46)
        run(.sequence([.wait(forDuration: 2.0), .run { [weak self] in
            guard let self else { return }
            self.hud.hideStatus()
            then()
        }]))
    }

    /// Breaks give every player a partial energy top-up (the only recovery
    /// outside of standing still in open play).
    private func restoreEnergyForBreak() {
        for p in allPlayers { p.restoreEnergy(GameConfig.energyBreakRestore) }
    }

    /// After a break, the authority opens the next period with a kickoff duel;
    /// the joiner stands by for the host's `duelStart` word instead.
    private func resumeAfterBreak() {
        if isAuthority {
            beginKickoffDuel()
        } else {
            phase = .kickoff
            drainPendingNetEvents()
        }
    }

    private func startHalftime() {
        if isNetworkHost { broadcast(.breakNow(kind: 0, shootoutGoalRight: nil)) }
        stopPlayForBreak(title: "HALF TIME") { [weak self] in
            guard let self else { return }
            self.stage = .regular2
            self.restoreEnergyForBreak()
            self.homeAttacksRight.toggle()   // switch ends for the second half
            self.resetFormation()
            self.resumeAfterBreak()
        }
    }

    /// 90' ended level: play two 15-minute extra-time halves.
    private func startExtraTime() {
        if isNetworkHost { broadcast(.breakNow(kind: 1, shootoutGoalRight: nil)) }
        stopPlayForBreak(title: "EXTRA TIME") { [weak self] in
            guard let self else { return }
            self.stage = .et1
            self.restoreEnergyForBreak()
            self.resetFormation()
            self.resumeAfterBreak()
        }
    }

    /// Break between the two extra-time halves (teams switch ends again).
    private func startEtHalftime() {
        if isNetworkHost { broadcast(.breakNow(kind: 2, shootoutGoalRight: nil)) }
        stopPlayForBreak(title: "ET HALF TIME") { [weak self] in
            guard let self else { return }
            self.stage = .et2
            self.restoreEnergyForBreak()
            self.homeAttacksRight.toggle()
            self.resetFormation()
            self.resumeAfterBreak()
        }
    }

    // MARK: Penalty shootout

    /// Still level after extra time: 3 kicks each (all outfielders), then the
    /// goalkeepers, then the order loops back to the first taker — sudden
    /// death after the first 3. Every kick is a typing battle preceded by a
    /// 3-second countdown. One randomly chosen goal hosts the whole shootout.
    private func startPenaltyShootout() {
        penHome = 0; penAway = 0
        homeKicks = 0; awayKicks = 0
        if isAuthority {
            penGoalRight = Bool.random()         // same goalpost for every kick
        }                                        // joiner: already set from the host's message
        if isNetworkHost { broadcast(.breakNow(kind: 3, shootoutGoalRight: penGoalRight)) }
        hud.setPenaltyTally(home: 0, away: 0)
        hud.setStatPanelsHidden(true)
        stopPlayForBreak(title: "PENALTY SHOOTOUT") { [weak self] in
            guard let self else { return }
            self.stage = .shootout
            // The host's team (wire-"home") always kicks first — map that
            // onto this machine's local sides.
            self.setupPenalty(kicker: self.localTeam(wireHome: true))
        }
    }

    /// Kick order: the three outfielders, then the goalkeeper, then loop.
    private func penaltyTaker(for team: Team) -> PlayerNode {
        let order = team == .home ? homePlayers : awayPlayers   // [top, mid, bottom, GK]
        let taken = team == .home ? homeKicks : awayKicks
        return order[taken % order.count]
    }

    /// Arrange the pitch for one penalty: ball on the spot, shooter a run-up
    /// behind it, rival keeper on the chosen goal's line, everyone else back
    /// at halfway. Then the 3s countdown into the typing battle.
    private func setupPenalty(kicker: Team) {
        currentKicker = kicker
        phase = .halftime   // neutral freeze while we stage the kick

        let shooter = penaltyTaker(for: kicker)
        let gk = keeper(kicker == .home ? awayPlayers : homePlayers)
        let toRight = penGoalRight
        let spotX = toRight ? geometry.rect.maxX - GameConfig.penaltyDepth
                            : geometry.rect.minX + GameConfig.penaltyDepth
        let spot = CGPoint(x: spotX, y: geometry.rect.midY)

        // Everyone not involved waits around the halfway line.
        for p in allPlayers where p !== shooter && p !== gk {
            if p.isGoalkeeper {
                p.position = CGPoint(x: keeperX(for: p.team), y: geometry.rect.midY)
            } else {
                let side: CGFloat = p.team == kicker ? -70 : 70
                p.position = CGPoint(x: geometry.rect.midX + (toRight ? side : -side),
                                     y: laneY(p.lane))
            }
        }
        // Ball waits on the spot; the shooter stands a run-up behind it.
        carrier = nil
        ball.position = spot
        ball.isHidden = false
        let backOff: CGFloat = toRight ? -GameConfig.penaltyRunUpDistance
                                       :  GameConfig.penaltyRunUpDistance
        shooter.position = CGPoint(x: spotX + backOff, y: geometry.rect.midY)
        shooter.setHasBall(true)   // highlight ring marks the taker
        gk.position = CGPoint(x: toRight ? geometry.rect.maxX - GameConfig.keeperStandoff
                                         : geometry.rect.minX + GameConfig.keeperStandoff,
                              y: geometry.rect.midY)

        hud.showStatus(kicker == .home ? "PENALTY — YOU" : "PENALTY — RIVAL", fontSize: 36)
        run(.sequence([.wait(forDuration: 1.2), .run { [weak self, weak shooter, weak gk] in
            guard let self, let shooter, let gk else { return }
            self.countdownCompletion = { [weak self] in
                guard let self else { return }
                if self.isAuthority {
                    Audio.whistle()
                    self.startDuel(kind: .shot, attacker: shooter, defender: gk, intensity: 0.85)
                } else {
                    self.phase = .kickoff       // await the host's penalty word
                }
            }
            self.startCountdown()
        }]))
    }

    /// Play out one penalty's decided outcome. Unlike open play, a mistyped
    /// letter does NOT end the kick immediately — the result is only revealed
    /// at the moment of the kick, after the shooter's run-up.
    private func applyPenaltyOutcome(_ outcome: ShotOutcome) {
        let shooter = duelAttacker!
        let gk = duelDefender!
        runUpThenKick(shooter: shooter) { [weak self] in
            guard let self else { return }
            switch outcome {
            case .saved: self.penaltySaved(keeper: gk)
            case .goal:  self.shootBall(scored: true, shooter: shooter)
            case .wide:  self.shootBall(scored: false, shooter: shooter)
            }
        }
    }

    /// The little run-up: the shooter jogs from its mark to the ball, THEN
    /// the kick happens and the outcome plays out.
    private func runUpThenKick(shooter: PlayerNode, then: @escaping () -> Void) {
        phase = .goalScored(shooter.team)   // neutral while the run-up animates
        let runUp = SKAction.move(to: ball.position, duration: GameConfig.penaltyRunUpDuration)
        runUp.timingMode = .easeIn
        shooter.run(runUp) { [weak shooter] in
            shooter?.setHasBall(false)
            then()
        }
    }

    /// The keeper out-typed the shooter: pull the ball in, then next kick.
    private func penaltySaved(keeper gk: PlayerNode) {
        carrier?.setHasBall(false)
        carrier = nil
        ballInFlight = true
        ball.isHidden = false
        phase = .goalScored(gk.team)   // neutral pause while the ball travels
        hud.showStatus("SAVED!", fontSize: 44)
        let travel = SKAction.move(to: gk.position, duration: GameConfig.keeperCatchDuration)
        travel.timingMode = .easeOut
        ball.run(travel) { [weak self] in
            guard let self else { return }
            self.ballInFlight = false
            self.run(.sequence([.wait(forDuration: 0.9), .run { [weak self] in
                self?.hud.hideStatus()
                self?.penaltyKickFinished(scored: false)
            }]))
        }
    }

    /// Book one kick's result, then either crown a winner or stage the next kick.
    private func penaltyKickFinished(scored: Bool) {
        if currentKicker == .home {
            homeKicks += 1
            if scored { penHome += 1 }
        } else {
            awayKicks += 1
            if scored { penAway += 1 }
        }
        hud.setPenaltyTally(home: penHome, away: penAway)

        if let winner = shootoutWinner() {
            endShootout(winner: winner)
            return
        }
        let next = currentKicker.opponent
        run(.sequence([.wait(forDuration: 1.0), .run { [weak self] in
            self?.setupPenalty(kicker: next)
        }]))
    }

    /// Decided? Within the first 3 each (all outfielders): over as soon as one
    /// side can't be caught. After that: sudden death (GK kicks 4th, then the
    /// order loops back to the first taker), decided after each complete pair.
    private func shootoutWinner() -> Team? {
        let per = GameConfig.penaltyKicksPerSide
        if homeKicks <= per && awayKicks <= per {
            let remHome = per - homeKicks
            let remAway = per - awayKicks
            if penHome > penAway + remAway { return .home }
            if penAway > penHome + remHome { return .away }
        }
        if homeKicks >= per && awayKicks >= per && homeKicks == awayKicks && penHome != penAway {
            return penHome > penAway ? .home : .away
        }
        return nil
    }

    private func endShootout(winner: Team) {
        Audio.whistle()
        hud.showStatus(winner == .home ? "YOU WIN ON PENALTIES!" : "RIVAL WINS ON PENALTIES",
                       fontSize: 38)
        run(.sequence([.wait(forDuration: 2.2), .run { [weak self] in
            self?.endMatch()
        }]))
    }

    // MARK: Shooting

    /// Animate the ball toward the goal after the final keeper duel.
    /// `scored` true → into the net; false → sails wide (a mistyped shot).
    private func shootBall(scored: Bool, shooter: PlayerNode) {
        // Shootout kicks all go at the one randomly chosen goal.
        let toRight = stage == .shootout ? penGoalRight : attacksRight(shooter.team)

        // Detach the ball from the shooter so it can fly on its own.
        carrier?.setHasBall(false)
        carrier = nil
        ballInFlight = true
        ball.isHidden = false
        phase = .goalScored(shooter.team)   // neutral phase while the ball is in flight

        let goalLineX = toRight ? geometry.rect.maxX : geometry.rect.minX
        let beyond: CGFloat = toRight ? 20 : -20
        let target: CGPoint
        if scored {
            // Into the middle of the goal mouth, just past the line.
            target = CGPoint(x: goalLineX + beyond, y: geometry.rect.midY)
        } else {
            // Wide of the post: outside the goal mouth vertically.
            let mouthHalf = geometry.rect.height * 0.15
            let dir: CGFloat = Bool.random() ? 1 : -1
            target = CGPoint(x: goalLineX + beyond, y: geometry.rect.midY + dir * (mouthHalf + 45))
        }

        Audio.tick()   // "kick" — swap for a real SFX later
        let kick = SKAction.move(to: target, duration: 0.45)
        kick.timingMode = .easeOut
        ball.run(kick) { [weak self] in
            guard let self else { return }
            self.ballInFlight = false
            guard self.phase != .finished else { return }   // match ended mid-flight
            if scored { self.finishGoal(scoringTeam: shooter.team) }
            else { self.finishMiss(shooter: shooter) }
        }
    }

    /// The goalkeeper out-typed the shooter: the ball is pulled quickly into
    /// the keeper's hands (like a fast pass) and the keeper's team takes over.
    private func keeperCatch(keeper gk: PlayerNode, shooter: PlayerNode) {
        carrier?.setHasBall(false)
        carrier = nil
        ballInFlight = true
        ball.isHidden = false
        phase = .goalScored(gk.team)   // neutral pause while the ball travels
        hud.showStatus("SAVED!", fontSize: 44)

        let travel = SKAction.move(to: gk.position, duration: GameConfig.keeperCatchDuration)
        travel.timingMode = .easeOut
        ball.run(travel) { [weak self, weak gk] in
            guard let self else { return }
            self.ballInFlight = false
            // A network break/match-end may have preempted the restart.
            guard case .goalScored = self.phase else { return }
            self.hud.hideStatus()
            if self.pendingBreak != nil { self.triggerBreak(); return }
            guard let gk else { return }
            // The keeper never dribbles out of its area — it must distribute.
            self.carrierMustPass = true    // set BEFORE setCarrier so the broadcast carries it
            self.setCarrier(gk)
            self.beginRunning()
            if self.mode == .singlePlayer && gk.team == .away {
                self.run(.sequence([.wait(forDuration: 0.8), .run { [weak self] in
                    self?.aiFreeKickPass()
                }]))
            }
        }
    }

    private func finishGoal(scoringTeam: Team) {
        // A converted penalty in the shootout counts on the pens tally only.
        if stage == .shootout {
            Audio.whistle()
            hud.showStatus("GOAL!", fontSize: 44)
            run(.sequence([.wait(forDuration: 1.0), .run { [weak self] in
                self?.hud.hideStatus()
                self?.penaltyKickFinished(scored: true)
            }]))
            return
        }
        if scoringTeam == .home { homeScore += 1; homeStats.goals += 1 } else { awayScore += 1 }
        hud.updateScore(home: homeScore, away: awayScore)
        Audio.whistle()
        celebrateGoal(scoringTeam: scoringTeam)
    }

    private func finishMiss(shooter: PlayerNode) {
        hud.showStatus("MISS!", fontSize: 44)
        run(.sequence([.wait(forDuration: 1.0), .run { [weak self] in
            guard let self else { return }
            // A network break/match-end may have preempted this restart.
            guard case .goalScored = self.phase else { return }
            self.hud.hideStatus()
            // A missed penalty in the shootout just moves to the next kick.
            if self.stage == .shootout { self.penaltyKickFinished(scored: false); return }
            if self.pendingBreak != nil { self.triggerBreak(); return }
            self.resetFormation()
            self.ball.isHidden = false
            // Possession resets to the OTHER side after the ball goes out.
            if self.isAuthority {
                self.giveBallToRandomOutfielder(of: shooter.team.opponent)
                self.beginRunning()
            }
            // Joiner: the host's possession message assigns the new carrier.
        }]))
    }

    // MARK: Possession helpers

    private func giveBallToRandomOutfielder(of team: Team) {
        let players = outfield(team == .home ? homePlayers : awayPlayers)
        let chosen = players.randomElement()!
        setCarrier(chosen)
    }

    private func setCarrier(_ player: PlayerNode) {
        carrier?.setHasBall(false)
        carrier = player
        player.setHasBall(true)
        ball.isHidden = false
        passTargetRef = nil
        passTimer = 0
        // Every authoritative possession change is mirrored to the joiner,
        // including the carrier's position so the two sims re-align.
        if isNetworkHost {
            broadcast(.possession(player: playerRef(player),
                                  x: Double(player.position.x),
                                  y: Double(player.position.y),
                                  mustPass: carrierMustPass))
        }
    }

    private func beginRunning() {
        phase = .running
        // Force a fresh defensive assignment as soon as play resumes,
        // and restart every runner's offside state for the new situation.
        defenderRoles.removeAll()
        offsideStates.removeAll()
        chaseChoice.removeAll()      // chase picks last one possession
        switchPending = false
        switchTimer = 0
    }

    /// Enter stoppage time (authority only) and tell the joiner.
    private func enterAddedTime(_ brk: BreakKind) {
        pendingBreak = brk
        addedTimeElapsed = 0
        hud.showToast("ADDED TIME")
        if isNetworkHost { broadcast(.addedTime) }
    }

    /// Execute a pending stoppage (after the shot, or the added-time cutoff).
    /// 90' draw → extra time. Extra-time draw → penalty shootout.
    private func triggerBreak() {
        guard let brk = pendingBreak else { return }
        pendingBreak = nil
        addedTimeElapsed = 0
        switch brk {
        case .half:
            startHalftime()
        case .full:
            if homeScore == awayScore { startExtraTime() } else { endMatch() }
        case .etHalf:
            startEtHalftime()
        case .etFull:
            if homeScore == awayScore { startPenaltyShootout() } else { endMatch() }
        }
    }

    // MARK: Update loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 1.0 / 20.0)
        lastUpdate = currentTime

        switch phase {
        case .strategyPick: updateStrategyPick(dt)
        case .countdown:  updateCountdown(dt)
        case .duel:       updateDuel(dt)
        case .running:    updateRunning(dt)
        case .kickoff, .goalScored, .halftime, .finished: break
        }

        // Slow-penalty recovery only advances while the ball is in open play.
        // During a battle everything on the pitch is frozen, including the
        // 3-second cooldown of a beaten defender.
        if case .running = phase {
            for p in allPlayers { p.tickSlow(deltaTime: dt) }
        }

        // Energy: ticks only while the ball is in open play — drains for anyone
        // who ran this frame, regenerates for anyone standing still. Outside
        // open play energy is frozen; only half-time / extra-time breaks give
        // back a chunk. Single-player only (peers can't sync stamina yet).
        if mode == .singlePlayer {
            if case .running = phase {
                for p in allPlayers { p.tickEnergy(deltaTime: dt) }
            }
            // Refresh the stat panels ~10×/sec instead of every frame:
            // each refresh may re-rasterize label textures.
            statPanelAccumulator += dt
            if statPanelAccumulator >= 0.1 {
                statPanelAccumulator = 0
                updateStatPanels()
            }
        }

        // Match clock: real seconds count up, shown as a 0–90' football clock
        // (extending to 120' in extra time). Paused during the countdown,
        // celebrations, half time, the shootout and full time.
        switch phase {
        case .strategyPick, .countdown, .goalScored, .halftime, .finished:
            break
        default:
            if stage == .shootout { break }              // clock frozen for penalties
            let displayTotal = GameConfig.displayMatchMinutes * 60    // 90:00 in "match seconds"
            let etHalfDisplay = GameConfig.etDisplayMinutesPerHalf * 60
            if let brk = pendingBreak {
                // In added time: freeze the base clock, count the "+N" up.
                addedTimeElapsed += dt
                let base: Double, cap: Double, cutoff: Double
                switch brk {
                case .half:   base = displayTotal / 2;                cap = GameConfig.addedTimeCapRegular; cutoff = GameConfig.addedTimeCutoffRegular
                case .full:   base = displayTotal;                    cap = GameConfig.addedTimeCapRegular; cutoff = GameConfig.addedTimeCutoffRegular
                case .etHalf: base = displayTotal + etHalfDisplay;    cap = GameConfig.addedTimeCapExtra;   cutoff = GameConfig.addedTimeCutoffExtra
                case .etFull: base = displayTotal + 2 * etHalfDisplay; cap = GameConfig.addedTimeCapExtra;  cutoff = GameConfig.addedTimeCutoffExtra
                }
                hud.setTimer(base, addedMinutes: min(cap, addedTimeElapsed / cutoff * cap))
            } else {
                elapsed += dt
                hud.setTimer(elapsed / GameConfig.matchLengthSeconds * displayTotal)
                let full = GameConfig.matchLengthSeconds
                let etHalf = GameConfig.etHalfLengthSeconds
                // Only the authority calls breaks; the joiner is told via
                // `.addedTime` / `.breakNow` messages so the clocks can't split.
                if isAuthority {
                    switch stage {
                    case .regular1 where elapsed >= full / 2:   enterAddedTime(.half)
                    case .regular2 where elapsed >= full:       enterAddedTime(.full)
                    case .et1 where elapsed >= full + etHalf:   enterAddedTime(.etHalf)
                    case .et2 where elapsed >= full + 2 * etHalf: enterAddedTime(.etFull)
                    default: break
                    }
                }
            }
        }

        // Ball follows its carrier (unless a shot is mid-flight).
        if let c = carrier, !ballInFlight { ball.position = c.position }
    }

    /// Bottom-corner panels: left shows the spotlighted HOME player, right the
    /// spotlighted AWAY player. The spotlight is the ball carrier on the team
    /// in possession and the defender closest to the ball on the other team.
    private func updateStatPanels() {
        guard let c = carrier, stage != .shootout else {
            hud.setStatPanelsHidden(true)
            return
        }
        let homeShown = c.team == .home ? c : nearestOutfielder(of: .home, to: c.position)
        let awayShown = c.team == .away ? c : nearestOutfielder(of: .away, to: c.position)
        hud.updateStatPanel(left: true, title: panelTitle(homeShown),
                            energy: homeShown.energy, speed: homeShown.currentSpeed)
        hud.updateStatPanel(left: false, title: panelTitle(awayShown),
                            energy: awayShown.energy, speed: awayShown.currentSpeed)
    }

    private func panelTitle(_ p: PlayerNode) -> String {
        let tag = p.playerName ?? (p.isGoalkeeper ? "GK" : "#\(p.lane.rawValue + 1)")
        let ballMark = p.hasBall ? " ●" : ""
        return "\(p.team.displayName) \(tag)\(ballMark)"
    }

    private func updateCountdown(_ dt: TimeInterval) {
        countdownRemaining -= dt
        let shown = Int(ceil(countdownRemaining))
        if shown != countdownShown && shown > 0 {
            countdownShown = shown
            hud.showStatus("\(shown)")
            Audio.tick()
        }
        if countdownRemaining <= 0 {
            hud.hideStatus()
            if let action = countdownCompletion {
                // Custom restart (e.g. a penalty kick after its 3s countdown).
                countdownCompletion = nil
                action()
            } else if let team = restartWithBallFor {
                // Restart after a goal: the conceding team gets the ball.
                restartWithBallFor = nil
                Audio.whistle()
                if isAuthority {
                    giveBallToRandomOutfielder(of: team)
                    beginRunning()
                } else {
                    phase = .kickoff    // host's possession message restarts play
                }
            } else {
                if isAuthority {
                    beginKickoffDuel()
                } else {
                    phase = .kickoff    // host's duelStart message brings the word
                }
            }
            drainPendingNetEvents()     // apply anything that arrived mid-countdown
        }
    }

    private func updateDuel(_ dt: TimeInterval) {
        // Update the on-screen typed/remaining display.
        hud.showPrompt(typed: typing.typedPrefix, remaining: typing.remaining)

        // Joiners never resolve duels — the host's `duelResult` decides.
        // (Rivals' live progress arrives via `.typingProgress` messages.)
        if isNetPeer { return }

        // Away side in single player: the AI "types".
        if mode == .singlePlayer {
            if ai.update(deltaTime: dt) { awayDuelDone = true }
            // Rival's live progress on the same word (orange row).
            let total = typing.target.count
            let enemyCount = min(total, Int(Double(total) * ai.progress))
            hud.updateEnemyProgress(word: typing.target, typedCount: enemyCount)
        }
        // Multiplayer: home/away completion flags are set by the host's own
        // typing (when it participates) and by seat-tagged network messages.

        // Whoever finishes first wins. Ties on the same frame go to home
        // (feels fairer in single player; deterministic in multiplayer).
        if homeDuelDone {
            resolveDuel(winner: .home)
        } else if awayDuelDone {
            resolveDuel(winner: .away)
        }
    }

    private func updateRunning(_ dt: TimeInterval) {
        guard let carrier else { return }

        // Added-time hard cutoff: if the stoppage window passes with no shot
        // in open play, stop the half/match now (shorter window in extra time).
        if let brk = pendingBreak {
            let cutoff = (brk == .etHalf || brk == .etFull) ? GameConfig.addedTimeCutoffExtra
                                                            : GameConfig.addedTimeCutoffRegular
            if addedTimeElapsed >= cutoff { triggerBreak(); return }
        }

        // Free-kick / keeper-possession hold: the ball-holder waits to pass.
        // Meanwhile every other outfielder drops back to its default formation
        // spot, so the offside player retreats and doesn't loiter by the ball.
        if carrierMustPass {
            for p in allPlayers where !p.isGoalkeeper && p !== carrier {
                p.move(toward: CGPoint(x: formationX(for: p.team, lane: p.lane),
                                       y: formationY(for: p.team, lane: p.lane)), deltaTime: dt)
            }
            return
        }

        let isHome = carrier.team == .home
        let toRight = attacksRight(carrier.team)
        let goalX = toRight ? geometry.rect.maxX : geometry.rect.minX
        let boxEdgeX = toRight ? geometry.rect.maxX - GameConfig.penaltyDepth
                               : geometry.rect.minX + GameConfig.penaltyDepth

        // Carrier drives toward the enemy goal along its lane. The joiner
        // parks the carrier at the box edge — the host's `duelStart` message
        // decides when the shot duel actually begins.
        let carrierAtBox = toRight ? carrier.position.x >= boxEdgeX
                                   : carrier.position.x <= boxEdgeX
        if !(isNetPeer && carrierAtBox) {
            carrier.move(toward: CGPoint(x: goalX, y: laneY(carrier.lane)), deltaTime: dt)
        }

        // Off-ball attackers run forward but STOP just outside the penalty
        // line, and respect offside via a per-runner state machine:
        //   normal      → run forward; if offside past the grace period, flag it
        //   retreating  → jog back toward own goal for 0.5 seconds
        //   waiting     → hold; once onside for 0.2s, run forward again
        // The offside line itself is the last defender OR the ball carrier —
        // whichever is nearer the goal — so an attacker overlapping the last
        // defender moves the line up to the man on the ball.
        let attackers = isHome ? homeOutfield : awayOutfield
        let offBall = attackers.filter { $0 !== carrier }
        let lineX = offsideReferenceX(attackingTeam: carrier.team)
        updateLiveOffsideLine(x: lineX)
        let midX = geometry.rect.midX
        let ownGoalX = toRight ? geometry.rect.minX : geometry.rect.maxX
        for a in offBall {
            let id = ObjectIdentifier(a)
            let inOppHalf = toRight ? a.position.x > midX : a.position.x < midX
            let beyondLine = toRight ? a.position.x > lineX : a.position.x < lineX
            let offside = inOppHalf && beyondLine

            switch offsideStates[id] ?? .normal(offsideTime: 0) {
            case .normal(let t):
                let time = offside ? t + dt : 0
                if offside && time >= GameConfig.offsideGraceSeconds {
                    offsideStates[id] = .retreating(remaining: GameConfig.offsideRetreatSeconds)
                } else {
                    offsideStates[id] = .normal(offsideTime: time)
                    let targetX = toRight ? min(boxEdgeX, geometry.rect.maxX)
                                          : max(boxEdgeX, geometry.rect.minX)   // never enter the box
                    a.move(toward: CGPoint(x: targetX, y: laneY(a.lane)), deltaTime: dt)
                }
            case .retreating(let remaining):
                // Jog back toward the own goal for the retreat window.
                a.move(toward: CGPoint(x: ownGoalX, y: laneY(a.lane)), deltaTime: dt, speedScale: 0.6)
                let left = remaining - dt
                offsideStates[id] = left <= 0 ? .waiting(onsideTime: 0)
                                              : .retreating(remaining: left)
            case .waiting(let onside):
                if offside {
                    // Still beyond the line: keep easing back, reset the clock.
                    a.move(toward: CGPoint(x: ownGoalX, y: laneY(a.lane)), deltaTime: dt, speedScale: 0.35)
                    offsideStates[id] = .waiting(onsideTime: 0)
                } else {
                    let time = onside + dt
                    // Hold position until legal for the reset window, then rejoin.
                    offsideStates[id] = time >= GameConfig.offsideOnsideResetSeconds
                        ? .normal(offsideTime: 0)
                        : .waiting(onsideTime: time)
                }
            }
        }

        // --- Defence ---
        let defenders = isHome ? awayOutfield : homeOutfield

        // Duel starts when the nearest defender that isn't in a slow window
        // (collision disabled) is close enough. Beaten defenders keep chasing
        // at 70% but can't trigger a new duel until they recover.
        // Authority only — the joiner is told about duels by the host.
        if isAuthority && !carrier.isSlowed {
            let eligible = defenders
                .filter { !$0.isSlowed && carrier.position.distance(to: $0.position) < GameConfig.duelTriggerDistance }
                .min(by: { carrier.position.distance(to: $0.position) < carrier.position.distance(to: $1.position) })
            if let defender = eligible {
                startDuel(kind: .interception, attacker: carrier, defender: defender, intensity: 0.45)
                return
            }
        }

        // Debounced marking: keep the current assignment unless a *different*
        // ideal marking persists for a full `defenderSwitchDelay`. If the need
        // to switch goes away within that window, we cancel and keep marking as
        // is — this stops defenders flip-flopping and stalling between targets.
        let ideal = computeDefenderRoles(defenders: defenders, carrier: carrier, offBall: offBall, goalX: goalX)
        if defenderRoles.isEmpty {
            defenderRoles = ideal                       // first assignment of this possession
            switchPending = false; switchTimer = 0
        } else if defenderRoles == ideal {
            switchPending = false; switchTimer = 0       // nothing wants to change
        } else if !switchPending {
            switchPending = true                         // a switch is wanted — start the 1s clock
            switchTimer = GameConfig.defenderSwitchDelay
        } else {
            switchTimer -= dt
            if switchTimer <= 0 {                        // still wanted after 1s → switch instantly
                defenderRoles = ideal
                switchPending = false
            }
        }

        // Move each defender toward its committed assignment (live positions).
        for d in defenders {
            switch defenderRoles[ObjectIdentifier(d)] ?? .press {
            case .press:
                d.move(toward: carrier.position, deltaTime: dt)
            case .coverRunner(let runner):
                d.move(toward: runner.position, deltaTime: dt)
            case .coverMid:
                let mid = offBall.count >= 2
                    ? CGPoint(x: (offBall[0].position.x + offBall[1].position.x) / 2,
                              y: (offBall[0].position.y + offBall[1].position.y) / 2)
                    : carrier.position
                d.move(toward: mid, deltaTime: dt)
            }
        }

        // Keeper holds a position out toward the penalty line and shadows
        // the ball's row across the goal mouth.
        let defKeeper: PlayerNode = isHome ? awayKeeper : homeKeeper
        let kX = toRight ? geometry.rect.maxX - GameConfig.keeperStandoff
                         : geometry.rect.minX + GameConfig.keeperStandoff
        defKeeper.move(toward: CGPoint(x: kX,
                                       y: max(geometry.rect.midY - 90, min(geometry.rect.midY + 90, carrier.position.y))),
                       deltaTime: dt)

        // Reached the penalty area → final shot duel vs the goalkeeper.
        // Authority only — the joiner waits for the host's `duelStart`.
        let reachedBox = toRight ? carrier.position.x >= boxEdgeX
                                 : carrier.position.x <= boxEdgeX
        if isAuthority && reachedBox && !carrier.isSlowed {
            startDuel(kind: .shot, attacker: carrier, defender: defKeeper, intensity: 0.85)
        }
    }

    /// The ideal marking right now: the presser is the defending player's
    /// chosen chaser (keys 1–3) if one is set, otherwise the nearest defender;
    /// one deep defender covers the off-ball runner(s); the rest press too.
    /// Pure — returns a fresh dictionary so callers can compare it against
    /// the committed one.
    private func computeDefenderRoles(defenders: [PlayerNode], carrier: PlayerNode,
                                      offBall: [PlayerNode], goalX: CGFloat) -> [ObjectIdentifier: DefenderRole] {
        var roles: [ObjectIdentifier: DefenderRole] = [:]
        let chosen = chaseChoice[carrier.team.opponent]
            .flatMap { lane in defenders.first { $0.lane == lane } }
        guard let press = chosen ?? defenders.min(by: {
            carrier.position.distance(to: $0.position) < carrier.position.distance(to: $1.position)
        }) else { return roles }
        roles[ObjectIdentifier(press)] = .press

        let others = defenders.filter { $0 !== press }
        if offBall.count >= 2 {
            let cover = others.min(by: { abs(goalX - $0.position.x) < abs(goalX - $1.position.x) })
            for d in others { roles[ObjectIdentifier(d)] = (d === cover) ? .coverMid : .press }
        } else if let runner = offBall.first {
            let cover = others.min(by: { runner.position.distance(to: $0.position) < runner.position.distance(to: $1.position) })
            for d in others { roles[ObjectIdentifier(d)] = (d === cover) ? .coverRunner(runner) : .press }
        } else {
            for d in others { roles[ObjectIdentifier(d)] = .press }
        }
        return roles
    }

    /// Manually pass to the home outfield player in a given lane (keys 1–3).
    /// Authority only — the joiner routes its key presses through the host
    /// with a `.passRequest` message instead (see keyDown).
    private func attemptManualPass(toLane lane: Lane) {
        guard case .running = phase, !ballInFlight,
              let carrier, carrier.team == .home else { return }
        guard let target = homeOutfield.first(where: { $0.lane == lane }),
              target !== carrier else { return }
        executePass(to: target, by: .home)
    }

    /// The host executing a remote player's pass request. Valid only if that
    /// seat controls the current carrier (field seat for an outfielder,
    /// keeper seat for the GK — this is how the keeper distributes).
    func applyPeerPassRequest(seatRaw: Int, toLane raw: Int) {
        guard isNetworkHost, case .running = phase, !ballInFlight,
              let seat = PeerSeat(rawValue: seatRaw),
              let lane = Lane(rawValue: raw),
              let carrier, controllerSeat(of: carrier) == seat,
              seat != .homeField,                     // the host passes locally
              let target = outfield(carrier.team == .home ? homePlayers : awayPlayers)
                            .first(where: { $0.lane == lane }),
              target !== carrier else { return }
        executePass(to: target, by: carrier.team)
    }

    /// The host committing a remote field player's chase pick (defense).
    func applyChaseRequest(seatRaw: Int, laneRaw: Int) {
        guard isNetworkHost, case .running = phase,
              let seat = PeerSeat(rawValue: seatRaw), seat.isField,
              let lane = Lane(rawValue: laneRaw),
              let carrier else { return }
        let team: Team = seat.isHome ? .home : .away   // host frame == wire frame
        guard carrier.team != team else { return }     // must actually be defending
        guard chaseChoice[team] != lane else { return }
        chaseChoice[team] = lane
        broadcast(.chaseState(homeTeam: seat.isHome, lane: laneRaw))
    }

    /// Run a validated pass for either side (authority only), announcing it
    /// to the joiner first so both screens animate the same ball flight.
    private func executePass(to target: PlayerNode, by team: Team) {
        // Passing to a teammate who is in an offside position is a foul: let
        // the ball travel to them first, then the flag goes up.
        let offside = isOffside(target, attackingTeam: team)
        if isNetworkHost {
            broadcast(.passStarted(target: playerRef(target), offside: offside,
                                   lineX: Double(offsideReferenceX(attackingTeam: team))))
        }
        if offside {
            passIntoOffside(to: target, by: team)
        } else {
            performPass(to: target)
        }
    }

    /// Animate the ball to an offside teammate, then raise the offside flag.
    private func passIntoOffside(to target: PlayerNode, by team: Team) {
        Audio.tick()
        carrierMustPass = false
        let lineX = offsideReferenceX(attackingTeam: team)   // boundary at the moment of the pass
        carrier?.setHasBall(false)
        carrier = nil
        ballInFlight = true
        ball.isHidden = false
        phase = .goalScored(team.opponent)   // neutral pause; corrected in handleOffside
        let spot = target.position
        let travel = SKAction.move(to: spot, duration: GameConfig.passTravelDuration)
        travel.timingMode = .easeInEaseOut
        ball.run(travel) { [weak self] in
            guard let self else { return }
            self.ballInFlight = false
            self.handleOffside(at: spot, lineX: lineX, defendingTeam: team.opponent)
        }
    }

    // MARK: Offside

    /// Faint live offside line shown while the ball is in open play. It tracks
    /// the last defender, or the ball carrier when the carrier has overlapped
    /// that defender (the ball can never be offside).
    private func updateLiveOffsideLine(x: CGFloat) {
        // Style/path only when switching back from the white "whistle" look;
        // per-frame we just slide the node (no path rebuild, no tessellation).
        if !offsideLineLiveStyle {
            offsideLineNode.path = liveOffsidePath
            offsideLineNode.strokeColor = SKColor(red: 0.4, green: 0.85, blue: 1, alpha: 0.35)
            offsideLineNode.lineWidth = 1.5
            offsideLineLiveStyle = true
        }
        offsideLineNode.position.x = x
        offsideLineNode.isHidden = false
    }

    /// The offside boundary X for the attacking team. Measured at the EDGE of
    /// the last defender (its goal-side rim, giving the attacker the benefit of
    /// the defender's body), and — since you can't be offside level with or
    /// behind the ball — never deeper than the ball's own line. So the boundary
    /// is the more-goalward of {last defender's edge, ball}.
    private func offsideReferenceX(attackingTeam team: Team) -> CGFloat {
        let toRight = attacksRight(team)
        let r = GameConfig.playerRadius
        // Reduce over the cached roster without allocating an intermediate array.
        let opponents = team == .home ? awayOutfield : homeOutfield
        let dir: CGFloat = toRight ? 1 : -1
        var deepest = toRight ? geometry.rect.maxX : geometry.rect.minX
        if let first = opponents.first {
            deepest = first.position.x
            for p in opponents.dropFirst() {
                deepest = toRight ? max(deepest, p.position.x) : min(deepest, p.position.x)
            }
        }
        let defEdge = deepest + dir * r                          // last defender's rim (circle edge)
        let ballEdge = ball.position.x + dir * GameConfig.ballRadius  // ball's rim (also a circle edge)
        return toRight ? max(defEdge, ballEdge) : min(defEdge, ballEdge)
    }

    /// A player is offside if — in the opponent's half — they are beyond the
    /// offside boundary. Nothing before halfway counts (as in real football).
    private func isOffside(_ p: PlayerNode, attackingTeam team: Team) -> Bool {
        let toRight = attacksRight(team)
        let inOppHalf = toRight ? p.position.x > geometry.rect.midX : p.position.x < geometry.rect.midX
        guard inOppHalf else { return false }
        let refX = offsideReferenceX(attackingTeam: team)
        return toRight ? p.position.x > refX : p.position.x < refX
    }

    /// Whistle for offside: stop play, draw the line, hand a free kick to the
    /// defending team at the exact spot; that taker must pass before dribbling.
    private func handleOffside(at spot: CGPoint, lineX: CGFloat, defendingTeam: Team) {
        phase = .goalScored(defendingTeam)     // neutral pause (movement + clock frozen)
        carrier?.setHasBall(false)
        carrier = nil
        ball.position = spot                   // ball sits where the offside pass arrived
        ball.isHidden = false
        Audio.whistle()
        hud.showStatus("OFFSIDE", fontSize: 44)

        // Draw the offside boundary at the defender/ball edge line.
        offsideLineNode.path = whistleOffsidePath
        offsideLineNode.strokeColor = .white     // offside line is always white
        offsideLineNode.lineWidth = 2
        offsideLineNode.position.x = lineX
        offsideLineNode.isHidden = false
        offsideLineLiveStyle = false

        // The offside line stays up for 3 seconds, then play restarts.
        run(.sequence([.wait(forDuration: 3.0), .run { [weak self] in
            guard let self else { return }
            self.hud.hideStatus()
            self.offsideLineNode.isHidden = true
            // Reset both goalkeepers back onto their goal lines.
            for gk in [self.keeper(self.homePlayers), self.keeper(self.awayPlayers)] {
                gk.setHasBall(false)
                gk.position = CGPoint(x: self.keeperX(for: gk.team), y: self.geometry.rect.midY)
            }
            // Free kick to the defending team's nearest OUTFIELD player at the spot.
            let taker = self.nearestOutfielder(of: defendingTeam, to: spot)
            taker.position = spot
            self.carrierMustPass = true        // must pass before advancing (set before the broadcast)
            self.setCarrier(taker)
            self.beginRunning()
            // If the AI is taking it, have it lay the ball off after a beat.
            if self.mode == .singlePlayer && defendingTeam == .away {
                self.run(.sequence([.wait(forDuration: 0.8), .run { [weak self] in
                    self?.aiFreeKickPass()
                }]))
            }
        }]))
    }

    private func aiFreeKickPass() {
        guard carrierMustPass, let c = carrier else { return }
        let mates = outfield(c.team == .home ? homePlayers : awayPlayers).filter { $0 !== c }
        if let target = mates.randomElement() { performPass(to: target) }
    }

    private func nearestOutfielder(of team: Team, to point: CGPoint) -> PlayerNode {
        let ps = team == .home ? homeOutfield : awayOutfield
        return ps.min(by: { point.distance(to: $0.position) < point.distance(to: $1.position) })!
    }

    private func performPass(to target: PlayerNode) {
        Audio.tick()          // "pass" cue — swap for a real SFX later
        carrierMustPass = false   // making the pass satisfies a free-kick restart
        // Release the ball from the carrier and animate it across to the
        // target, just like a shot — no instant teleport.
        carrier?.setHasBall(false)
        carrier = nil
        passTargetRef = nil
        passTimer = 0
        ballInFlight = true

        let dest = target.position
        let travel = SKAction.move(to: dest, duration: GameConfig.passTravelDuration)
        travel.timingMode = .easeInEaseOut
        ball.run(travel) { [weak self, weak target] in
            guard let self else { return }
            self.ballInFlight = false
            // Abort if the half ended or match finished mid-pass.
            guard self.phase == .running, let target else { return }
            self.setCarrier(target)
        }
    }

    private func endMatch() {
        guard phase != .finished else { return }
        if isNetworkHost { broadcast(.breakNow(kind: 4, shootoutGoalRight: nil)) }
        phase = .finished
        hud.hidePrompt()
        hud.setStatPanelsHidden(true)
        carrier?.setHasBall(false)
        carrier = nil
        ball.isHidden = true
        hud.showStatus("FULL TIME", fontSize: 46)
        gameDelegate?.matchDidFinish(homeStats: homeStats,
                                     homeScore: homeScore, awayScore: awayScore,
                                     penaltyHome: stage == .shootout ? penHome : nil,
                                     penaltyAway: stage == .shootout ? penAway : nil)
    }

    // MARK: Keyboard input (the human's typing)

    override func keyDown(with event: NSEvent) {
        // Left / right arrows cycle the formation (field players only).
        if mode == .singlePlayer || localIsField {
            if event.keyCode == 123 { cycleFormation(-1); return }   // ←
            if event.keyCode == 124 { cycleFormation(1);  return }   // →
        }

        guard let chars = event.charactersIgnoringModifiers, let ch = chars.first else { return }

        // Number keys 1–3: attacking → pass to that lane; defending → pick
        // which of your outfielders chases the ball carrier.
        if let digit = ch.wholeNumberValue, (1...3).contains(digit),
           let lane = Lane(rawValue: digit - 1) {
            handleLaneKey(lane)
            return
        }

        guard case .duel = phase, typing.isActive else { return }
        // Only the human whose unit is in this duel gets to type.
        guard localTypesThisDuel else { return }
        guard ch.isLetter else { return }
        let mistakesBefore = typing.mistakes
        let done = typing.input(ch)
        hud.showPrompt(typed: typing.typedPrefix, remaining: typing.remaining)
        if typing.mistakes > 0 { homeDuelMistyped = true }

        // Stream live progress so rivals see the orange row fill in.
        if mode == .multipeer, typing.typedPrefix.count > 0, !done {
            broadcast(.typingProgress(seat: localSeat.rawValue, count: typing.typedPrefix.count))
        }

        // Final shot rule (open play only): the shooter must type the WHOLE
        // word cleanly — one wrong letter and the shot sails wide immediately.
        // Penalties are different: the mistake is only revealed at the kick.
        if typing.mistakes > mistakesBefore, stage != .shootout,
           duelKind == .shot, let shooter = duelAttacker,
           localControls(shooter), !duelResolved {
            if isNetPeer {
                broadcast(.shotMistyped(seat: localSeat.rawValue))   // host resolves + reports back
            } else {
                failShot(mistypedBy: .home)
            }
            return
        }

        if done {
            homeDuelDone = true
            gameDelegate?.localPlayerCompletedWord(mistyped: typing.mistakes > 0)
        }
    }

    /// Keys 1–3. Attacking (and this human controls the carrier — the field
    /// player for outfielders, the keeper player for the GK): pass to that
    /// lane. Defending (field players only): order that outfielder to chase
    /// the ball carrier; the others keep their auto-cover jobs.
    private func handleLaneKey(_ lane: Lane) {
        guard case .running = phase, !ballInFlight, let carrier else { return }

        if carrier.team == .home {
            // ATTACK: pass. Only the carrier's controller may play it.
            guard localControls(carrier) else { return }
            if isAuthority {
                attemptManualPass(toLane: lane)
            } else {
                broadcast(.passRequest(seat: localSeat.rawValue, toLane: lane.rawValue))
            }
        } else {
            // DEFENSE: choose the chaser (field players only; SP human too).
            guard mode == .singlePlayer || localIsField else { return }
            guard chaseChoice[.home] != lane else { return }
            if isAuthority {
                chaseChoice[.home] = lane
                if isNetworkHost {
                    broadcast(.chaseState(homeTeam: wireHome(for: .home), lane: lane.rawValue))
                }
            } else {
                broadcast(.chaseRequest(seat: localSeat.rawValue, lane: lane.rawValue))
            }
            hud.showToast("CHASE — PLAYER \(lane.rawValue + 1)")
        }
    }

    /// A shooter mistyped during an open-play final shot: instant miss.
    /// Runs on the authority for either side's shooter.
    private func failShot(mistypedBy team: Team) {
        guard let shooter = duelAttacker, shooter.team == team, !duelResolved else { return }
        duelResolved = true
        let winner = team.opponent
        if isNetworkHost {
            broadcast(.duelResult(winnerHome: wireHome(for: winner),
                                  shotOutcome: ShotOutcome.wide.rawValue))
        }
        hud.hidePrompt()
        if localTypesThisDuel {
            homeStats.record(word: typing.target,
                             seconds: max(0.001, typing.elapsedSeconds),
                             mistakes: typing.mistakes)
            if winner == .home { homeStats.duelsWon += 1 } else { homeStats.duelsLost += 1 }
        }
        ai.reset()
        typing.reset()
        hud.showToast(team == .home ? "MISTYPE — SHOT WIDE" : "RIVAL MISTYPE — WIDE")
        shootBall(scored: false, shooter: shooter)
    }

    // MARK: - Multiplayer networking

    /// Ship a message to the connected peer (no-op outside multiplayer).
    private func broadcast(_ message: PeerMessage) {
        guard mode == .multipeer else { return }
        gameDelegate?.peerSend(message)
    }

    /// Scene fully built (didMove ran)? Network events arriving before that
    /// — possible if the peer's scene presents a beat later — are dropped.
    private var netReady: Bool { hud != nil && !allPlayers.isEmpty }

    /// Wire coordinates are in the HOST's frame. Machines on the wire-home
    /// team share that frame; machines on the other team render a mirrored
    /// pitch (everyone sees their own team attack to the right), so they
    /// flip every incoming x.
    private func mirrorX(_ x: CGFloat) -> CGFloat {
        myTeamIsWireHome ? x : geometry.rect.midX * 2 - x
    }

    /// Map a wire team flag ("home" = the host's team) onto our local sides.
    private func localTeam(wireHome: Bool) -> Team {
        wireHome == myTeamIsWireHome ? .home : .away
    }

    /// Encode a local team for the wire.
    private func wireHome(for team: Team) -> Bool {
        team == .home ? myTeamIsWireHome : !myTeamIsWireHome
    }

    /// Encode a player for the wire.
    private func playerRef(_ p: PlayerNode) -> PeerPlayerRef {
        PeerPlayerRef(home: wireHome(for: p.team), slot: p.isGoalkeeper ? 3 : p.lane.rawValue)
    }

    /// Decode a wire ref onto our local rosters ([top, mid, bottom, GK]).
    private func playerNode(for ref: PeerPlayerRef) -> PlayerNode {
        let list = localTeam(wireHome: ref.home) == .home ? homePlayers : awayPlayers
        return list[max(0, min(ref.slot, 3))]
    }

    /// Host: a remote human finished the duel word — credit their side.
    /// (Joiners learn outcomes from `duelResult` instead.)
    func applyRemoteWordCompleted(seatRaw: Int, mistyped: Bool) {
        guard isNetworkHost, case .duel = phase, !duelResolved,
              let seat = PeerSeat(rawValue: seatRaw), seatParticipates(seat) else { return }
        if seat.isHome {
            homeDuelDone = true
            homeDuelMistyped = homeDuelMistyped || mistyped
        } else {
            awayDuelDone = true
            awayDuelMistyped = awayDuelMistyped || mistyped
        }
    }

    /// Live rival typing progress (orange row under the word) — only shown
    /// for the OPPOSING team's typist, on every machine.
    func applyRemoteTypingProgress(seatRaw: Int, count: Int) {
        guard mode == .multipeer, case .duel = phase,
              let seat = PeerSeat(rawValue: seatRaw),
              localTeam(wireHome: seat.isHome) == .away else { return }
        hud.updateEnemyProgress(word: typing.target,
                                typedCount: max(0, min(count, typing.target.count)))
    }

    /// Host: a remote shooter mistyped its open-play shot word.
    func applyRemoteShotMistype(seatRaw: Int) {
        guard isNetworkHost, stage != .shootout, case .duel(.shot) = phase,
              let seat = PeerSeat(rawValue: seatRaw),
              let shooter = duelAttacker, controllerSeat(of: shooter) == seat else { return }
        failShot(mistypedBy: shooter.team)
    }

    /// All machines: mirror a committed chase pick so local defender
    /// movement matches the host's sim.
    func applyRemoteChaseState(homeTeamWire: Bool, laneRaw: Int) {
        guard mode == .multipeer, let lane = Lane(rawValue: laneRaw) else { return }
        chaseChoice[localTeam(wireHome: homeTeamWire)] = lane
    }

    /// Non-senders: a field player changed their team's formation.
    func applyRemoteFormationUpdate(homeTeamWire: Bool, raw: Int) {
        guard mode == .multipeer, let f = Formation(rawValue: raw) else { return }
        if localTeam(wireHome: homeTeamWire) == .home {
            // Our field teammate changed OUR shape (keeper-client view).
            guard !localIsField else { return }
            switch phase {
            case .strategyPick, .countdown:
                homeFormation = f
                pendingHomeFormation = nil
                applyHomeFormationPositions(animated: true)
            default:
                pendingHomeFormation = f
            }
            hud?.showToast("FORMATION \(f.label)")
        } else {
            awayFormation = f
            hud?.showToast("RIVAL FORMATION \(f.label)")
        }
    }

    /// Joiner: the host started a duel — same word on both screens.
    func applyRemoteDuelStart(kindCode: Int, word: String,
                              attacker: PeerPlayerRef?, defender: PeerPlayerRef?) {
        guard isNetPeer, netReady else { return }
        let kind = DuelKind(netCode: kindCode)
        let a = attacker.map(playerNode(for:))
        let d = defender.map(playerNode(for:))
        switch phase {
        case .countdown, .strategyPick, .halftime:
            // Still playing out a local pause — hold the duel until it ends.
            pendingRemoteDuel = (kind, word, a, d)
        default:
            beginDuel(kind: kind, word: word, attacker: a, defender: d)
        }
    }

    /// Joiner: the host resolved the current duel.
    func applyRemoteDuelResult(winnerHome: Bool, shotOutcomeCode: Int?) {
        guard isNetPeer, !duelResolved, case .duel = phase else { return }
        duelResolved = true
        applyDuelResolution(winner: localTeam(wireHome: winnerHome),
                            outcome: shotOutcomeCode.flatMap(ShotOutcome.init(rawValue:)))
    }

    /// Joiner: the host assigned the ball to a player (kickoffs, turnovers,
    /// restarts, keeper distributions, free kicks, landed passes).
    func applyRemotePossession(playerRef ref: PeerPlayerRef, x: Double, y: Double, mustPass: Bool) {
        guard isNetPeer, netReady else { return }
        let p = playerNode(for: ref)
        if holdingPossessionEvents || phase == .countdown || phase == .halftime {
            pendingRemotePossession = (p, CGFloat(x), CGFloat(y), mustPass)
            return
        }
        applyPossessionNow(p, x: CGFloat(x), y: CGFloat(y), mustPass: mustPass)
    }

    private func applyPossessionNow(_ p: PlayerNode, x: CGFloat, y: CGFloat, mustPass: Bool) {
        p.position = CGPoint(x: mirrorX(x), y: y)   // re-align with the host's sim
        carrierMustPass = mustPass
        setCarrier(p)
        if phase != .running { beginRunning() }
    }

    /// Joiner: a pass kicked off on the host — animate the same flight here.
    func applyRemotePass(targetRef: PeerPlayerRef, offside: Bool, lineX: Double) {
        guard isNetPeer, netReady else { return }
        let target = playerNode(for: targetRef)
        Audio.tick()
        carrierMustPass = false
        carrier?.setHasBall(false)
        carrier = nil
        ballInFlight = true
        ball.isHidden = false
        let travel = SKAction.move(to: target.position, duration: GameConfig.passTravelDuration)
        travel.timingMode = .easeInEaseOut
        if offside {
            phase = .goalScored(.away)          // neutral pause during the whistle
            holdingPossessionEvents = true      // don't restart until the flag sequence ends
            let flagX = mirrorX(CGFloat(lineX))
            ball.run(travel) { [weak self] in
                guard let self else { return }
                self.ballInFlight = false
                self.presentOffsideWhistle(lineX: flagX)
            }
        } else {
            ball.run(travel) { [weak self] in
                self?.ballInFlight = false
                // The landed pass's new carrier arrives as a possession message.
            }
        }
    }

    /// Joiner-side offside presentation: whistle, white line, 3s pause. The
    /// restart itself (free-kick taker + must-pass) comes from the host.
    private func presentOffsideWhistle(lineX: CGFloat) {
        Audio.whistle()
        hud.showStatus("OFFSIDE", fontSize: 44)
        offsideLineNode.path = whistleOffsidePath
        offsideLineNode.strokeColor = .white
        offsideLineNode.lineWidth = 2
        offsideLineNode.position.x = lineX
        offsideLineNode.isHidden = false
        offsideLineLiveStyle = false
        run(.sequence([.wait(forDuration: 3.0), .run { [weak self] in
            guard let self else { return }
            self.hud.hideStatus()
            self.offsideLineNode.isHidden = true
            for gk in [self.homeKeeper!, self.awayKeeper!] {
                gk.setHasBall(false)
                gk.position = CGPoint(x: self.keeperX(for: gk.team), y: self.geometry.rect.midY)
            }
            self.holdingPossessionEvents = false
            self.drainPendingNetEvents()
        }]))
    }

    /// Joiner: stoppage-time notice from the host (display only).
    func applyRemoteAddedTime() {
        guard isNetPeer else { return }
        hud?.showToast("ADDED TIME")
    }

    /// Joiner: the host called a break / stage transition.
    func applyRemoteBreak(kind: Int, shootoutGoalRight: Bool?) {
        guard isNetPeer, netReady else { return }
        pendingRemoteDuel = nil
        pendingRemotePossession = nil
        holdingPossessionEvents = false
        switch kind {
        case 0: startHalftime()
        case 1: startExtraTime()
        case 2: startEtHalftime()
        case 3:
            penGoalRight = shootoutGoalRight ?? true
            startPenaltyShootout()
        case 4: endMatch()
        default: break
        }
    }

    /// Apply buffered network events once a local waiting phase ends.
    private func drainPendingNetEvents() {
        guard isNetPeer else { return }
        if let d = pendingRemoteDuel {
            pendingRemoteDuel = nil
            pendingRemotePossession = nil     // superseded by the new duel
            beginDuel(kind: d.kind, word: d.word, attacker: d.attacker, defender: d.defender)
        } else if let p = pendingRemotePossession {
            pendingRemotePossession = nil
            applyPossessionNow(p.player, x: p.x, y: p.y, mustPass: p.mustPass)
        }
    }

    /// The connection dropped mid-match: freeze play and wrap up.
    func peerDidDisconnect() {
        guard mode == .multipeer, netReady, phase != .finished else { return }
        removeAllActions()
        hud.hidePrompt()
        hud.showStatus("PLAYER DISCONNECTED", fontSize: 36)
        phase = .halftime          // neutral freeze — no input, no movement
        typing.reset()
        run(.sequence([.wait(forDuration: 2.0), .run { [weak self] in
            self?.endMatch()
        }]))
    }
}

/// Wire codes for DuelKind (the enum itself has no raw value).
private extension DuelKind {
    var netCode: Int {
        switch self {
        case .kickoff: return 0
        case .interception: return 1
        case .shot: return 2
        }
    }
    init(netCode: Int) {
        switch netCode {
        case 1: self = .interception
        case 2: self = .shot
        default: self = .kickoff
        }
    }
}

// MARK: - Small helpers

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(other.x - x, other.y - y) }
}

/// Lightweight audio using built-in macOS system sounds so the prototype
/// makes noise without any bundled assets. Swap for real SFX later.
enum Audio {
    static func whistle() { NSSound(named: NSSound.Name("Submarine"))?.play() }
    static func tick()    { NSSound(named: NSSound.Name("Tink"))?.play() }
}
