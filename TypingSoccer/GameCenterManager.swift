//
//  GameCenterManager.swift
//  TypingSoccer
//
//  Thin GameKit wrapper: authenticates the local player and reports a
//  simple "typing WPM" score to a leaderboard. Real leaderboard IDs are
//  configured in App Store Connect; the constant below is a placeholder.
//

import GameKit

final class GameCenterManager: ObservableObject {

    static let shared = GameCenterManager()

    @Published private(set) var isAuthenticated = false
    private let leaderboardID = "com.typingsoccer.wpm"   // placeholder

    /// Kick off Game Center sign-in. On macOS the auth view controller is
    /// presented by the system automatically when needed.
    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] _, error in
            DispatchQueue.main.async {
                self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                if let error { NSLog("GameKit auth error: \(error.localizedDescription)") }
            }
        }
    }

    /// Report an integer score (e.g. average WPM) to the leaderboard.
    func submit(score: Int) {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
                                  leaderboardIDs: [leaderboardID]) { error in
            if let error { NSLog("GameKit submit error: \(error.localizedDescription)") }
        }
    }
}
