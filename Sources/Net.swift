import Foundation
import MultipeerConnectivity

/// Everything that travels between iPads.
enum Msg: Codable {
    case hello(PlayerInfo)
    case welcome(seed: UInt32, edits: [Edit], players: [PlayerInfo], dayTime: Double)
    case state(id: String, x: Float, y: Float, z: Float, yaw: Float)
    case edit(Edit)
    case leave(id: String)
    case tag(itId: String?, secondsLeft: Double, message: String)
    case tagged(by: String, target: String)
}

/// Local multiplayer over Wi-Fi / Bluetooth with MultipeerConnectivity.
/// The host iPad owns the world and relays messages to everyone else.
final class Net: NSObject, ObservableObject {
    static let service = "blokeiland"

    let peer: MCPeerID
    let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var worldNames: [MCPeerID: String] = [:]

    @Published var found: [MCPeerID] = []
    @Published var connectedCount = 0
    private(set) var joining: MCPeerID?
    private(set) var isHost = false

    var onMessage: ((Msg, MCPeerID) -> Void)?
    var onPeerChange: ((MCPeerID, MCSessionState) -> Void)?

    init(name: String) {
        let clean = String(name.prefix(30))
        peer = MCPeerID(displayName: clean.isEmpty ? "Speler" : clean)
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    func host(worldName: String) {
        isHost = true
        let a = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["w": String(worldName.prefix(40))], serviceType: Net.service)
        a.delegate = self
        a.startAdvertisingPeer()
        advertiser = a
    }

    func browse() {
        let b = MCNearbyServiceBrowser(peer: peer, serviceType: Net.service)
        b.delegate = self
        b.startBrowsingForPeers()
        browser = b
    }

    func worldName(_ p: MCPeerID) -> String { worldNames[p] ?? "Eiland van \(p.displayName)" }

    func join(_ p: MCPeerID) {
        joining = p
        browser?.invitePeer(p, to: session, withContext: nil, timeout: 20)
    }

    func send(_ m: Msg, reliable: Bool = true, to peers: [MCPeerID]? = nil, except: MCPeerID? = nil) {
        let targets = (peers ?? session.connectedPeers).filter { $0 != except }
        guard !targets.isEmpty, let data = try? JSONEncoder().encode(m) else { return }
        try? session.send(data, toPeers: targets, with: reliable ? .reliable : .unreliable)
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
    }
}

extension Net: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedCount = session.connectedPeers.count
            self.onPeerChange?(peerID, state)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let m = try? JSONDecoder().decode(Msg.self, from: data) else { return }
        DispatchQueue.main.async { self.onMessage?(m, peerID) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension Net: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}

extension Net: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            if let w = info?["w"] { self.worldNames[peerID] = w }
            if !self.found.contains(peerID) { self.found.append(peerID) }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { self.found.removeAll { $0 == peerID } }
    }
}
