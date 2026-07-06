//
//  GameModels.swift
//  TypingSoccer
//
//  Core value types shared across the game.
//

import Foundation

/// The two sides. `home` is the local human in single-player;
/// `away` is the AI (single-player) or the remote peer (multiplayer).
enum Team: String, Codable {
    case home
    case away

    var opponent: Team { self == .home ? .away : .home }
    var displayName: String { self == .home ? "YOU" : "RIVAL" }
}

/// Which of the three horizontal tracks a player belongs to.
enum Lane: Int, Codable, CaseIterable {
    case top = 0
    case middle = 1
    case bottom = 2
}

/// A player is either an outfield runner (tied to a lane) or the keeper.
enum PlayerRole: Equatable {
    case outfield(Lane)
    case goalkeeper
}

/// High-level match state machine.
enum GamePhase: Equatable {
    case countdown          // whistle + 3-2-1
    case kickoff            // first word decides who gets the ball
    case running            // a carrier is advancing, defenders closing
    case duel(DuelKind)     // a word is being typed to resolve a contest
    case goalScored(Team)   // brief celebration / reset
    case finished           // time up
}

/// What a typing duel is resolving.
enum DuelKind: Equatable {
    case kickoff            // possession from the opening whistle
    case interception       // defender caught the carrier mid-field
    case shot               // carrier vs goalkeeper at the box
}

/// Which mode the match is running in.
enum MatchMode: Equatable {
    case singlePlayer       // away team driven by AIOpponent
    case multipeer          // away team driven by a remote human via MultipeerManager
}

/// Per-player running tally, fed to Foundation Models for the end screen.
struct PlayerStats: Codable {
    var wordsCompleted = 0
    var totalKeystrokes = 0
    var mistakes = 0
    var duelsWon = 0
    var duelsLost = 0
    var goals = 0
    var fastestWordSeconds: Double? = nil
    var totalTypingSeconds = 0.0

    /// Words-per-minute across the match (5 chars == 1 "word").
    var averageWPM: Double {
        guard totalTypingSeconds > 0 else { return 0 }
        let words = Double(totalKeystrokes) / 5.0
        return words / (totalTypingSeconds / 60.0)
    }

    var accuracy: Double {
        guard totalKeystrokes > 0 else { return 1 }
        return Double(totalKeystrokes - mistakes) / Double(totalKeystrokes)
    }

    mutating func record(word: String, seconds: Double, mistakes m: Int) {
        wordsCompleted += 1
        totalKeystrokes += word.count
        mistakes += m
        totalTypingSeconds += seconds
        if let f = fastestWordSeconds { fastestWordSeconds = min(f, seconds) }
        else { fastestWordSeconds = seconds }
    }
}
