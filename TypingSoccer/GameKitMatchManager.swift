//
//  GameKitMatchManager.swift
//  TypingSoccer
//
//  Multiplayer transport using GameKit real-time matches (GKMatch).
//  Supports two modes:
//    • 1v1 — two humans, one per team; each controls their WHOLE team
//      (the three outfielders AND the goalkeeper).
//    • 2v2 — four humans; each team is a FIELD player (three outfielders)
//      and a KEEPER player (the goalkeeper).
//
//  Flow:
//    1. LOBBY / PARTY. The player picks their country in the lobby. In 2v2
//       they gather their teammate first: the room MASTER taps "Generate
//       Key" to mint a short code; the teammate types that code to join the
//       same private room (a GKMatch scoped to a deterministic playerGroup
//       derived from the code). 1v1 needs no party.
//    2. BATTLE. Tapping "Battle" starts balanced matchmaking for the
//       opposing side — automatch fills the remaining seats (1 opponent for
//       1v1, 2 for 2v2). A 2v2 party fills its opponents with
//       GKMatchmaker.addPlayers(to:); a solo/1v1 player uses findMatch.
//
//  Sync model: one machine is the AUTHORITATIVE HOST — it picks every duel
//  word, resolves every duel and decides possession, broadcasting each as a
//  PeerMessage. The host is ELECTED deterministically once the full table is
//  present: the connected player with the lowest gamePlayerID. The host owns
//  seat `homeField`; the coordinator groups the remaining players so the
//  host's real teammate stays on the host's ("home") side.
//
//  If a player QUITS mid-match, the match does NOT end: the host promotes
//  that seat to AI control. Only the host leaving ends the match.
//
//  Wire convention: "home" in any message payload means the HOST's team.
//

import Foundation
import GameKit

/// Multiplayer format. Raw counts drive matchmaking and seat layout.
enum MPMode: Int, Codable {
    case oneVsOne = 1
    case twoVsTwo = 2

    /// Total humans in a full match.
    var totalPlayers: Int { self == .oneVsOne ? 2 : 4 }
    /// Humans per team.
    var teamSize: Int { self == .oneVsOne ? 1 : 2 }
    /// Automatch pool ID (keeps the two formats from cross-matching).
    var poolGroup: Int { self == .oneVsOne ? 1001 : 1002 }
    /// Does this format gather a teammate via a room key first?
    var usesParty: Bool { self == .twoVsTwo }
}

/// One chair in a match. Raw values go over the wire. `homeField` is always
/// the (elected) host. In 1v1 only `homeField` / `awayField` are used and the
/// occupant controls the whole team.
enum PeerSeat: Int, Codable, CaseIterable {
    case homeField = 0      // host — home team's outfielders (+ keeper in 1v1)
    case homeKeeper = 1     // home team's goalkeeper (2v2 only)
    case awayField = 2      // away team's outfielders (+ keeper in 1v1)
    case awayKeeper = 3     // away team's goalkeeper (2v2 only)

    /// On the HOST's team? ("home" in wire terms.)
    var isHome: Bool { self == .homeField || self == .awayField }
    /// Controls the three outfielders (in 2v2, as opposed to the goalkeeper)?
    var isField: Bool { self == .homeField || self == .awayField }

    var roleLabel: String { isField ? "FIELD" : "KEEPER" }

    /// The two seats belonging to a side, in field-then-keeper order.
    static func seats(home: Bool) -> [PeerSeat] {
        home ? [.homeField, .homeKeeper] : [.awayField, .awayKeeper]
    }
}

/// Identifies one player node on the wire. `home` = the HOST's team.
/// `slot` 0…2 = outfield lanes (top/middle/bottom), 3 = goalkeeper.
struct PeerPlayerRef: Codable {
    let home: Bool
    let slot: Int
}

/// Messages exchanged between the machines. Coordinates (x / y / lineX) are in
/// the HOST's scene frame; away-team machines mirror x.
enum PeerMessage: Codable {

    // MARK: Lobby / seat assignment
    /// Every player → all, once the full table connects: my country pick and
    /// my party room key (nil if I searched solo). The host groups by key so
    /// teammates share a side, then hands out seats.
    case hello(country: String, roomKey: String?)
    /// Host → one player: your assigned seat.
    case seatAssigned(seat: Int)
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
    /// Matchmaking / connection progress (player joined or left).
    func matchStateChanged()
    /// 2v2 only: the room master's teammate connected — the party is formed.
    func partyReady()
    /// The full table connected — the host is elected; seating can begin.
    func matchReady()
    /// Matchmaking failed or was cancelled by the system.
    func matchFailed(error: Error?)
    /// A connected player dropped. `wasHost` decides AI-takeover vs abort.
    func playerLeft(playerID: String, wasHost: Bool)
    func didReceive(_ message: PeerMessage, fromPlayerID: String)
}

final class GameKitMatchManager: NSObject {

    /// Internal matchmaking stage.
    private enum Stage { case idle, party, battle }

    weak var delegate: MatchManagerDelegate?

    private(set) var mode: MPMode = .twoVsTwo
    private(set) var match: GKMatch?
    private(set) var isMatchmaking = false
    private var stage: Stage = .idle
    private var partyAnnounced = false
    /// The room code, if this player hosted or joined a party.
    private(set) var roomKey: String?
    /// True for the player who generated the key (drives the Battle button).
    private(set) var isRoomMaster = false

