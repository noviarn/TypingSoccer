//
//  AIOpponent.swift
//  TypingSoccer
//
//  Simulates the rival team "typing" a word in single-player mode.
//  Given a word, it schedules a completion time based on a randomised
//  characters-per-second rate, with an occasional fumble to keep things fair.
//

import Foundation

final class AIOpponent {

    /// Time (seconds) the AI will need to finish `word`, decided up front.
    private(set) var scheduledFinish: TimeInterval = 0
    private var elapsed: TimeInterval = 0
    private(set) var finished = false

    /// Start a fresh contest for `word`. `skill` 0…1 scales the AI speed
    /// (e.g. a goalkeeper can be tougher on a shot).
    func begin(word: String, skill: Double = 0.5) {
        let range = GameConfig.aiCharsPerSecondRange
        let cps = range.lowerBound + (range.upperBound - range.lowerBound) * skill
        // Add jitter so it isn't perfectly deterministic.
        let jittered = cps * Double.random(in: 0.85...1.15)
        var time = Double(word.count) / max(1.0, jittered)
        if Double.random(in: 0...1) < GameConfig.aiFumbleChance {
            time += Double.random(in: 0.4...1.2)   // a fumble/pause
        }
        scheduledFinish = time
        elapsed = 0
        finished = false
    }

    /// Advance the AI clock. Returns true on the tick it completes the word.
    @discardableResult
    func update(deltaTime: TimeInterval) -> Bool {
        guard !finished, scheduledFinish > 0 else { return false }
        elapsed += deltaTime
        if elapsed >= scheduledFinish {
            finished = true
            return true
        }
        return false
    }

    /// AI progress 0…1 for optional on-screen display.
    var progress: Double {
        guard scheduledFinish > 0 else { return 0 }
        return min(1, elapsed / scheduledFinish)
    }

    func reset() {
        scheduledFinish = 0
        elapsed = 0
        finished = false
    }
}
