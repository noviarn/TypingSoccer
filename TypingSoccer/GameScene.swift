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
    func matchDidFinish(homeStats: PlayerStats, homeScore: Int, awayScore: Int)
    /// Called when the human completes a word — forwarded to peers in multiplayer.
    func localPlayerCompletedWord()
}

final class GameScene: SKScene {

    weak var gameDelegate: GameSceneDelegate?
    var mode: MatchMode = .singlePlayer

    // MARK: Nodes / state
    private let world = SKNode()
    private var hud: HUD!
    private var geometry: FieldBuilder.Geometry!

    private var homePlayers: [PlayerNode] = []
    private var awayPlayers: [PlayerNode] = []
    private let ball = BallNode.make()

    private var phase: GamePhase = .countdown
    private var carrier: PlayerNode?

    // Duel bookkeeping
    private let typing = TypingController()
    private let ai = AIOpponent()
    private var duelKind: DuelKind = .kickoff
    private var duelAttacker: PlayerNode?     // carrier / shooter (nil for kickoff)
    private var duelDefender: PlayerNode?     // interceptor / goalkeeper
    private var homeFinished = false
    private var awayFinishedRemote = false    // set by multipeer callback
    private var duelResolved = false

    // Stats & score
    private var homeStats = PlayerStats()
    private var awayScore = 0
    private var homeScore = 0

    // Clocks
    private var lastUpdate: TimeInterval = 0
    private var matchClock: TimeInterval = GameConfig.matchLengthSeconds
    private var countdownRemaining = Double(GameConfig.countdownSeconds)
    private var countdownShown = -1

    // MARK: Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true
        view.layer?.isOpaque = false
        scaleMode = .aspectFit
        addChild(world)

        geometry = FieldBuilder.build(in: world, sceneSize: size)
        hud = HUD(sceneSize: size, fieldBottomY: geometry.rect.minY)
        addChild(hud)

        world.addChild(ball)
        spawnTeams()
        resetFormation()
        ball.isHidden = true

        startCountdown()
        // Ensure we receive key events.
        view.window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: Team setup

    private func laneY(_ lane: Lane) -> CGFloat { geometry.laneY[lane.rawValue] }

    private func homeFormationX(for lane: Lane) -> CGFloat {
        geometry.rect.minX + geometry.rect.width * 0.30
    }
    private func awayFormationX(for lane: Lane) -> CGFloat {
        geometry.rect.maxX - geometry.rect.width * 0.30
    }

    private func spawnTeams() {
        for lane in Lane.allCases {
            let h = PlayerNode(team: .home, role: .outfield(lane), baseSpeed: GameConfig.baseCarrierSpeed)
            let a = PlayerNode(team: .away, role: .outfield(lane), baseSpeed: GameConfig.baseCarrierSpeed)
            homePlayers.append(h); awayPlayers.append(a)
            world.addChild(h); world.addChild(a)
        }
        let hk = PlayerNode(team: .home, role: .goalkeeper, baseSpeed: GameConfig.baseDefenderSpeed)
        let ak = PlayerNode(team: .away, role: .goalkeeper, baseSpeed: GameConfig.baseDefenderSpeed)
        homePlayers.append(hk); awayPlayers.append(ak)
        world.addChild(hk); world.addChild(ak)
    }

    private func outfield(_ team: [PlayerNode]) -> [PlayerNode] { team.filter { !$0.isGoalkeeper } }
    private func keeper(_ team: [PlayerNode]) -> PlayerNode { team.first { $0.isGoalkeeper }! }

