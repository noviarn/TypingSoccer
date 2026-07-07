//
//  GameKitMatchManager.swift
//  TypingSoccer
//
//  Multiplayer transport using GameKit real-time matches (GKMatch) —
//  2v2 across 4 Macs over Game Center, replacing MultipeerConnectivity.
//
//  Each team has TWO humans:
//    • the FIELD player  — controls the three outfielders (typing duels,
//      passes, and picking which defender chases the ball carrier)
//    • the KEEPER player — controls the goalkeeper (typing shot/penalty
//      duels in goal, and choosing who to pass to after a save/free kick)
//
//  Sync model (unchanged from the Multipeer version): one machine is
//  AUTHORITATIVE HOST — it picks every duel word, resolves every duel and
//  decides possession, broadcasting each as a PeerMessage. GKMatch has no
//  built-in host, so the host is ELECTED deterministically: the connected
//  player with the lowest gamePlayerID. The host always takes seat
//  `homeField`; the three others claim the remaining seats in the lobby.
//
//  If a player QUITS mid-match, the match does NOT end: the host promotes
//  that seat to AI control (see GameScene.seatDidDisconnect). Only the
//  host leaving ends the match, since the host owns the simulation.
//
//  Wire convention: "home" in any message payload means the HOST's team.
//

import Foundation
import GameKit

/// One of the four chairs in a 2v2 match. Raw values go over the wire.
/// `homeField` is always the (elected) host.
enum PeerSeat: Int, Codable, CaseIterable {
    case homeField = 0      // host — home team's 3 outfielders
    case homeKeeper = 1     // home team's goalkeeper
    case awayField = 2      // away team's 3 outfielders (picks the away WC team)
    case awayKeeper = 3     // away team's goalkeeper

    /// On the HOST's team? ("home" in wire terms.)
    var isHome: Bool { self == .homeField || self == .homeKeeper }
    /// Controls the three outfielders (vs the goalkeeper)?
    var isField: Bool { self == .homeField || self == .awayField }

    var roleLabel: String { isField ? "FIELD" : "KEEPER" }
}

/// Identifies one player node on the wire. `home` = the HOST's team.
/// `slot` 0…2 = outfield lanes (top/middle/bottom), 3 = goalkeeper.
struct PeerPlayerRef: Codable {
    let home: Bool
    let slot: Int
}

/// Messages exchanged between the four machines. Coordinates (x / y /
/// lineX) are in the HOST's scene frame; away-team machines mirror x.
enum PeerMessage: Codable {

    // MARK: Lobby (host assigns seats; match starts when all 4 are filled)
    /// Host → all: which seats are taken (parallel arrays), plus team picks.
    case lobbyState(filledSeats: [Int], names: [String], hostTeamID: String, awayTeamID: String?)
    /// Joiner → host: claim a seat. teamID/formation only matter for awayField.
    case requestSeat(seat: Int, teamID: String, formation: Int)
    /// Host → one joiner: your claim succeeded / failed.
    case seatAssigned(seat: Int)
    case seatDenied(seat: Int)
    /// Host → all: everyone is seated — launch the match.
    case startMatch(homeTeamID: String, awayTeamID: String,
                    homeFormation: Int, awayFormation: Int)

    // MARK: Inputs (joiners + host, tagged with the sender's seat)
    case formationUpdate(homeTeam: Bool, formation: Int)   // field players only
    case typingProgress(seat: Int, count: Int)
    case wordCompleted(seat: Int, mistyped: Bool)
    case shotMistyped(seat: Int)                           // open-play shot fluffed
    case passRequest(seat: Int, toLane: Int)               // carrier's controller asks host
    case chaseRequest(seat: Int, lane: Int)                // defending field player picks the presser

    // MARK: Authoritative events (host only)
    case duelStart(kind: Int, word: String, attacker: PeerPlayerRef?, defender: PeerPlayerRef?)
    case duelResult(winnerHome: Bool, shotOutcome: Int?)   // outcome: 0 goal, 1 wide, 2 saved
    case possession(player: PeerPlayerRef, x: Double, y: Double, mustPass: Bool)
    case passStarted(target: PeerPlayerRef, offside: Bool, lineX: Double)
    case chaseState(homeTeam: Bool, lane: Int)             // committed chase assignment
    case addedTime
    case breakNow(kind: Int, shootoutGoalRight: Bool?)     // 0 HT, 1 ET, 2 ET-HT, 3 pens, 4 full time
    /// Host → all: a seat's human left mid-match; the AI now runs it.
    case seatWentAI(seat: Int)
}

protocol MatchManagerDelegate: AnyObject {
    /// Matchmaking progress: player count changed / match delivered.
    func matchStateChanged()
    /// All four players connected — the lobby can start seat claiming.
    func matchReady()
    /// Matchmaking failed or was cancelled by the system.
    func matchFailed(error: Error?)
    /// A connected player dropped. `wasHost` decides AI-takeover vs abort.
    func playerLeft(playerID: String, wasHost: Bool)
    func didReceive(_ message: PeerMessage, fromPlayerID: String)
}

