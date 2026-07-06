//
//  MatchFeedback.swift
//  TypingSoccer
//
//  Post-match coaching feedback generated on-device with Apple's
//  Foundation Models framework, using the player's real typing stats.
//  Falls back to a hand-written summary when the model isn't available
//  (older OS, unsupported hardware, or model still downloading).
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum MatchFeedback {

    /// Build a short, encouraging coach's note from the match stats.
    static func generate(stats: PlayerStats, homeScore: Int, awayScore: Int) async -> String {

        let facts = summaryFacts(stats: stats, homeScore: homeScore, awayScore: awayScore)

        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                do {
                    let session = LanguageModelSession(instructions: """
                    You are an upbeat esports typing coach for a soccer typing game. \
                    Given the player's match stats, write 2-3 short sentences of feedback: \
                    celebrate a strength, point out one thing to improve, and end with encouragement. \
                    Keep it under 60 words. Do not use bullet points.
                    """)
                    let prompt = "Match stats:\n\(facts)"
                    let response = try await session.respond(to: prompt)
                    return response.content
                } catch {
                    NSLog("FoundationModels error: \(error.localizedDescription)")
                    return fallback(stats: stats, homeScore: homeScore, awayScore: awayScore)
                }
            default:
                // .unavailable(...) — model not ready on this device.
                return fallback(stats: stats, homeScore: homeScore, awayScore: awayScore)
            }
        } else {
            return fallback(stats: stats, homeScore: homeScore, awayScore: awayScore)
        }
        #else
        return fallback(stats: stats, homeScore: homeScore, awayScore: awayScore)
        #endif
    }

    private static func summaryFacts(stats: PlayerStats, homeScore: Int, awayScore: Int) -> String {
        let wpm = Int(stats.averageWPM.rounded())
        let acc = Int((stats.accuracy * 100).rounded())
        let fastest = stats.fastestWordSeconds.map { String(format: "%.1fs", $0) } ?? "n/a"
        return """
        Result: \(homeScore)-\(awayScore) (\(homeScore >= awayScore ? "win/draw" : "loss"))
        Words typed: \(stats.wordsCompleted)
        Average WPM: \(wpm)
        Accuracy: \(acc)%
        Mistakes: \(stats.mistakes)
        Duels won: \(stats.duelsWon), lost: \(stats.duelsLost)
        Goals: \(stats.goals)
        Fastest word: \(fastest)
        """
    }

    /// Deterministic fallback so the end screen always says something useful.
    private static func fallback(stats: PlayerStats, homeScore: Int, awayScore: Int) -> String {
        let wpm = Int(stats.averageWPM.rounded())
        let acc = Int((stats.accuracy * 100).rounded())
        let outcome = homeScore > awayScore ? "Great win" : (homeScore == awayScore ? "Hard-fought draw" : "Tough loss")
        let strength = acc >= 90 ? "Your accuracy was excellent" : "You kept the ball moving"
        let improve = wpm < 40 ? "work on raw speed to win more duels" : "trim mistakes to close out shots"
        return "\(outcome) at \(homeScore)-\(awayScore). \(strength) (\(wpm) WPM, \(acc)% accurate). Next match, \(improve). Keep at it!"
    }
}
