//
//  LeaderboardView.swift
//  TypingSoccer
//
//  Game Center-backed leaderboards: top-3 podium + a table with the six
//  multiplayer stat columns (Best Goal, Accuracy, Best Score, Shot
//  Accuracy, Best Saves, Save %), ranked by Best Score.
//

import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject var coordinator: GameCoordinator
    @ObservedObject private var gameCenter = GameCenterManager.shared

    @State private var rows: [LeaderboardRow] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Text(L("leaderboard.title"))
                    .font(.system(size: 30, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(red: 238/255, green: 170/255, blue: 82/255))
                HStack { BackButton(); Spacer() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Text(L("leaderboard.mpOnly"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))

            if isLoading {
                Spacer()
                ProgressView(L("leaderboard.loading"))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
            } else if !gameCenter.isAuthenticated {
                Spacer()
                message(L("leaderboard.notAuth"))
                Spacer()
            } else if loadFailed {
                Spacer()
                message(L("leaderboard.error"))
                Spacer()
            } else if rows.isEmpty {
                Spacer()
                message(L("leaderboard.empty"))
                Spacer()
            } else {
                if rows.count >= 1 { podium }
                table
            }
        }
        .task { await load() }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, design: .monospaced))
            .foregroundColor(.white.opacity(0.7))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        do {
            rows = try await GameCenterManager.shared.loadLeaderboard()
        } catch {
            NSLog("Leaderboard load failed: \(error.localizedDescription)")
            loadFailed = true
        }
        isLoading = false
    }

    // MARK: Podium (top 3)

    private var podium: some View {
        let first = rows.count > 0 ? rows[0] : nil
        let second = rows.count > 1 ? rows[1] : nil
        let third = rows.count > 2 ? rows[2] : nil

        return HStack(alignment: .bottom, spacing: 34) {
            podiumSpot(second, place: 2, color: Color(white: 0.75), height: 54)
            podiumSpot(first, place: 1, color: Color(red: 1, green: 0.78, blue: 0.2), height: 80)
            podiumSpot(third, place: 3, color: Color(red: 0.8, green: 0.5, blue: 0.2), height: 40)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func podiumSpot(_ row: LeaderboardRow?, place: Int, color: Color, height: CGFloat) -> some View {
        if let row {
            VStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: place == 1 ? 64 : 50, height: place == 1 ? 64 : 50)
                    .overlay(
                        Text(initials(row.displayName))
                            .font(.system(size: place == 1 ? 20 : 15, weight: .heavy, design: .monospaced))
                            .foregroundColor(.black.opacity(0.7))
                    )
                Text(row.isLocalPlayer ? L("leaderboard.you") : row.displayName)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Rectangle()
                    .fill(color)
                    .frame(width: 92, height: height)
                    .overlay(
                        Text("\(place)")
                            .font(.system(size: 20, weight: .heavy, design: .monospaced))
                            .foregroundColor(.black.opacity(0.55))
                    )
            }
            .frame(width: 130)
        } else {
            Color.clear.frame(width: 130, height: 10)
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    // MARK: Table (rank 4+, plus the local player wherever they are)

    private var table: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(rows.dropFirst(3))) { row in
                        rowView(row)
                    }
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 20)
    }

    private let colWidths: (rank: CGFloat, player: CGFloat, stat: CGFloat) = (60, 170, 92)

    private var header: some View {
        HStack(spacing: 4) {
            Text(L("leaderboard.rank")).frame(width: colWidths.rank, alignment: .leading)
            Text(L("leaderboard.player")).frame(width: colWidths.player, alignment: .leading)
            Group {
                Text(L("leaderboard.bestGoal"))
                Text(L("leaderboard.accuracy"))
                Text(L("leaderboard.bestScore"))
                Text(L("leaderboard.shotAcc"))
                Text(L("leaderboard.bestSaves"))
                Text(L("leaderboard.savePct"))
            }
            .frame(width: colWidths.stat, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .heavy, design: .monospaced))
        .foregroundColor(.white)
        .padding(.vertical, 8)
    }

    private func rowView(_ row: LeaderboardRow) -> some View {
        HStack(spacing: 4) {
            Text(row.rank == Int.max ? "—" : "\(row.rank)")
                .frame(width: colWidths.rank, alignment: .leading)
                .foregroundColor(.white.opacity(0.85))
            Text(row.isLocalPlayer ? L("leaderboard.you") : row.displayName)
                .frame(width: colWidths.player, alignment: .leading)
                .foregroundColor(row.isLocalPlayer ? .yellow : .white)
                .lineLimit(1)
            Group {
                Text("\(row.bestGoal)").foregroundColor(.white)
                Text(pct(row.accuracyBP)).foregroundColor(.green)
                Text(formatted(row.bestScore)).foregroundColor(.yellow)
                Text(pct(row.shotAccuracyBP)).foregroundColor(.green)
                Text("\(row.bestSaves)").foregroundColor(.white)
                Text(pct(row.savePctBP)).foregroundColor(.green)
            }
            .frame(width: colWidths.stat, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .bold, design: .monospaced))
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .background(row.isLocalPlayer ? Color.yellow.opacity(0.12) : Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func pct(_ basisPoints: Int) -> String {
        String(format: "%.0f%%", Double(basisPoints) / 100.0)
    }

    private func formatted(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
