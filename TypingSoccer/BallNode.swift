//
//  BallNode.swift
//  TypingSoccer
//
//  Dummy ball sprite. Replace with real art later.
//

import SpriteKit

final class BallNode: SKShapeNode {

    static func make() -> BallNode {
        let r = GameConfig.ballRadius
        let ball = BallNode(ellipseOf: CGSize(width: r * 2, height: r * 2))
        ball.fillColor = .white
        ball.strokeColor = SKColor(white: 0.2, alpha: 1)
        ball.lineWidth = 1.5
        ball.zPosition = 5
        return ball
    }
}
