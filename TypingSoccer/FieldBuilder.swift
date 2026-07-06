//
//  FieldBuilder.swift
//  TypingSoccer
//
//  Draws the pitch: outline, halfway line, centre circle, three lanes,
//  and the two penalty areas. Pure dummy vector art.
//

import SpriteKit

enum FieldBuilder {

    struct Geometry {
        let rect: CGRect          // playable field rect
        let laneY: [CGFloat]      // y position for top, middle, bottom lanes
    }

    /// Builds all static field nodes into `parent` and returns geometry
    /// the game logic needs (lane rows, field bounds).
    @discardableResult
    static func build(in parent: SKNode, sceneSize: CGSize) -> Geometry {
        let inset = GameConfig.fieldInset
        let rect = CGRect(
            x: inset,
            y: inset,
            width: sceneSize.width - inset * 2,
            height: sceneSize.height - inset * 2 - GameConfig.hudHeight
        )

        // Pitch background.
        let pitch = SKShapeNode(rect: rect)
        pitch.fillColor = SKColor(red: 0.05, green: 0.09, blue: 0.16, alpha: 1)
        pitch.strokeColor = SKColor(white: 0.6, alpha: 0.8)
        pitch.lineWidth = 2
        pitch.zPosition = 0
        parent.addChild(pitch)

        // Halfway line.
        let midX = rect.midX
        let halfway = SKShapeNode()
        let hp = CGMutablePath()
        hp.move(to: CGPoint(x: midX, y: rect.minY))
        hp.addLine(to: CGPoint(x: midX, y: rect.maxY))
        halfway.path = hp
        halfway.strokeColor = SKColor(white: 0.5, alpha: 0.6)
        halfway.lineWidth = 1.5
        parent.addChild(halfway)

        // Centre circle.
        let circle = SKShapeNode(circleOfRadius: 70)
        circle.position = CGPoint(x: midX, y: rect.midY)
        circle.strokeColor = SKColor(white: 0.5, alpha: 0.6)
        circle.lineWidth = 1.5
        parent.addChild(circle)

        // Three lanes.
        let laneYs: [CGFloat] = [
            rect.minY + rect.height * 0.78,   // top
            rect.midY,                        // middle
            rect.minY + rect.height * 0.22    // bottom
        ]
        for y in laneYs {
            let lane = SKShapeNode()
            let lp = CGMutablePath()
            lp.move(to: CGPoint(x: rect.minX, y: y))
            lp.addLine(to: CGPoint(x: rect.maxX, y: y))
            lp.move(to: CGPoint(x: rect.minX, y: y))
            lane.path = lp
            lane.strokeColor = SKColor(white: 0.35, alpha: 0.5)
            lane.lineWidth = 1
            // dashed
            lane.path = lp.copy(dashingWithPhase: 0, lengths: [10, 8])
            parent.addChild(lane)
        }

        // Penalty areas.
        let boxHeight = rect.height * 0.6
        let boxY = rect.midY - boxHeight / 2
        for isLeft in [true, false] {
            let boxRect = CGRect(
                x: isLeft ? rect.minX : rect.maxX - GameConfig.penaltyDepth,
                y: boxY,
                width: GameConfig.penaltyDepth,
                height: boxHeight
            )
            let box = SKShapeNode(rect: boxRect)
            box.strokeColor = SKColor(white: 0.45, alpha: 0.6)
            box.lineWidth = 1.5
            parent.addChild(box)

            // Goal mouth marker.
            let goal = SKShapeNode(rect: CGRect(
                x: isLeft ? rect.minX - 8 : rect.maxX,
                y: rect.midY - boxHeight * 0.25,
                width: 8,
                height: boxHeight * 0.5))
            goal.fillColor = SKColor(white: 0.85, alpha: 0.9)
            goal.strokeColor = .clear
            parent.addChild(goal)
        }

        return Geometry(rect: rect, laneY: laneYs)
    }
}
