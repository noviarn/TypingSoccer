//
//  PlayerNode.swift
//  TypingSoccer
//
//  Dummy sprite for a single player: a coloured disc with a role label.
//  Replace the drawing in `makeBody()` with real art later.
//

import SpriteKit

//final class PlayerNode: SKNode {
//
//    let team: Team
//    let role: PlayerRole
//    let baseSpeed: CGFloat
//    /// Real player name (World Cup mode); shown under the circle and in the
//    /// stat panels. Nil = generic dummy player.
//    let playerName: String?
//
//    private(set) var hasBall = false
//    private(set) var isSlowed = false
//    private var slowRemaining: TimeInterval = 0
//
//    // Energy / stamina. Drains while running, regenerates while resting.
//    private(set) var energy: CGFloat = GameConfig.energyMax
//    private var movedThisFrame = false
//
//    private let body = SKShapeNode()
//    private let ring = SKShapeNode()   // highlight ring when carrying the ball
//
//    /// The lane this player patrols (goalkeepers report their own goal lane = middle).
//    var lane: Lane {
//        if case let .outfield(l) = role { return l }
//        return .middle
//    }
//
//    var isGoalkeeper: Bool {
//        if case .goalkeeper = role { return true }
//        return false
//    }
//
//    /// Current effective speed after any slow penalty, ball-carry penalty
//    /// and energy fatigue (an exhausted player runs at half pace).
//    var currentSpeed: CGFloat {
//        var speed = baseSpeed
//        if isSlowed { speed *= GameConfig.slowMultiplier }
//        if hasBall { speed *= GameConfig.ballCarryMultiplier }  // slower while carrying
//        let minF = GameConfig.energyMinSpeedFactor
//        speed *= minF + (1 - minF) * (energy / GameConfig.energyMax)
//        return speed
//    }
//
//    // MARK: Energy
//
//    /// Partial recovery at a half-time / extra-time break.
//    func restoreEnergy(_ amount: CGFloat) {
//        energy = min(GameConfig.energyMax, energy + amount)
//    }
//
//    /// Call once per frame AFTER movement: drains if the player actually ran
//    /// this frame, otherwise regenerates. Carrying the ball drains faster.
//    func tickEnergy(deltaTime dt: TimeInterval) {
//        if movedThisFrame {
//            let drain = hasBall ? GameConfig.energyCarrierDrainPerSecond
//                                : GameConfig.energyDrainPerSecond
//            energy = max(0, energy - drain * CGFloat(dt))
//        } else {
//            energy = min(GameConfig.energyMax, energy + GameConfig.energyRegenPerSecond * CGFloat(dt))
//        }
//        movedThisFrame = false
//    }
//
//    init(team: Team, role: PlayerRole, baseSpeed: CGFloat, playerName: String? = nil) {
//        self.team = team
//        self.role = role
//        self.baseSpeed = baseSpeed
//        self.playerName = playerName
//        super.init()
//        makeBody()
//    }
//
//    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
//
//    private func makeBody() {
//        let r = GameConfig.playerRadius
//        body.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
//        // Dummy colours: home = red-ish, away = blue-ish; keepers darker.
//        let home = team == .home
//        body.fillColor = isGoalkeeper
//            ? (home ? SKColor(red: 0.6, green: 0.15, blue: 0.15, alpha: 1)
//                    : SKColor(red: 0.15, green: 0.2, blue: 0.55, alpha: 1))
//            : (home ? SKColor(red: 0.90, green: 0.35, blue: 0.25, alpha: 1)
//                    : SKColor(red: 0.30, green: 0.55, blue: 0.95, alpha: 1))
//        body.strokeColor = .white
//        body.lineWidth = 2
//        addChild(body)
//
//        // Possession highlight ring (hidden by default).
//        ring.path = CGPath(ellipseIn: CGRect(x: -r - 5, y: -r - 5, width: (r + 5) * 2, height: (r + 5) * 2), transform: nil)
//        ring.strokeColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
//        ring.lineWidth = 3
//        ring.isHidden = true
//        addChild(ring)
//
//        let label = SKLabelNode(text: labelText())
//        label.fontName = "Menlo-Bold"
//        label.fontSize = 11
//        label.fontColor = .white
//        label.verticalAlignmentMode = .center
//        addChild(label)
//
//        // Real name under the circle (World Cup mode only).
//        if let playerName {
//            let name = SKLabelNode(text: playerName)
//            name.fontName = "Menlo-Bold"
//            name.fontSize = 9
//            name.fontColor = SKColor(white: 0.85, alpha: 0.9)
//            name.verticalAlignmentMode = .top
//            name.position = CGPoint(x: 0, y: -r - 7)
//            addChild(name)
//        }
//    }
//
//    private func labelText() -> String {
//        if isGoalkeeper { return "GK" }
//        switch lane {
//        case .top: return "1"
//        case .middle: return "2"
//        case .bottom: return "3"
//        }
//    }
//
//    // MARK: Possession
//
//    func setHasBall(_ value: Bool) {
//        hasBall = value
//        ring.isHidden = !value
//    }
//
//    // MARK: Slow penalty (after losing a duel)
//
//    func applySlow() {
//        isSlowed = true
//        slowRemaining = GameConfig.slowDuration
//        body.alpha = 0.5
//    }
//
//    /// Call every frame; returns true on the tick the slow wears off.
//    @discardableResult
//    func tickSlow(deltaTime: TimeInterval) -> Bool {
//        guard isSlowed else { return false }
//        slowRemaining -= deltaTime
//        if slowRemaining <= 0 {
//            isSlowed = false
//            body.alpha = 1
//            return true
//        }
//        return false
//    }
//
//    /// Move this player toward `point` at its current speed for `dt` seconds.
//    /// `speedScale` temporarily scales the speed (e.g. 0.5 while retreating from
//    /// an offside position).
//    func move(toward point: CGPoint, deltaTime dt: TimeInterval, speedScale: CGFloat = 1) {
//        let dx = point.x - position.x
//        let dy = point.y - position.y
//        let dist = hypot(dx, dy)
//        guard dist > 1 else { return }
//        movedThisFrame = true
//        let step = currentSpeed * speedScale * CGFloat(dt)
//        if step >= dist {
//            position = point
//        } else {
//            position.x += dx / dist * step
//            position.y += dy / dist * step
//        }
//    }
//}

