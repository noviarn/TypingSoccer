//
//  PlayerProfileStore.swift
//  TypingSoccer
//
//  Persistent player profile: career aggregates across single player AND
//  multiplayer (for the Profile screen), match history, XP/level and
//  achievements. Multiplayer-only bests are kept separately because only
//  those feed the Game Center leaderboards.
//
//  Stored as one JSON blob in UserDefaults — small, atomic, no files.
//

import Foundation

/// One finished match, newest first in `history`.
struct MatchRecord: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let isMultiplayer: Bool
    let myTeamID: String
    let rivalTeamID: String
    let myScore: Int
    let rivalScore: Int
    let myPens: Int?
    let rivalPens: Int?
    let stats: PlayerStats

    var won: Bool {
        if myScore != rivalScore { return myScore > rivalScore }
        if let mp = myPens, let rp = rivalPens { return mp > rp }
        return false
    }
    var drawn: Bool { myScore == rivalScore && myPens == nil }
}

/// Achievement definitions shown on the Profile screen.
enum Achievement: String, CaseIterable, Identifiable {
    case speedGod    // ≥ 80 average WPM in one match
    case combo25     // 25 correct keystrokes in a row
    case goalShooter // 25 career goals
    case stealthType // a match with 10+ words and zero mistakes

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .speedGod: return "bolt.fill"
        case .combo25: return "target"
        case .goalShooter: return "flag.fill"
        case .stealthType: return "moon.fill"
        }
    }
    var title: String {
        switch self {
        case .speedGod: return "Speed God"
        case .combo25: return "x25 Combo"
        case .goalShooter: return "Goal Shooter"
        case .stealthType: return "Stealth Type"
        }
    }
}

/// Everything persisted for the local player.
struct PlayerProfile: Codable {
    var xp = 0
    var history: [MatchRecord] = []

    // Career aggregates (both modes) — Profile screen.
    var matchesPlayed = 0
    var wins = 0
    var totalGoals = 0
    var totalKeystrokes = 0
    var totalMistakes = 0
    var currentStreak = 0        // consecutive wins; reset on loss/draw

    // Multiplayer-only bests — Game Center leaderboard columns.
    var mpBestGoals = 0          // most goals in one match
    var mpBestScore = 0          // best single-game score
    var mpBestSaves = 0          // most saves in one match
    var mpKeystrokes = 0         // for overall MP typing accuracy
    var mpMistakes = 0
    var mpShotsTaken = 0         // penalty-area shots only
    var mpShotsScored = 0
    var mpSavesFaced = 0         // final battles played as keeper
    var mpSavesMade = 0

    var unlockedAchievements: Set<String> = []

    var level: Int { xp / 100 + 1 }
    var xpIntoLevel: Int { xp % 100 }
    var winRate: Double { matchesPlayed > 0 ? Double(wins) / Double(matchesPlayed) : 0 }
    var accuracy: Double {
        totalKeystrokes > 0
            ? Double(totalKeystrokes - totalMistakes) / Double(totalKeystrokes) : 1
    }
    var mpAccuracy: Double {
        mpKeystrokes > 0 ? Double(mpKeystrokes - mpMistakes) / Double(mpKeystrokes) : 0
    }
    var mpShotAccuracy: Double {
        mpShotsTaken > 0 ? Double(mpShotsScored) / Double(mpShotsTaken) : 0
    }
    var mpSavePercentage: Double {
        mpSavesFaced > 0 ? Double(mpSavesMade) / Double(mpSavesFaced) : 0
    }
}

@MainActor
final class PlayerProfileStore: ObservableObject {

    static let shared = PlayerProfileStore()

    @Published private(set) var profile: PlayerProfile

    private static let key = "player.profile.v1"
    private static let historyCap = 20

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(PlayerProfile.self, from: data) {
            profile = saved
        } else {
            profile = PlayerProfile()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// Book a finished match into the profile. Returns the newly unlocked
    /// achievements (for a toast, if the UI wants one).
    @discardableResult
    func record(_ match: MatchRecord) -> [Achievement] {
        profile.history.insert(match, at: 0)
        if profile.history.count > Self.historyCap {
            profile.history.removeLast(profile.history.count - Self.historyCap)
        }

        profile.matchesPlayed += 1
        profile.totalGoals += match.stats.goals
        profile.totalKeystrokes += match.stats.totalKeystrokes
        profile.totalMistakes += match.stats.mistakes
        if match.won {
            profile.wins += 1
            profile.currentStreak += 1
        } else {
            profile.currentStreak = 0
        }

        // XP: participation + goals + duels + win bonus.
        profile.xp += 20 + match.stats.goals * 5 + match.stats.duelsWon * 2 + (match.won ? 30 : 0)

        if match.isMultiplayer {
            let s = match.stats
            profile.mpBestGoals = max(profile.mpBestGoals, s.goals)
            profile.mpBestScore = max(profile.mpBestScore, s.matchScore)
            profile.mpBestSaves = max(profile.mpBestSaves, s.savesMade)
            profile.mpKeystrokes += s.totalKeystrokes
            profile.mpMistakes += s.mistakes
            profile.mpShotsTaken += s.shotsTaken
            profile.mpShotsScored += s.shotsScored
            profile.mpSavesFaced += s.savesFaced
            profile.mpSavesMade += s.savesMade
        }

        let newOnes = evaluateAchievements(after: match)
        save()
        return newOnes
    }

    private func evaluateAchievements(after match: MatchRecord) -> [Achievement] {
        var unlocked: [Achievement] = []
        func unlock(_ a: Achievement, when condition: Bool) {
            guard condition, !profile.unlockedAchievements.contains(a.rawValue) else { return }
            profile.unlockedAchievements.insert(a.rawValue)
            unlocked.append(a)
        }
        unlock(.speedGod, when: match.stats.averageWPM >= 80)
        unlock(.combo25, when: match.stats.bestCombo >= 25)
        unlock(.goalShooter, when: profile.totalGoals >= 25)
        unlock(.stealthType, when: match.stats.wordsCompleted >= 10 && match.stats.mistakes == 0)
        return unlocked
    }

    func isUnlocked(_ a: Achievement) -> Bool {
        profile.unlockedAchievements.contains(a.rawValue)
    }
}
