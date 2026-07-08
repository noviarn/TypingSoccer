//
//  ProfileView.swift
//  TypingSoccer
//
//  Player profile: identity card (name, level, XP), career stats across
//  single player AND multiplayer, recent match history, achievements.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var coordinator: GameCoordinator
    @ObservedObject private var gameCenter = GameCenterManager.shared
    @ObservedObject private var store = PlayerProfileStore.shared

    private let panelColor = Color(red: 109/255, green: 112/255, blue: 116/255).opacity(0.92)

    var body: some View {
        VStack(spacing: 16) {
            HStack { BackButton(); Spacer() }
                .padding(.horizontal, 20)
                .padding(.top, 14)

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    identityCard
                    statsCard
                }
                VStack(spacing: 16) {
                    historyCard
                    achievementsCard
                }
            }
            .padding(.horizontal, 26)

            Spacer(minLength: 10)
        }
    }

    // MARK: Identity (name, level, XP)

    private var identityCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color(white: 0.85))

            Text(gameCenter.playerName)
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .foregroundColor(.white)

            // Level + XP bar.
            VStack(spacing: 4) {
                HStack {
                    Text("\(L("profile.level")) \(store.profile.level)")
                    Spacer()
                    Text("\(store.profile.xpIntoLevel) / 100")
                }
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.7))
                        Capsule()
                            .fill(Color(red: 1, green: 0.8, blue: 0.2))
                            .frame(width: geo.size.width * CGFloat(store.profile.xpIntoLevel) / 100)
                    }
                }
                .frame(height: 10)
            }
            .padding(.horizontal, 8)
        }
        .padding(18)
        .frame(width: 300)
        .background(panelColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Career stats

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("profile.stats"))
                .font(.system(size: 18, weight: .heavy, design: .monospaced))
                .foregroundColor(.white)

            statRow(L("profile.matches"), "\(store.profile.matchesPlayed)")
            statRow(L("profile.winRate"), pct(store.profile.winRate))
            statRow(L("profile.accuracy"), pct(store.profile.accuracy))
            statRow(L("profile.goals"), "\(store.profile.totalGoals)")
            statRow(L("profile.streak"), "\(store.profile.currentStreak)")
        }
        .padding(18)
        .frame(width: 300, alignment: .leading)
        .background(panelColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(.white)
        }
    }

    private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    // MARK: Match history

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("profile.history"))
                .font(.system(size: 18, weight: .heavy, design: .monospaced))
                .foregroundColor(.white)

            if store.profile.history.isEmpty {
                Text(L("profile.noMatches"))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.vertical, 8)
            } else {
                ForEach(store.profile.history.prefix(5)) { match in
                    HStack {
                        Text(flag(match.myTeamID))
                        Text("VS")
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                        Text(flag(match.rivalTeamID))
                        if match.isMultiplayer {
                            Text("2v2")
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundColor(.cyan.opacity(0.8))
                        }
                        Spacer()
                        Text("\(match.myScore) – \(match.rivalScore)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(match.won ? .green : (match.drawn ? .white : .red))
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 430, alignment: .leading)
        .background(panelColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func flag(_ teamID: String) -> String {
        WorldCupTeams.team(named: teamID)?.flag ?? "🏳️"
    }

    // MARK: Achievements

    private var achievementsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("profile.achievements"))
                .font(.system(size: 18, weight: .heavy, design: .monospaced))
                .foregroundColor(.white)

            let columns = [GridItem(.fixed(196), spacing: 14), GridItem(.fixed(196), spacing: 14)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(Achievement.allCases) { a in
                    badge(a, unlocked: store.isUnlocked(a))
                }
            }
        }
        .padding(18)
        .frame(width: 430, alignment: .leading)
        .background(panelColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func badge(_ a: Achievement, unlocked: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: a.icon)
                .font(.system(size: 13, weight: .bold))
            Text(a.title)
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundColor(unlocked ? Color(red: 0.45, green: 0.28, blue: 0.05) : .white.opacity(0.35))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(width: 196, alignment: .leading)
        .background(unlocked
                    ? Color(red: 238/255, green: 170/255, blue: 82/255)
                    : Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