final class GameKitMatchManager: NSObject {

    /// A 2v2 match is exactly four humans. (Drop to 2 for local testing.)
    static let requiredPlayers = 4

    weak var delegate: MatchManagerDelegate?

    private(set) var match: GKMatch?
    private(set) var isMatchmaking = false
    /// Fixed at election time so a later disconnect can't re-elect a new
    /// host mid-match (the sim lives on the original host).
    private(set) var hostPlayerID: String?

    var localPlayerID: String { GKLocalPlayer.local.gamePlayerID }
    var localDisplayName: String { GKLocalPlayer.local.displayName }
    var isHost: Bool { hostPlayerID == localPlayerID }

    /// Everyone in the match including the local player.
    var allPlayerIDs: [String] {
        guard let match else { return [localPlayerID] }
        return match.players.map { $0.gamePlayerID } + [localPlayerID]
    }
    var connectedRemoteCount: Int { match?.players.count ?? 0 }

    func displayName(for playerID: String) -> String {
        if playerID == localPlayerID { return localDisplayName }
        return match?.players.first { $0.gamePlayerID == playerID }?.displayName ?? "Player"
    }

    // MARK: Matchmaking

    /// Start automatching a 4-player game. The lobby UI reflects progress
    /// via `matchStateChanged`; once all players connect, `matchReady`.
    func findMatch() {
        stop()
        guard GKLocalPlayer.local.isAuthenticated else {
            delegate?.matchFailed(error: nil)
            return
        }
        isMatchmaking = true
        let request = GKMatchRequest()
        request.minPlayers = Self.requiredPlayers
        request.maxPlayers = Self.requiredPlayers
        request.playerGroup = 2026        // typing-soccer 2v2 pool
        GKMatchmaker.shared().findMatch(for: request) { [weak self] match, error in
            DispatchQueue.main.async {
                guard let self, self.isMatchmaking else { return }
                if let error {
                    self.isMatchmaking = false
                    self.delegate?.matchFailed(error: error)
                    return
                }
                guard let match else { return }
                self.match = match
                match.delegate = self
                self.delegate?.matchStateChanged()
                self.electHostIfReady()
            }
        }
    }

    func stop() {
        if isMatchmaking { GKMatchmaker.shared().cancel() }
        isMatchmaking = false
        match?.delegate = nil
        match?.disconnect()
        match = nil
        hostPlayerID = nil
    }

    /// All expected players present → elect the host (lowest gamePlayerID,
    /// identical on every machine) and tell the delegate the table is set.
    private func electHostIfReady() {
        guard let match, match.expectedPlayerCount == 0, hostPlayerID == nil else { return }
        hostPlayerID = allPlayerIDs.sorted().first
        isMatchmaking = false
        delegate?.matchReady()
    }

    // MARK: Sending

    /// Broadcast to every player, or to specific `playerIDs` when given.
    func send(_ message: PeerMessage, to playerIDs: [String]? = nil) {
        guard let match else { return }
        // Live typing progress is cosmetic — send it unreliably.
        let mode: GKMatch.SendDataMode
        if case .typingProgress = message { mode = .unreliable } else { mode = .reliable }
        do {
            let data = try JSONEncoder().encode(message)
            if let playerIDs {
                let targets = match.players.filter { playerIDs.contains($0.gamePlayerID) }
                guard !targets.isEmpty else { return }
                try match.send(data, to: targets, dataMode: mode)
            } else {
                try match.sendData(toAllPlayers: data, with: mode)
            }
        } catch {
            NSLog("GameKit send failed: \(error)")
        }
    }

    /// Convenience: send only to the elected host.
    func sendToHost(_ message: PeerMessage) {
        guard let hostPlayerID, hostPlayerID != localPlayerID else { return }
        send(message, to: [hostPlayerID])
    }
}

// MARK: - GKMatchDelegate

extension GameKitMatchManager: GKMatchDelegate {

    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        guard let message = try? JSONDecoder().decode(PeerMessage.self, from: data) else { return }
        DispatchQueue.main.async {
            self.delegate?.didReceive(message, fromPlayerID: player.gamePlayerID)
        }
    }

    func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.delegate?.matchStateChanged()
                self.electHostIfReady()
            case .disconnected:
                self.delegate?.playerLeft(playerID: player.gamePlayerID,
                                          wasHost: player.gamePlayerID == self.hostPlayerID)
                self.delegate?.matchStateChanged()
            default:
                break
            }
        }
    }

    func match(_ match: GKMatch, didFailWithError error: Error?) {
        DispatchQueue.main.async {
            self.delegate?.matchFailed(error: error)
        }
    }
}