    private func resetFormation() {
        for p in homePlayers {
            p.setHasBall(false)
            if p.isGoalkeeper {
                p.position = CGPoint(x: geometry.rect.minX + 20, y: geometry.rect.midY)
            } else {
                p.position = CGPoint(x: homeFormationX(for: p.lane), y: laneY(p.lane))
            }
        }
        for p in awayPlayers {
            p.setHasBall(false)
            if p.isGoalkeeper {
                p.position = CGPoint(x: geometry.rect.maxX - 20, y: geometry.rect.midY)
            } else {
                p.position = CGPoint(x: awayFormationX(for: p.lane), y: laneY(p.lane))
            }
        }
        carrier = nil
        ball.position = CGPoint(x: geometry.rect.midX, y: geometry.rect.midY)
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

    private func startDuel(kind: DuelKind, attacker: PlayerNode?, defender: PlayerNode?, intensity: Double) {
        duelKind = kind
        duelAttacker = attacker
        duelDefender = defender
        homeFinished = false
        awayFinishedRemote = false
        duelResolved = false

        let word = WordProvider.word(intensity: intensity)
        typing.begin(word: word)

        // Away difficulty: keeper shots are a touch harder.
        let skill: Double = (kind == .shot && (defender?.team == .away)) ? 0.75 : 0.5
        ai.begin(word: word, skill: skill)

        phase = .duel(kind)
        hud.showPrompt(typed: "", remaining: word)
    }

    /// Resolve who won and apply consequences.
    private func resolveDuel(winner: Team) {
        guard !duelResolved else { return }
        duelResolved = true
        hud.hidePrompt()

        // Record the human's typing effort for this word.
        homeStats.record(word: typing.target,
                         seconds: max(0.001, typing.elapsedSeconds),
                         mistakes: typing.mistakes)

        switch duelKind {
        case .kickoff:
            if winner == .home { homeStats.duelsWon += 1 } else { homeStats.duelsLost += 1 }
            giveBallToRandomOutfielder(of: winner)
            beginRunning()

        case .interception:
            let attacker = duelAttacker!     // current carrier
            let defender = duelDefender!     // interceptor
            if winner == attacker.team {
                // Carrier keeps the ball; defender is beaten and slowed.
                if winner == .home { homeStats.duelsWon += 1 } else { homeStats.duelsLost += 1 }
                defender.applySlow()
            } else {
                // Turnover: defender wins the ball; old carrier slowed.
                if winner == .home { homeStats.duelsWon += 1 } else { homeStats.duelsLost += 1 }
                attacker.applySlow()
                setCarrier(defender)
            }
            beginRunning()

        case .shot:
            let shooter = duelAttacker!
            if winner == shooter.team {
                // GOAL!
                if winner == .home { homeStats.duelsWon += 1; homeStats.goals += 1; homeScore += 1 }
                else { homeStats.duelsLost += 1; awayScore += 1 }
                hud.updateScore(home: homeScore, away: awayScore)
                Audio.whistle()
                celebrateGoal(scoringTeam: winner)
            } else {
                // Miss: ball goes out, possession resets to the OTHER side.
                if winner == .home { homeStats.duelsWon += 1 } else { homeStats.duelsLost += 1 }
                hud.showStatus("MISS!", fontSize: 44)
                run(.sequence([.wait(forDuration: 1.0), .run { [weak self] in
                    guard let self else { return }
                    self.hud.hideStatus()
                    self.resetFormation()
                    self.giveBallToRandomOutfielder(of: shooter.team.opponent)
                    self.beginRunning()
                }]))
            }
        }
        ai.reset()
        typing.reset()
    }

    private func celebrateGoal(scoringTeam: Team) {
        phase = .goalScored(scoringTeam)
        hud.showStatus(scoringTeam == .home ? "GOAL!" : "RIVAL SCORES", fontSize: 48)
        run(.sequence([.wait(forDuration: 1.4), .run { [weak self] in
            guard let self else { return }
            self.hud.hideStatus()
            self.resetFormation()
            // Kick off again with a fresh word contest.
            self.beginKickoffDuel()
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
    }

    private func beginRunning() {
        phase = .running
    }

    // MARK: Update loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 1.0 / 20.0)
        lastUpdate = currentTime

        switch phase {
        case .countdown:  updateCountdown(dt)
        case .duel:       updateDuel(dt)
        case .running:    updateRunning(dt)
        case .kickoff, .goalScored, .finished: break
        }

        // Slow-penalty recovery runs regardless of phase.
        for p in homePlayers + awayPlayers { p.tickSlow(deltaTime: dt) }

        // Match clock ticks while the ball is in play.
        if case .finished = phase {} else if phase != .countdown {
            matchClock -= dt
            hud.setTimer(matchClock)
            if matchClock <= 0 { endMatch() }
        }

        // Ball follows its carrier.
        if let c = carrier { ball.position = c.position }
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
            beginKickoffDuel()
        }
    }

    private func updateDuel(_ dt: TimeInterval) {
        // Away side: AI in single-player, remote peer in multiplayer.
        var awayDone = false
        if mode == .singlePlayer {
            awayDone = ai.update(deltaTime: dt)
        } else {
            awayDone = awayFinishedRemote
        }

        // Update the on-screen typed/remaining display.
        hud.showPrompt(typed: typing.typedPrefix, remaining: typing.remaining)

        // Whoever finishes first wins. Home completion is set in keyDown.
        if homeFinished && !awayDone {
            resolveDuel(winner: .home)
        } else if awayDone && !homeFinished {
            resolveDuel(winner: .away)
        } else if homeFinished && awayDone {
            // Tie on the same frame — award to the human (feels fairer).
            resolveDuel(winner: .home)
        }
    }

    private func updateRunning(_ dt: TimeInterval) {
        guard let carrier else { return }
        let attackingHome = carrier.team == .home
        let targetGoalX = attackingHome ? geometry.rect.maxX : geometry.rect.minX

        // Carrier runs down its lane toward the enemy goal.
        let laneRow = laneY(carrier.lane)
        carrier.move(toward: CGPoint(x: targetGoalX, y: laneRow), deltaTime: dt)

        // The opposing outfielder in the same lane closes down.
        let defenders = outfield(attackingHome ? awayPlayers : homePlayers)
        if let defender = defenders.first(where: { $0.lane == carrier.lane }) {
            if !defender.isSlowed {
                defender.move(toward: carrier.position, deltaTime: dt)
                // Collision (only when neither is in a slow window).
                if !carrier.isSlowed,
                   carrier.position.distance(to: defender.position) < GameConfig.duelTriggerDistance {
                    startDuel(kind: .interception, attacker: carrier, defender: defender,
                              intensity: 0.45)
                    return
                }
            }
        }

        // Idle players ease back toward their formation slots.
        for p in outfield(attackingHome ? homePlayers : awayPlayers) where p !== carrier {
            p.move(toward: CGPoint(x: (attackingHome ? homeFormationX(for: p.lane) : awayFormationX(for: p.lane)),
                                   y: laneY(p.lane)), deltaTime: dt * 0.6)
        }

        // Keepers shadow the ball's row inside their box.
        let defKeeper = keeper(attackingHome ? awayPlayers : homePlayers)
        let keeperX = attackingHome ? geometry.rect.maxX - 20 : geometry.rect.minX + 20
        defKeeper.move(toward: CGPoint(x: keeperX,
                                       y: max(geometry.rect.midY - 90, min(geometry.rect.midY + 90, carrier.position.y))),
                       deltaTime: dt)

        // Reached the penalty area → final shot duel vs the goalkeeper.
        let boxEdgeX = attackingHome ? geometry.rect.maxX - GameConfig.penaltyDepth
                                     : geometry.rect.minX + GameConfig.penaltyDepth
        let reachedBox = attackingHome ? carrier.position.x >= boxEdgeX
                                       : carrier.position.x <= boxEdgeX
        if reachedBox && !carrier.isSlowed {
            startDuel(kind: .shot, attacker: carrier, defender: defKeeper, intensity: 0.85)
        }
    }

    private func endMatch() {
        guard phase != .finished else { return }
        phase = .finished
        hud.hidePrompt()
        carrier?.setHasBall(false)
        ball.isHidden = true
        hud.showStatus("FULL TIME", fontSize: 46)
        gameDelegate?.matchDidFinish(homeStats: homeStats, homeScore: homeScore, awayScore: awayScore)
    }

    // MARK: Keyboard input (the human's typing)

    override func keyDown(with event: NSEvent) {
        guard case .duel = phase, typing.isActive else { return }
        guard let chars = event.charactersIgnoringModifiers, let ch = chars.first else { return }
        guard ch.isLetter else { return }
        let done = typing.input(ch)
        hud.showPrompt(typed: typing.typedPrefix, remaining: typing.remaining)
        if done {
            homeFinished = true
            gameDelegate?.localPlayerCompletedWord()
        }
    }

    // MARK: Multiplayer hook

    /// Called by MultipeerManager when the remote human finishes their word.
    func remotePlayerCompletedWord() {
        awayFinishedRemote = true
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

// preview

import SwiftUI

struct GameScenePreview: NSViewRepresentable {
    func makeNSView(context: Context) -> SKView {
        let view = SKView()
        
        let scene = GameScene(size: CGSize(width: 900, height: 600))
        scene.scaleMode = .aspectFit
        
        view.presentScene(scene)
        view.ignoresSiblingOrder = true
        return view
    }
    
    func updateNSView(_ nsView: SKView, context: Context) {}
}

#Preview {
    GameScenePreview()
}
