//
//  TypingController.swift
//  TypingSoccer
//
//  Tracks the human's progress typing the current duel word.
//  Correct next-character advances; a wrong key counts as a mistake
//  but does not advance (the player must hit the right key).
//

import Foundation

final class TypingController {

    private(set) var target: String = ""
    private(set) var typedCount: Int = 0
    private(set) var mistakes: Int = 0
    private var startTime: Date?

    var isActive: Bool { !target.isEmpty && typedCount < target.count }
    var isComplete: Bool { !target.isEmpty && typedCount >= target.count }

    /// Fraction typed so far, 0…1 — handy for progress bars.
    var progress: Double {
        guard !target.isEmpty else { return 0 }
        return Double(typedCount) / Double(target.count)
    }

    /// The substring already typed correctly.
    var typedPrefix: String { String(target.prefix(typedCount)) }
    /// The remaining substring still to type.
    var remaining: String { String(target.suffix(target.count - typedCount)) }

    func begin(word: String) {
        target = word.lowercased()
        typedCount = 0
        mistakes = 0
        startTime = Date()
    }

    /// Feed a single typed character. Returns true when the word is finished.
    @discardableResult
    func input(_ character: Character) -> Bool {
        guard isActive else { return isComplete }
        let chars = Array(target)
        let expected = chars[typedCount]
        if Character(character.lowercased()) == expected {
            typedCount += 1
        } else {
            mistakes += 1
        }
        return isComplete
    }

    /// Seconds elapsed since the word began.
    var elapsedSeconds: Double {
        guard let s = startTime else { return 0 }
        return Date().timeIntervalSince(s)
    }

    func reset() {
        target = ""
        typedCount = 0
        mistakes = 0
        startTime = nil
    }
}
