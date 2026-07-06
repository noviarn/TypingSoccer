//
//  PlayerNode.swift
//  TypingSoccer
//
//  Dummy sprite for a single player: a coloured disc with a role label.
//  Replace the drawing in `makeBody()` with real art later.
//

import SpriteKit

final class PlayerNode: SKNode {

    let team: Team
    let role: PlayerRole
    let baseSpeed: CGFloat

    private(set) var hasBall = false
    private(set) var isSlowed = false
    private var slowRemaining: TimeInterval = 0

    private let body = SKShapeNode()
    private let ring = SKShapeNode()   // highlight ring when carrying the ball

    /// The lane this player patrols (goalkeepers report their own goal lane = middle).
    var lane: Lane {
        if case let .outfield(l) = role { return l }
        return .middle
    }

    var isGoalkeeper: Bool {
        if case .goalkeeper = role { return true }
        return false
    }

    /// Current effective speed after any slow penalty.
    var currentSpeed: CGFloat { isSlowed ? baseSpeed * GameConfig.slowMultiplier : baseSpeed }

    init(team: Team, role: PlayerRole, baseSpeed: CGFloat) {
        self.team = team
        self.role = role
        self.baseSpeed = baseSpeed
        super.init()
        makeBody()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func makeBody() {
        let r = GameConfig.playerRadius
        body.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
        // Dummy colours: home = red-ish, away = blue-ish; keepers darker.
        let home = team == .home
        body.fillColor = isGoalkeeper
            ? (home ? SKColor(red: 0.6, green: 0.15, blue: 0.15, alpha: 1)
                    : SKColor(red: 0.15, green: 0.2, blue: 0.55, alpha: 1))
            : (home ? SKColor(red: 0.90, green: 0.35, blue: 0.25, alpha: 1)
                    : SKColor(red: 0.30, green: 0.55, blue: 0.95, alpha: 1))
        body.strokeColor = .white
        body.lineWidth = 2
        addChild(body)

        // Possession highlight ring (hidden by default).
        ring.path = CGPath(ellipseIn: CGRect(x: -r - 5, y: -r - 5, width: (r + 5) * 2, height: (r + 5) * 2), transform: nil)
        ring.strokeColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        ring.lineWidth = 3
        ring.isHidden = true
        addChild(ring)

        let label = SKLabelNode(text: labelText())
        label.fontName = "Menlo-Bold"
        label.fontSize = 11
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        addChild(label)
    }

    private func labelText() -> String {
        if isGoalkeeper { return "GK" }
        switch lane {
        case .top: return "1"
        case .middle: return "2"
        case .bottom: return "3"
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
    func move(toward point: CGPoint, deltaTime dt: TimeInterval) {
        let dx = point.x - position.x
        let dy = point.y - position.y
        let dist = hypot(dx, dy)
        guard dist > 1 else { return }
        let step = currentSpeed * CGFloat(dt)
        if step >= dist {
            position = point
        } else {
            position.x += dx / dist * step
            position.y += dy / dist * step
        }
    }
}
