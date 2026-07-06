//
//  MultipeerManager.swift
//  TypingSoccer
//
//  Multiplayer transport using MultipeerConnectivity — 2v2 across 4 Macs.
//
//  Each team has TWO humans:
//    • the FIELD player  — controls the three outfielders (typing duels,
//      passes, and picking which defender chases the ball carrier)
//    • the KEEPER player — controls the goalkeeper (typing shot/penalty
//      duels in goal, and choosing who to pass to after a save/free kick)
//
//  Sync model: the HOST (always seat homeField) is authoritative. It picks
//  every duel word, resolves every duel, and decides possession, passes,
//  offside, breaks and penalties, broadcasting each as a PeerMessage over
//  the 4-peer mesh. The three joiners mirror the events and send back only
//  their own inputs (typing progress, completions, pass/chase requests),
//  tagged with their seat.
//
//  Wire convention: "home" in any message payload means the HOST's team.
//  Each machine maps that onto its own view (it always renders its own
//  team as the local `.home` side).
//

import Foundation
import MultipeerConnectivity

/// One of the four chairs in a 2v2 match. Raw values go over the wire.
/// `homeField` is always the host.
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

/// Messages exchanged across the 4-peer mesh. Coordinates (x / y / lineX)
/// are in the HOST's scene frame; machines on the away team mirror x.
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
}

protocol MultipeerManagerDelegate: AnyObject {
    /// Fired whenever the set of connected peers changes.
    func peersChanged(connected: [MCPeerID])
    func didReceive(_ message: PeerMessage, from peer: MCPeerID)
}

final class MultipeerManager: NSObject {

    static let serviceType = "typing-soccer"   // must be <= 15 chars, a-z0-9-
    /// A 2v2 match is the host + 3 joiners.
    static let requiredRemotePeers = 3

    weak var delegate: MultipeerManagerDelegate?

    // Include the process ID so multiple instances on ONE Mac (handy for
    // testing 2v2 locally) show up as distinct players in the lobby.
    let myPeerID = MCPeerID(displayName:
        "\(Host.current().localizedName ?? "Player") · \(ProcessInfo.processInfo.processIdentifier)")
    private lazy var session: MCSession = {
        let s = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        return s
    }()

    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    /// The host advertises, owns the lobby and is authoritative for the match.
    private(set) var isHost = false
    /// True between host()/join() and stop().
    private var wantsConnection = false

    var connectedPeers: [MCPeerID] { session.connectedPeers }
    var connectedCount: Int { session.connectedPeers.count }

    // MARK: Hosting / joining

    func host() {
        stop()
        isHost = true
        wantsConnection = true
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil,
                                               serviceType: Self.serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }

    func join() {
        stop()
        isHost = false
        wantsConnection = true
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    func stop() {
        wantsConnection = false
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        session.disconnect()
    }

    /// Host: stop advertising once the table is full; joiner: stop browsing
    /// once connected to a host. Discovery resumes if someone drops.
    private func refreshDiscovery() {
        guard wantsConnection else { return }
        if isHost {
            if session.connectedPeers.count >= Self.requiredRemotePeers {
                advertiser?.stopAdvertisingPeer()
            } else {
                advertiser?.startAdvertisingPeer()
            }
        } else {
            if session.connectedPeers.isEmpty {
                browser?.startBrowsingForPeers()
            } else {
                browser?.stopBrowsingForPeers()
            }
        }
    }

    // MARK: Sending

    /// Broadcast to every connected peer, or to `peers` only when given.
    func send(_ message: PeerMessage, to peers: [MCPeerID]? = nil) {
        let targets = peers ?? session.connectedPeers
        guard !targets.isEmpty else { return }
        // Live typing progress is cosmetic — send it unreliably.
        let mode: MCSessionSendDataMode
        if case .typingProgress = message { mode = .unreliable } else { mode = .reliable }
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: targets, with: mode)
        } catch {
            NSLog("Multipeer send failed: \(error)")
        }
    }
}

// MARK: - MCSessionDelegate

extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            guard state != .connecting else { return }
            self.refreshDiscovery()
            self.delegate?.peersChanged(connected: session.connectedPeers)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(PeerMessage.self, from: data) else { return }
        DispatchQueue.main.async {
            self.delegate?.didReceive(message, from: peerID)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Advertiser / Browser

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Host accepts joiners into the one shared session until 3 are in.
        invitationHandler(session.connectedPeers.count < Self.requiredRemotePeers, session)
    }
}

extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        // Only hosts advertise, so anything found is a host. One host at a time.
        guard session.connectedPeers.isEmpty else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
