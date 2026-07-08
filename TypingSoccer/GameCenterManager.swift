//
//  GameCenterManager.swift
//  TypingSoccer
//
//  GameKit wrapper: authenticates the local player, submits the six
//  multiplayer leaderboard stats, and fetches + merges the boards for the
//  Leaderboard screen.
//
//  The six leaderboard IDs below must be created in App Store Connect
//  (Game Center → Leaderboards, "Classic", best-score-wins, integer).
//  Percent stats are submitted as basis points ×100 (98.2% → 9820) so the
//  integer boards keep two decimals.
//

import GameKit

/// One merged row for the Leaderboard screen.
struct LeaderboardRow: Identifiable {
    let id: String              // gamePlayerID
    let displayName: String
    let isLocalPlayer: Bool
    var rank: Int               // rank on the BEST SCORE board (the anchor)
    var bestScore: Int = 0
    var bestGoal: Int = 0
    var accuracyBP: Int = 0     // basis points: 9820 = 98.20%
    var shotAccuracyBP: Int = 0
    var bestSaves: Int = 0
    var savePctBP: Int = 0
}

final class GameCenterManager: ObservableObject {

    static let shared = GameCenterManager()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var playerName = "Guest"

    // MARK: Leaderboard IDs (configure these in App Store Connect)
    enum Board: String, CaseIterable {
        case bestScore   = "com.typingsoccer.bestscore"     // anchor board (ranks)
        case bestGoal    = "com.typingsoccer.bestgoal"
        case accuracy    = "com.typingsoccer.accuracy"      // basis points
        case shotAccuracy = "com.typingsoccer.shotaccuracy" // basis points
        case bestSaves   = "com.typingsoccer.bestsaves"
        case savePct     = "com.typingsoccer.savepct"       // basis points
    }

    /// Kick off Game Center sign-in. On macOS the auth view controller is
    /// presented by the system automatically when needed.
    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] _, error in
            DispatchQueue.main.async {
                self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                self?.playerName = GKLocalPlayer.local.isAuthenticated
                    ? GKLocalPlayer.local.displayName : "Guest"
                if let error { NSLog("GameKit auth error: \(error.localizedDescription)") }
            }
        }
    }

    // MARK: Submitting (multiplayer matches only)

    /// Push the local player's multiplayer bests to all six boards. Boards
    /// configured as "best score wins" keep the max automatically.
    func submitMultiplayerStats(from profile: PlayerProfile) {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        let scores: [(Board, Int)] = [
            (.bestScore, profile.mpBestScore),
            (.bestGoal, profile.mpBestGoals),
            (.accuracy, Int((profile.mpAccuracy * 10000).rounded())),
            (.shotAccuracy, Int((profile.mpShotAccuracy * 10000).rounded())),
            (.bestSaves, profile.mpBestSaves),
            (.savePct, Int((profile.mpSavePercentage * 10000).rounded())),
        ]
        for (board, value) in scores {
            GKLeaderboard.submitScore(value, context: 0, player: GKLocalPlayer.local,
                                      leaderboardIDs: [board.rawValue]) { error in
                if let error { NSLog("GameKit submit \(board.rawValue): \(error.localizedDescription)") }
            }
        }
    }

    // MARK: Fetching (Leaderboard screen)

    /// Load the top of every board and merge them into one row per player,
    /// ranked by the BEST SCORE board.
    func loadLeaderboard(topN: Int = 25) async throws -> [LeaderboardRow] {
        guard GKLocalPlayer.local.isAuthenticated else { return [] }
        let ids = Board.allCases.map(\.rawValue)
        let boards = try await GKLeaderboard.loadLeaderboards(IDs: ids)
        let localID = GKLocalPlayer.local.gamePlayerID

        var rows: [String: LeaderboardRow] = [:]

        for board in boards {
            guard let kind = Board(rawValue: board.baseLeaderboardID) else { continue }
            let (_, entries, _) = try await board.loadEntries(
                for: .global, timeScope: .allTime, range: NSRange(location: 1, length: topN))
            for entry in entries {
                let pid = entry.player.gamePlayerID
                var row = rows[pid] ?? LeaderboardRow(
                    id: pid,
                    displayName: entry.player.displayName,
                    isLocalPlayer: pid == localID,
                    rank: Int.max)
                switch kind {
                case .bestScore:
                    row.bestScore = entry.score
                    row.rank = entry.rank
                case .bestGoal: row.bestGoal = entry.score
                case .accuracy: row.accuracyBP = entry.score
                case .shotAccuracy: row.shotAccuracyBP = entry.score
                case .bestSaves: row.bestSaves = entry.score
                case .savePct: row.savePctBP = entry.score
                }
                rows[pid] = row
            }
        }

        // Players present on secondary boards but missing from BEST SCORE
        // sink to the bottom, ordered by their best score.
        return rows.values.sorted {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            return $0.bestScore > $1.bestScore
        }
    }
}
