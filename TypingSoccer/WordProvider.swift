//
//  WordProvider.swift
//  TypingSoccer
//
//  Local word bank used for in-game typing duels.
//  (Apple Foundation Models is used only for the post-match feedback —
//   see MatchFeedback.swift.)
//

import Foundation

struct WordProvider {

    /// Buckets by difficulty so we can ramp the challenge closer to goal.
    private static let easy = [
        "goal", "pass", "kick", "run", "ball", "team", "shot", "save",
        "win", "fast", "move", "dash", "wing", "post", "net", "play"
    ]

    private static let medium = [
        "striker", "tackle", "defend", "sprint", "corner", "header",
        "dribble", "counter", "offside", "keeper", "volley", "assist"
    ]

    private static let hard = [
        "midfielder", "possession", "formation", "goalkeeper",
        "counterattack", "substitution", "championship", "penalty",
        "tournament", "breakaway", "playmaker", "equalizer"
    ]

    /// Returns a word appropriate for the current situation.
    /// `intensity` 0…1 nudges toward harder words (e.g. near the goal).
    static func word(intensity: Double = 0.3) -> String {
        let roll = Double.random(in: 0...1)
        let pool: [String]
        switch intensity {
        case ..<0.34:
            pool = roll < 0.75 ? easy : medium
        case ..<0.67:
            pool = roll < 0.5 ? medium : (roll < 0.85 ? easy : hard)
        default:
            pool = roll < 0.6 ? hard : medium
        }
        return pool.randomElement() ?? "goal"
    }
}
