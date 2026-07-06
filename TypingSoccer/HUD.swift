//
//  HUD.swift
//  TypingSoccer
//
//  Score + timer strip along the top, plus the big centred word prompt
//  and typed-progress display used during duels.
//

import SpriteKit

final class HUD: SKNode {
    
    private let homeScoreLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let awayScoreLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let timerLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let statusLabel = SKLabelNode(fontNamed: "Menlo-Bold")   // countdown / messages
    
    private let promptBg = SKShapeNode()
    private let typedLabel = SKLabelNode(fontNamed: "Menlo-Bold")     // already-typed (green)
    private let remainLabel = SKLabelNode(fontNamed: "Menlo-Bold")    // still-to-type (grey)
    
    //    private let sceneSize: CGSize
    
    private let sceneSize: CGSize
    private let fieldBottomY: CGFloat
    
    //    init(sceneSize: CGSize) {
    //        self.sceneSize = sceneSize
    //        super.init()
    //        build()
    //    }
    
    /// - Parameters:
    ///   - sceneSize: full scene size.
    ///   - fieldBottomY: the y-coordinate where the (now shortened) field ends,
    ///     i.e. `FieldBuilder.Geometry.rect.minY`. Used to center the word
    ///     prompt box in the gap between the field's bottom edge and the
    ///     bottom of the screen.
    init(sceneSize: CGSize, fieldBottomY: CGFloat) {
        self.sceneSize = sceneSize
        self.fieldBottomY = fieldBottomY
        super.init()
        build()
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func build() {
        let topY = sceneSize.height - GameConfig.hudHeight / 2
        
        homeScoreLabel.horizontalAlignmentMode = .left
        homeScoreLabel.position = CGPoint(x: GameConfig.fieldInset, y: topY)
        homeScoreLabel.fontSize = 26
        homeScoreLabel.fontColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        addChild(homeScoreLabel)
        
        awayScoreLabel.horizontalAlignmentMode = .right
        awayScoreLabel.position = CGPoint(x: sceneSize.width - GameConfig.fieldInset, y: topY)
        awayScoreLabel.fontSize = 26
        awayScoreLabel.fontColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        addChild(awayScoreLabel)
        
        timerLabel.horizontalAlignmentMode = .center
        timerLabel.position = CGPoint(x: sceneSize.width / 2, y: topY)
        timerLabel.fontSize = 26
        timerLabel.fontColor = .white
        addChild(timerLabel)
        
        statusLabel.horizontalAlignmentMode = .center
        statusLabel.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
        statusLabel.fontSize = 54
        statusLabel.fontColor = .white
        statusLabel.zPosition = 50
        addChild(statusLabel)
        
        //        // Word prompt (hidden until a duel starts).
        //        promptBg.path = CGPath(roundedRect: CGRect(x: -220, y: -34, width: 440, height: 68),
        //                               cornerWidth: 12, cornerHeight: 12, transform: nil)
        //        promptBg.fillColor = SKColor(white: 0, alpha: 0.65)
        //        promptBg.strokeColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        //        promptBg.lineWidth = 2
        //        promptBg.position = CGPoint(x: sceneSize.width / 2, y: GameConfig.fieldInset + 40)
        //        promptBg.zPosition = 40
        //        promptBg.isHidden = true
        //        addChild(promptBg)
        
        // Word prompt (hidden until a duel starts).
        promptBg.path = CGPath(roundedRect: CGRect(x: -220, y: -34, width: 440, height: 68),
                               cornerWidth: 12, cornerHeight: 12, transform: nil)
//        promptBg.fillColor = SKColor(white: 0, alpha: 0.65)
        promptBg.fillColor = SKColor(white: 1, alpha: 0.15)
        promptBg.strokeColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        promptBg.lineWidth = 2
        // Centered vertically in the gap between the bottom of the field
        // (fieldBottomY) and the bottom of the screen (y = 0).
        promptBg.position = CGPoint(x: sceneSize.width / 2, y: fieldBottomY / 2)
        promptBg.zPosition = 40
        promptBg.isHidden = true
        addChild(promptBg)
        
        typedLabel.horizontalAlignmentMode = .left
        typedLabel.verticalAlignmentMode = .center
        typedLabel.fontSize = 36
        typedLabel.fontColor = SKColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1)
        typedLabel.zPosition = 41
        promptBg.addChild(typedLabel)
        
        remainLabel.horizontalAlignmentMode = .left
        remainLabel.verticalAlignmentMode = .center
        remainLabel.fontSize = 36
        remainLabel.fontColor = SKColor(white: 0.7, alpha: 1)
        remainLabel.zPosition = 41
        promptBg.addChild(remainLabel)
        
        updateScore(home: 0, away: 0)
        setTimer(GameConfig.matchLengthSeconds)
    }
    
    // MARK: Updates
    
    func updateScore(home: Int, away: Int) {
        homeScoreLabel.text = "YOU  \(home)"
        awayScoreLabel.text = "\(away)  RIVAL"
    }
    
    func setTimer(_ seconds: TimeInterval) {
        let s = max(0, Int(seconds))
        timerLabel.text = String(format: "%d:%02d", s / 60, s % 60)
    }
    
    func showStatus(_ text: String, fontSize: CGFloat = 54) {
        statusLabel.fontSize = fontSize
        statusLabel.text = text
        statusLabel.isHidden = text.isEmpty
    }
    
    func hideStatus() { statusLabel.isHidden = true; statusLabel.text = "" }
    
    // MARK: Word prompt
    
    func showPrompt(typed: String, remaining: String) {
        promptBg.isHidden = false
        typedLabel.text = typed
        remainLabel.text = remaining
        // Lay out so the two labels read as one word, roughly centred.
        let full = typed + remaining
        let totalWidth = CGFloat(full.count) * 21.0   // approx glyph width at size 36 Menlo
        let startX = -totalWidth / 2
        typedLabel.position = CGPoint(x: startX, y: 0)
        remainLabel.position = CGPoint(x: startX + CGFloat(typed.count) * 21.0, y: 0)
    }
    
    func hidePrompt() { promptBg.isHidden = true }
}
