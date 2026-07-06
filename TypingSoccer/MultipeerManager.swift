//
//  MultipeerManager.swift
//  TypingSoccer
//
//  Multiplayer transport for the rival side using MultipeerConnectivity.
//  In multiplayer mode the away team is another human on the local network;
//  we exchange tiny control messages (word-completed, kickoff word, score).
//
//  This is a working scaffold: it advertises/browses, connects, and relays
//  "word completed" events into the scene. Extend the message set as needed.
//

import Foundation
import MultipeerConnectivity

/// Messages exchanged between the two peers.
enum PeerMessage: Codable {
    case ready
    case kickoffWord(String)          // host tells peer the shared kickoff word
    case wordCompleted                // "I finished typing my word"
    case score(home: Int, away: Int)  // authoritative score sync from host
    case goal(byHome: Bool)
}

protocol MultipeerManagerDelegate: AnyObject {
    func peerConnectionChanged(connected: Bool)
    func didReceive(_ message: PeerMessage, from peer: MCPeerID)
}

final class MultipeerManager: NSObject {

    static let serviceType = "typing-soccer"   // must be <= 15 chars, a-z0-9-

    weak var delegate: MultipeerManagerDelegate?

    private let myPeerID = MCPeerID(displayName: Host.current().localizedName ?? "Player")
    private lazy var session: MCSession = {
        let s = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        return s
    }()

    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    /// The host advertises and is authoritative for scoring.
    private(set) var isHost = false

    var isConnected: Bool { !session.connectedPeers.isEmpty }

    // MARK: Hosting / joining

    func host() {
        isHost = true
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil,
                                               serviceType: Self.serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }

    func join() {
        isHost = false
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
    }

    // MARK: Sending

    func send(_ message: PeerMessage) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            NSLog("Multipeer send failed: \(error)")
        }
    }
}

// MARK: - MCSessionDelegate

extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.delegate?.peerConnectionChanged(connected: state == .connected)
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
        invitationHandler(true, session)   // auto-accept for the prototype
    }
}

extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