final class PlayerNode: SKNode {

    let team: Team
    let role: PlayerRole
    let baseSpeed: CGFloat
    /// Real player name (World Cup mode); shown under the circle and in the
    /// stat panels. Nil = generic dummy player.
    let playerName: String?

    private(set) var hasBall = false
    private(set) var isSlowed = false
    private var slowRemaining: TimeInterval = 0

    // Energy / stamina. Drains while running, regenerates while resting.
    private(set) var energy: CGFloat = GameConfig.energyMax
    private var movedThisFrame = false

    private let body = SKSpriteNode()
    private let ring = SKShapeNode()   // highlight ring when carrying the ball

    // Which way the sprite is currently facing. Assets are assumed to face
    // RIGHT by default; facing left mirrors the sprite horizontally.
    private var facingRight = true

    /// The lane this player patrols (goalkeepers report their own goal lane = middle).
    var lane: Lane {
        if case let .outfield(l) = role { return l }
        return .middle
    }

    var isGoalkeeper: Bool {
        if case .goalkeeper = role { return true }
        return false
    }

    /// Current effective speed after any slow penalty, ball-carry penalty
    /// and energy fatigue (an exhausted player runs at half pace).
    var currentSpeed: CGFloat {
        var speed = baseSpeed
        if isSlowed { speed *= GameConfig.slowMultiplier }
        if hasBall { speed *= GameConfig.ballCarryMultiplier }  // slower while carrying
        let minF = GameConfig.energyMinSpeedFactor
        speed *= minF + (1 - minF) * (energy / GameConfig.energyMax)
        return speed
    }

    // MARK: Energy

    /// Partial recovery at a half-time / extra-time break.
    func restoreEnergy(_ amount: CGFloat) {
        energy = min(GameConfig.energyMax, energy + amount)
    }

    /// Call once per frame AFTER movement: drains if the player actually ran
    /// this frame, otherwise regenerates. Carrying the ball drains faster.
    func tickEnergy(deltaTime dt: TimeInterval) {
        if movedThisFrame {
            let drain = hasBall ? GameConfig.energyCarrierDrainPerSecond
                                : GameConfig.energyDrainPerSecond
            energy = max(0, energy - drain * CGFloat(dt))
        } else {
            energy = min(GameConfig.energyMax, energy + GameConfig.energyRegenPerSecond * CGFloat(dt))
        }
        movedThisFrame = false
    }