    /// Fixed at election time so a later disconnect can't re-elect a new host
    /// mid-match (the sim lives on the original host).
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
    var connectedTotal: Int { connectedRemoteCount + 1 }

    func displayName(for playerID: String) -> String {
        if playerID == localPlayerID { return localDisplayName }
        return match?.players.first { $0.gamePlayerID == playerID }?.displayName ?? "Player"
    }

    // MARK: Room keys

    /// Mint a short, unambiguous room code (no 0/O/1/I to avoid typos).
    static func makeRoomKey() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<4).map { _ in alphabet.randomElement()! })
    }

    /// Stable (cross-process) hash of a room key → a private playerGroup, so
    /// only players who typed the same code land in the same party. Swift's
    /// Hasher is per-process randomized, so we roll a fixed FNV-1a instead.
    private func groupID(forRoomKey key: String) -> Int {
        var hash: UInt64 = 1469598103934665603      // FNV-1a offset basis
        for byte in key.uppercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211            // FNV-1a prime
        }
        return 100_000 + Int(hash % 900_000)         // 100000…999999, clear of pool IDs
    }

    // MARK: Party (2v2)

    /// Master: open a private room for `key` and wait for a teammate to join.
    func hostRoom(mode: MPMode, key: String) {
        stop()
        guard authGuard() else { return }
        self.mode = mode
        roomKey = key
        isRoomMaster = true
        beginFind(playerGroup: groupID(forRoomKey: key), minPlayers: 2, maxPlayers: 4,
                  stage: .party)
    }

    /// Teammate: join the private room identified by `key`.
    func joinRoom(mode: MPMode, key: String) {
        stop()
        guard authGuard() else { return }
        self.mode = mode
        roomKey = key
        isRoomMaster = false
        beginFind(playerGroup: groupID(forRoomKey: key), minPlayers: 2, maxPlayers: 4,
                  stage: .party)
    }

    // MARK: Battle (find the opposing side)

    /// Start matchmaking for opponents. 1v1 and solo players automatch a fresh
    /// table; a 2v2 party fills the two opponent seats onto its existing match.
    func startBattle(mode: MPMode) {
        guard authGuard() else { return }
        self.mode = mode
        if mode == .twoVsTwo, isRoomMaster, let match, connectedTotal < mode.totalPlayers {
            // We already have our teammate — add automatched opponents to the
            // existing party match. (Also the retry path after a timed-out search.)
            stage = .battle
            isMatchmaking = true
            let request = makeRequest(playerGroup: mode.poolGroup,
                                      minPlayers: 4, maxPlayers: 4)
            GKMatchmaker.shared().addPlayers(to: match, matchRequest: request) { [weak self] error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let error {
                        self.isMatchmaking = false
                        self.delegate?.matchFailed(error: error)
                        return
                    }
                    self.checkReady()
                }
            }
        } else {
            // 1v1, or a solo 2v2 player: automatch the whole table.
            beginFind(playerGroup: mode.poolGroup,
                      minPlayers: mode.totalPlayers, maxPlayers: mode.totalPlayers,
                      stage: .battle)
        }
    }

    // MARK: Matchmaking internals

    private func authGuard() -> Bool {
        guard GKLocalPlayer.local.isAuthenticated else {
            delegate?.matchFailed(error: nil)
            return false
        }
        return true
    }

    private func makeRequest(playerGroup: Int, minPlayers: Int, maxPlayers: Int) -> GKMatchRequest {
        let request = GKMatchRequest()
        request.minPlayers = minPlayers
        request.maxPlayers = maxPlayers
        request.playerGroup = playerGroup
        return request
    }

    private func beginFind(playerGroup: Int, minPlayers: Int, maxPlayers: Int, stage: Stage) {
        self.stage = stage
        if stage == .party { partyAnnounced = false }
        isMatchmaking = true
        let request = makeRequest(playerGroup: playerGroup,
                                  minPlayers: minPlayers, maxPlayers: maxPlayers)
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
                self.checkReady()
            }
        }
    }

    /// Cancel the outstanding automatch request without tearing down a match
    /// that already exists (e.g. keep a formed party while stopping the search).
    func cancelSearch() {
        if isMatchmaking { GKMatchmaker.shared().cancel() }
        isMatchmaking = false
    }

    func stop() {
        if isMatchmaking { GKMatchmaker.shared().cancel() }
        isMatchmaking = false
        stage = .idle
        partyAnnounced = false
        roomKey = nil
        isRoomMaster = false
        match?.delegate = nil
        match?.disconnect()
        match = nil
        hostPlayerID = nil
    }

    /// Fire the right readiness callback as players connect. A full table
    /// (both sides present) elects the host and starts the match; a half-full
    /// 2v2 party just announces the teammate. Counts drive this (rather than
    /// `expectedPlayerCount`, which can linger on a max>min party request);
    /// the connection delegate re-invokes this on every join.
    private func checkReady() {
        guard match != nil else { return }
        if connectedTotal >= mode.totalPlayers {
            guard hostPlayerID == nil else { return }
            stage = .battle
            hostPlayerID = allPlayerIDs.sorted().first
            isMatchmaking = false
            delegate?.matchReady()
        } else if stage == .party, connectedTotal >= 2, !partyAnnounced {
            // Teammate connected. Keep the match so Battle can add opponents.
            partyAnnounced = true
            isMatchmaking = false
            delegate?.partyReady()
        }
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
                self.checkReady()
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
