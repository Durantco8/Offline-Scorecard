import Foundation
import MultipeerConnectivity
import CRDTKit

/// MultipeerConnectivity-backed transport.
///
/// Handles peer discovery, session management, and DeviceID ↔ MCPeerID mapping.
/// Auto-accepts all invitations (no auth for v1).
///
/// On connect, sends a handshake message containing the local DeviceID so the
/// remote can map MCPeerID → DeviceID. Until the handshake is received, messages
/// from that peer are queued.
public final class MCTransport: NSObject, Transport {
    public let deviceID: DeviceID
    public var onReceive: ((Data, DeviceID) -> Void)?

    /// Called when a peer connects or disconnects. Key: DeviceID, Value: true if connected.
    public var onPeerChange: ((DeviceID, Bool) -> Void)?

    private let serviceType: String
    private let session: MCSession
    private let myPeerID: MCPeerID
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser

    /// MCPeerID → DeviceID mapping, established via handshake.
    private var peerMap: [MCPeerID: DeviceID] = [:]
    /// Reverse lookup for sending.
    private var reversePeerMap: [DeviceID: MCPeerID] = [:]
    /// Messages received before handshake completed.
    private var pendingMessages: [MCPeerID: [Data]] = [:]

    private static let handshakePrefix = Data([0xFF, 0xFE])

    /// - Parameters:
    ///   - deviceID: This device's stable DeviceID.
    ///   - serviceType: Bonjour service type (1-15 chars, lowercase + hyphens).
    ///   - displayName: Human-readable name for this peer.
    public init(deviceID: DeviceID, serviceType: String = "crdt-golf", displayName: String? = nil) {
        self.deviceID = deviceID
        self.serviceType = serviceType
        self.myPeerID = MCPeerID(displayName: displayName ?? deviceID.uuid.uuidString.prefix(8).description)
        self.session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .none)
        self.advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        self.browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    // MARK: - Start / Stop

    public func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    public func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        peerMap.removeAll()
        reversePeerMap.removeAll()
        pendingMessages.removeAll()
    }

    // MARK: - Transport

    public func send(_ data: Data, to peer: DeviceID) {
        guard let mcPeer = reversePeerMap[peer] else { return }
        try? session.send(data, toPeers: [mcPeer], with: .reliable)
    }

    public func broadcast(_ data: Data) {
        let connected = session.connectedPeers
        guard !connected.isEmpty else { return }
        try? session.send(data, toPeers: connected, with: .reliable)
    }

    // MARK: - Handshake

    private func sendHandshake(to mcPeer: MCPeerID) {
        var payload = Self.handshakePrefix
        payload.append(deviceID.uuid.data)
        try? session.send(payload, toPeers: [mcPeer], with: .reliable)
    }

    private func isHandshake(_ data: Data) -> DeviceID? {
        guard data.count == Self.handshakePrefix.count + 16,
              data.prefix(Self.handshakePrefix.count) == Self.handshakePrefix else {
            return nil
        }
        let uuidBytes = data.suffix(16)
        let b = [UInt8](uuidBytes)
        let uuid = UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                                b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
        return DeviceID(uuid)
    }

    /// Connected DeviceIDs (handshake completed).
    public var connectedDevices: Set<DeviceID> {
        Set(reversePeerMap.keys)
    }
}

// MARK: - UUID.data

private extension UUID {
    var data: Data {
        let u = self.uuid
        return Data([u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7,
                     u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15])
    }
}

// MARK: - MCSessionDelegate

extension MCTransport: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            sendHandshake(to: peerID)
        case .notConnected:
            if let deviceID = peerMap[peerID] {
                peerMap.removeValue(forKey: peerID)
                reversePeerMap.removeValue(forKey: deviceID)
                onPeerChange?(deviceID, false)
            }
            pendingMessages.removeValue(forKey: peerID)
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Check for handshake
        if let remoteDeviceID = isHandshake(data) {
            peerMap[peerID] = remoteDeviceID
            reversePeerMap[remoteDeviceID] = peerID
            onPeerChange?(remoteDeviceID, true)

            // Drain any messages that arrived before handshake
            if let queued = pendingMessages.removeValue(forKey: peerID) {
                for msg in queued {
                    onReceive?(msg, remoteDeviceID)
                }
            }
            return
        }

        // Regular message
        if let deviceID = peerMap[peerID] {
            onReceive?(data, deviceID)
        } else {
            // Handshake not yet received — queue
            pendingMessages[peerID, default: []].append(data)
        }
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MCTransport: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }

    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {}
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MCTransport: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {}
}
