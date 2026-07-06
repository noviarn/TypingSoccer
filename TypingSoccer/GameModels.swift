//
//  GameModels.swift
//  TypingSoccer
//
//  Core value types shared across the game.
//

import Foundation
import CoreGraphics

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
    case strategyPick       // pre-match window to choose the starting formation
    case countdown          // whistle + 3-2-1
    case kickoff            // first word decides who gets the ball
    case running            // a carrier is advancing, defenders closing
    case duel(DuelKind)     // a word is being typed to resolve a contest
    case goalScored(Team)   // brief celebration / reset
    case halftime           // break at 45'; teams switch ends
    case finished           // time up
}

/// What a typing duel is resolving.
enum DuelKind: Equatable {
    case kickoff            // possession from the opening whistle
    case interception       // defender caught the carrier mid-field
    case shot               // carrier vs goalkeeper at the box
}

/// Outfield shape, expressed as depth bands (back → forward). Selected by
/// the player and applied at every reset (kickoff, half time, after a goal).
/// Numbers map to keyboard keys 1…5.
enum Formation: Int, CaseIterable, Equatable {
    case oneTwo = 1     // 1-2   : 1 back, 2 forward  (default)
    case twoOne         // 2-1   : 2 back, 1 forward
    case threeZero      // 3-0   : all three back
    case zeroThree      // 0-3   : all three forward
    case oneOneOne      // 1-1-1 : one forward, one middle, one back

    var label: String {
        switch self {
        case .oneTwo: return "1-2"
        case .twoOne: return "2-1"
        case .threeZero: return "3-0"
        case .zeroThree: return "0-3"
        case .oneOneOne: return "1-1-1"
        }
    }

    /// Depth as a fraction of the field width from a team's OWN goal line
    /// (small = deep/back, large = advanced/forward), per lane.
    func depthFraction(for lane: Lane) -> CGFloat {
        let back: CGFloat = 0.15, mid: CGFloat = 0.28, fwd: CGFloat = 0.42
        switch self {
        case .oneTwo:    return lane == .middle ? back : fwd   // wings up, centre deep
        case .twoOne:    return lane == .middle ? fwd : back   // wings deep, centre up
        case .threeZero: return back
        case .zeroThree: return fwd
        case .oneOneOne:
            switch lane {
            case .top:    return fwd
            case .middle: return mid
            case .bottom: return back
            }
        }
    }
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