    init(team: Team, role: PlayerRole, baseSpeed: CGFloat, playerName: String? = nil) {
        self.team = team
        self.role = role
        self.baseSpeed = baseSpeed
        self.playerName = playerName
        super.init()
        makeBody()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func makeBody() {
        let r = GameConfig.playerRadius
        // `.home` is always the local human's side (in single player AND in
        // multiplayer, since each machine renders its own team as `.home`
        // — see GameScene's mirrorX / localTeam(wireHome:) logic). So this
        // mapping is simply "us = blue, rivals = red" everywhere.
        let home = team == .home
        let texture = SKTexture(imageNamed: home ? "blue-player" : "red-player")
        body.texture = texture
        body.size = CGSize(width: r * 2, height: r * 2)
        // Goalkeepers get a subtle dark tint so they read as distinct from
        // outfielders without needing separate art assets.
        if isGoalkeeper {
            body.color = .black
            body.colorBlendFactor = 0.35
        }
        addChild(body)

        // Idle/default facing: home (attacking rightward) faces right,
        // away (attacking leftward) faces left. Movement direction can
        // still override this once the player actually starts running
        // — see move(toward:deltaTime:speedScale:).
        facingRight = home
        body.xScale = facingRight ? abs(body.xScale) : -abs(body.xScale)

        // Possession highlight ring (hidden by default).
        ring.path = CGPath(ellipseIn: CGRect(x: -r - 5, y: -r - 5, width: (r + 5) * 2, height: (r + 5) * 2), transform: nil)
        ring.strokeColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        ring.lineWidth = 3
        ring.isHidden = true
        addChild(ring)

        if isGoalkeeper {
            let label = SKLabelNode(text: "GK")
            label.fontName = "Menlo-Bold"
            label.fontSize = 11
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            label.zPosition = 1   // sit above the sprite
            addChild(label)
        }

        // Real name under the circle (World Cup mode only).
        if let playerName {
            let name = SKLabelNode(text: playerName)
            name.fontName = "Menlo-Bold"
            name.fontSize = 9
            name.fontColor = SKColor(white: 0.85, alpha: 0.9)
            name.verticalAlignmentMode = .top
            name.position = CGPoint(x: 0, y: -r - 7)
            name.zPosition = 1
            addChild(name)
        }
    }

    // MARK: Possession

    func setHasBall(_ value: Bool) {
        hasBall = value
        ring.isHidden = !value
    }

    // MARK: Slow penalty (after losing a duel)

    func applySlow() {
        isSlowed = true
        slowRemaining = GameConfig.slowDuration
        body.alpha = 0.5
    }

    /// Call every frame; returns true on the tick the slow wears off.
    @discardableResult
    func tickSlow(deltaTime: TimeInterval) -> Bool {
        guard isSlowed else { return false }
        slowRemaining -= deltaTime
        if slowRemaining <= 0 {
            isSlowed = false
            body.alpha = 1
            return true
        }
        return false
    }

    /// Move this player toward `point` at its current speed for `dt` seconds.
    /// `speedScale` temporarily scales the speed (e.g. 0.5 while retreating from
    /// an offside position). Also flips the sprite to face the direction of
    /// horizontal travel.
    func move(toward point: CGPoint, deltaTime dt: TimeInterval, speedScale: CGFloat = 1) {
        let dx = point.x - position.x
        let dy = point.y - position.y
        let dist = hypot(dx, dy)
        guard dist > 1 else { return }
        movedThisFrame = true

        // Only re-face on a meaningful horizontal component, so purely
        // vertical movement (dx ≈ 0) doesn't cause flicker between facings.
        if abs(dx) > 1 {
            let shouldFaceRight = dx > 0
            if shouldFaceRight != facingRight {
                facingRight = shouldFaceRight
                body.xScale = facingRight ? abs(body.xScale) : -abs(body.xScale)
            }
        }

        let step = currentSpeed * speedScale * CGFloat(dt)
        if step >= dist {
            position = point
        } else {
            position.x += dx / dist * step
            position.y += dy / dist * step
        }
    }
}
