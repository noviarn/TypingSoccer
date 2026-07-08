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
    private let pensLabel = SKLabelNode(fontNamed: "Menlo-Bold")     // shootout tally

    private let toastLabel = SKLabelNode(fontNamed: "Menlo-Bold")   // brief messages
    private let promptBg = SKShapeNode()
    private let typedLabel = SKLabelNode(fontNamed: "Menlo-Bold")     // already-typed (green)
    private let remainLabel = SKLabelNode(fontNamed: "Menlo-Bold")    // still-to-type (grey)
    // Rival's live progress on the same word (small row under the main word).
    private let enemyTypedLabel = SKLabelNode(fontNamed: "Menlo-Bold")   // rival-typed (orange)
    private let enemyRemainLabel = SKLabelNode(fontNamed: "Menlo-Bold")  // rival-remaining (dark)

    // Bottom-corner stat panels (energy + speed) for the two spotlighted players.
    private let leftPanel = SKNode()
    private let rightPanel = SKNode()
    private let leftPanelTitle = SKLabelNode(fontNamed: "Menlo-Bold")
    private let rightPanelTitle = SKLabelNode(fontNamed: "Menlo-Bold")
    private let leftEnergyFill = SKShapeNode()
    private let rightEnergyFill = SKShapeNode()
    private let leftSpeedLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let rightSpeedLabel = SKLabelNode(fontNamed: "Menlo-Bold")

    private let sceneSize: CGSize
    /// Settings-driven multiplier for HUD/word text (1.0…1.5).
    private let textScale: CGFloat

    init(sceneSize: CGSize, textScale: CGFloat = 1.0) {
        self.sceneSize = sceneSize
        self.textScale = max(1.0, min(1.5, textScale))
        super.init()
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let topY = sceneSize.height - GameConfig.hudHeight / 2

        homeScoreLabel.horizontalAlignmentMode = .left
        homeScoreLabel.position = CGPoint(x: GameConfig.fieldInset, y: topY)
        homeScoreLabel.fontSize = 26 * textScale
        homeScoreLabel.fontColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        addChild(homeScoreLabel)

        awayScoreLabel.horizontalAlignmentMode = .right
        awayScoreLabel.position = CGPoint(x: sceneSize.width - GameConfig.fieldInset, y: topY)
        awayScoreLabel.fontSize = 26 * textScale
        awayScoreLabel.fontColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        addChild(awayScoreLabel)

        timerLabel.horizontalAlignmentMode = .center
        timerLabel.position = CGPoint(x: sceneSize.width / 2, y: topY)
        timerLabel.fontSize = 26 * textScale
        timerLabel.fontColor = .white
        addChild(timerLabel)

        // Penalty shootout tally, just under the timer (hidden until needed).
        pensLabel.horizontalAlignmentMode = .center
        pensLabel.position = CGPoint(x: sceneSize.width / 2, y: topY - 26)
        pensLabel.fontSize = 15 * textScale
        pensLabel.fontColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        pensLabel.zPosition = 50
        pensLabel.isHidden = true
        addChild(pensLabel)

        statusLabel.horizontalAlignmentMode = .center
        statusLabel.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
        statusLabel.fontSize = 54
        statusLabel.fontColor = .white
        statusLabel.zPosition = 50
        addChild(statusLabel)

        // Transient toast (formation changes, etc.) just under the HUD strip.
        toastLabel.horizontalAlignmentMode = .center
        toastLabel.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height - GameConfig.hudHeight - 18)
        toastLabel.fontSize = 18 * textScale
        toastLabel.fontColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        toastLabel.zPosition = 60
        toastLabel.alpha = 0
        addChild(toastLabel)

        // Word prompt (hidden until a duel starts) — sized to the text scale.
        let promptW = 440 * textScale
        let promptH = 68 * textScale
        promptBg.path = CGPath(roundedRect: CGRect(x: -promptW / 2, y: -promptH / 2,
                                                   width: promptW, height: promptH),
                               cornerWidth: 12, cornerHeight: 12, transform: nil)
        promptBg.fillColor = SKColor(white: 0, alpha: 0.65)
        promptBg.strokeColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        promptBg.lineWidth = 2
        promptBg.position = CGPoint(x: sceneSize.width / 2, y: GameConfig.fieldInset + 40)
        promptBg.zPosition = 40
        promptBg.isHidden = true
        addChild(promptBg)

        typedLabel.horizontalAlignmentMode = .left
        typedLabel.verticalAlignmentMode = .center
        typedLabel.fontSize = 36 * textScale
        typedLabel.fontColor = SKColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1)
        typedLabel.zPosition = 41
        promptBg.addChild(typedLabel)

        remainLabel.horizontalAlignmentMode = .left
        remainLabel.verticalAlignmentMode = .center
        remainLabel.fontSize = 36 * textScale
        remainLabel.fontColor = SKColor(white: 0.7, alpha: 1)
        remainLabel.zPosition = 41
        promptBg.addChild(remainLabel)

        // Rival's progress row, small and orange so it can't be confused
        // with your own green progress above it.
        for l in [enemyTypedLabel, enemyRemainLabel] {
            l.horizontalAlignmentMode = .left
            l.verticalAlignmentMode = .center
            l.fontSize = 15 * textScale
            l.zPosition = 41
            promptBg.addChild(l)
        }
        enemyTypedLabel.fontColor = SKColor(red: 1, green: 0.45, blue: 0.2, alpha: 1)
        enemyRemainLabel.fontColor = SKColor(white: 0.4, alpha: 1)

        buildStatPanel(panel: leftPanel, title: leftPanelTitle,
                       fill: leftEnergyFill, speed: leftSpeedLabel,
                       center: CGPoint(x: GameConfig.fieldInset + 106,
                                       y: GameConfig.fieldInset + 38))
        buildStatPanel(panel: rightPanel, title: rightPanelTitle,
                       fill: rightEnergyFill, speed: rightSpeedLabel,
                       center: CGPoint(x: sceneSize.width - GameConfig.fieldInset - 106,
                                       y: GameConfig.fieldInset + 38))

        updateScore(home: 0, away: 0)
        setTimer(0)   // football clock counts up from 0:00 to 90:00
    }

    /// One bottom-corner panel: name, energy bar, current speed readout.
    private func buildStatPanel(panel: SKNode, title: SKLabelNode,
                                fill: SKShapeNode, speed: SKLabelNode, center: CGPoint) {
        panel.position = center
        panel.zPosition = 45
        panel.isHidden = true
        addChild(panel)

        let bg = SKShapeNode(path: CGPath(roundedRect: CGRect(x: -92, y: -28, width: 184, height: 56),
                                          cornerWidth: 8, cornerHeight: 8, transform: nil))
        bg.fillColor = SKColor(white: 0, alpha: 0.55)
        bg.strokeColor = SKColor(white: 1, alpha: 0.25)
        bg.lineWidth = 1
        panel.addChild(bg)

        title.fontSize = 11
        title.fontColor = .white
        title.horizontalAlignmentMode = .left
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: -82, y: 15)
        panel.addChild(title)

        let barBg = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 128, height: 8))
        barBg.fillColor = SKColor(white: 1, alpha: 0.15)
        barBg.strokeColor = .clear
        barBg.position = CGPoint(x: -82, y: -4)
        panel.addChild(barBg)

        fill.path = CGPath(rect: CGRect(x: 0, y: 0, width: 128, height: 8), transform: nil)
        fill.strokeColor = .clear
        fill.position = CGPoint(x: -82, y: -4)
        panel.addChild(fill)

        speed.fontSize = 10
        speed.fontColor = SKColor(white: 0.8, alpha: 1)
        speed.horizontalAlignmentMode = .left
        speed.verticalAlignmentMode = .center
        speed.position = CGPoint(x: -82, y: -19)
        panel.addChild(speed)
    }

    // MARK: Updates

    private var homeName = "YOU"
    private var awayName = "RIVAL"
    private var lastHome = 0
    private var lastAway = 0

    /// World Cup mode: put the real team names on the scoreboard.
    func setTeamNames(home: String, away: String) {
        homeName = home.uppercased()
        awayName = away.uppercased()
        updateScore(home: lastHome, away: lastAway)
    }

    func updateScore(home: Int, away: Int) {
        lastHome = home
        lastAway = away
        homeScoreLabel.text = "\(homeName)  \(home)"
        awayScoreLabel.text = "\(away)  \(awayName)"
    }

    private var lastTimerText: String?

    func setTimer(_ seconds: TimeInterval, addedMinutes: Double = 0) {
        let s = max(0, Int(seconds))
        var text = String(format: "%d:%02d", s / 60, s % 60)
        if addedMinutes > 0 { text += "  +\(Int(ceil(addedMinutes)))" }   // e.g. 45:00  +3
        // Re-rasterizing an SKLabelNode is expensive; skip unchanged frames.
        guard text != lastTimerText else { return }
        lastTimerText = text
        timerLabel.text = text
    }

    func showStatus(_ text: String, fontSize: CGFloat = 54) {
        statusLabel.fontSize = fontSize * textScale
        statusLabel.text = text
        statusLabel.isHidden = text.isEmpty
    }

    func hideStatus() { statusLabel.isHidden = true; statusLabel.text = "" }

    /// Show/update the penalty shootout tally under the timer.
    func setPenaltyTally(home: Int, away: Int) {
        pensLabel.isHidden = false
        pensLabel.text = "PENS  \(home) – \(away)"
    }

    /// Briefly flash a small message (e.g. a formation change).
    func showToast(_ text: String) {
        toastLabel.removeAllActions()
        toastLabel.text = text
        toastLabel.alpha = 1
        toastLabel.run(.sequence([.wait(forDuration: 1.4), .fadeOut(withDuration: 0.4)]))
    }

    // MARK: Word prompt

    private var lastTyped: String?
    private var lastRemaining: String?

    func showPrompt(typed: String, remaining: String) {
        promptBg.isHidden = false
        // Called every frame during a duel — only touch the labels on change.
        guard typed != lastTyped || remaining != lastRemaining else { return }
        lastTyped = typed
        lastRemaining = remaining
        typedLabel.text = typed
        remainLabel.text = remaining
        // Lay out so the two labels read as one word, roughly centred.
        let glyph = 21.0 * textScale   // approx glyph width at size 36 Menlo, scaled
        let full = typed + remaining
        let totalWidth = CGFloat(full.count) * glyph
        let startX = -totalWidth / 2
        typedLabel.position = CGPoint(x: startX, y: 7 * textScale)
        remainLabel.position = CGPoint(x: startX + CGFloat(typed.count) * glyph, y: 7 * textScale)
    }

    /// Update the rival's progress row on the current duel word: the letters
    /// the rival has already "typed" show in orange under the main word, so
    /// you can see at a glance if it's ahead of you.
    private var lastEnemyWord: String?
    private var lastEnemyCount = -1

    func updateEnemyProgress(word: String, typedCount: Int) {
        let count = max(0, min(typedCount, word.count))
        // Called every frame during a duel — only touch the labels on change.
        guard word != lastEnemyWord || count != lastEnemyCount else { return }
        lastEnemyWord = word
        lastEnemyCount = count
        enemyTypedLabel.text = String(word.prefix(count))
        enemyRemainLabel.text = String(word.suffix(word.count - count))
        let glyph: CGFloat = 9.0 * textScale   // approx glyph width at size 15 Menlo, scaled
        let startX = -CGFloat(word.count) * glyph / 2
        enemyTypedLabel.position = CGPoint(x: startX, y: -20 * textScale)
        enemyRemainLabel.position = CGPoint(x: startX + CGFloat(count) * glyph, y: -20 * textScale)
    }

    func hidePrompt() {
        promptBg.isHidden = true
        enemyTypedLabel.text = ""
        enemyRemainLabel.text = ""
        lastTyped = nil
        lastRemaining = nil
        lastEnemyWord = nil
        lastEnemyCount = -1
    }

    // MARK: Stat panels (energy + current speed)

    /// Per-panel cache so labels/colors are only touched when they change
    /// (SKLabelNode text and SKShapeNode fillColor updates are expensive).
    private struct PanelCache { var title: String?; var speedText: String?; var band = -1 }
    private var leftPanelCache = PanelCache()
    private var rightPanelCache = PanelCache()

    /// Refresh one bottom-corner panel. `left` is the home side of the pitch.
    func updateStatPanel(left: Bool, title: String, energy: CGFloat, speed: CGFloat) {
        let panel = left ? leftPanel : rightPanel
        let titleLabel = left ? leftPanelTitle : rightPanelTitle
        let fill = left ? leftEnergyFill : rightEnergyFill
        let speedLabel = left ? leftSpeedLabel : rightSpeedLabel
        var cache = left ? leftPanelCache : rightPanelCache

        panel.isHidden = false
        if title != cache.title {
            cache.title = title
            titleLabel.text = title
        }
        let frac = max(0, min(1, energy / GameConfig.energyMax))
        fill.xScale = frac   // scaling is cheap; no geometry rebuild
        let band = frac > 0.5 ? 2 : frac > 0.25 ? 1 : 0
        if band != cache.band {
            cache.band = band
            fill.fillColor = band == 2 ? SKColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1)
                           : band == 1 ? SKColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 1)
                           : SKColor(red: 1.0, green: 0.35, blue: 0.3, alpha: 1)
        }
        let speedText = "SPD \(Int(speed.rounded()))   EN \(Int((frac * 100).rounded()))%"
        if speedText != cache.speedText {
            cache.speedText = speedText
            speedLabel.text = speedText
        }
        if left { leftPanelCache = cache } else { rightPanelCache = cache }
    }

    func setStatPanelsHidden(_ hidden: Bool) {
        leftPanel.isHidden = hidden
        rightPanel.isHidden = hidden
    }
}
