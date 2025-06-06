import Foundation
import MultipeerConnectivity

// Protocol for connection service delegate
protocol ConnectionServiceDelegate: AnyObject {
    func connectionService(_ service: ConnectionService, didChangeState state: ConnectionState, for peer: MCPeerID?)
    func connectionService(_ service: ConnectionService, didReceiveData data: Data, from peer: MCPeerID)
}

// Connection states
enum ConnectionState {
    case notConnected
    case connecting
    case connected
    case error(String)
}

// Connection modes
enum ConnectionMode {
    case monitor
    case viewer
}

// Main connection service class
class ConnectionService: NSObject {
    // Multipeer connectivity properties
    private var peerID: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    // Service properties
    private let serviceType = "baby-monitor"
    private(set) var mode: ConnectionMode
    private(set) var state: ConnectionState = .notConnected
    
    // Delegate
    weak var delegate: ConnectionServiceDelegate?
    
    // Connected peers
    var connectedPeers: [MCPeerID] {
        return session.connectedPeers
    }
    
    // Initialize with a specific mode
    init(mode: ConnectionMode, displayName: String = UIDevice.current.name) {
        self.mode = mode
        self.peerID = MCPeerID(displayName: displayName)
        self.session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        
        super.init()
        
        self.session.delegate = self
    }
    
    // Start the service based on mode
    func start() {
        switch mode {
        case .monitor:
            startAdvertising()
        case .viewer:
            startBrowsing()
        }
    }
    
    // Stop the service
    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
        setState(.notConnected)
    }
    
    // Send data to all connected peers
    func sendData(_ data: Data) -> Bool {
        guard !session.connectedPeers.isEmpty else { return false }
        
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            return true
        } catch {
            print("Error sending data: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Private Methods
    
    private func startAdvertising() {
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }
    
    private func startBrowsing() {
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        setState(.notConnected)
    }
    
    private func setState(_ newState: ConnectionState) {
        state = newState
        var peer: MCPeerID? = nil
        
        if case .connected = newState, !session.connectedPeers.isEmpty {
            peer = session.connectedPeers.first
        }
        
        delegate?.connectionService(self, didChangeState: newState, for: peer)
    }
}

// MARK: - MCSessionDelegate
extension ConnectionService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            setState(.connected)
        case .connecting:
            setState(.connecting)
        case .notConnected:
            setState(.notConnected)
        @unknown default:
            setState(.error("Unknown session state"))
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        delegate?.connectionService(self, didReceiveData: data, from: peerID)
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not implemented
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not implemented
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not implemented
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension ConnectionService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept connections in monitor mode
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        setState(.error("Failed to start advertising: \(error.localizedDescription)"))
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension ConnectionService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        // Auto-invite found peers in viewer mode
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // Peer is no longer available
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        setState(.error("Failed to start browsing: \(error.localizedDescription)"))
    }
}

// MARK: - Data Packaging Utilities
extension ConnectionService {
    // Package data with metadata for sending
    static func packageData(type: String, payload: Data) -> Data? {
        // Create metadata dictionary
        let metadata: [String: Any] = [
            "type": type,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        // Serialize metadata
        guard let metadataData = try? JSONSerialization.data(withJSONObject: metadata) else { return nil }
        
        // Create combined data package
        var combinedData = Data()
        var metadataLength = UInt32(metadataData.count)
        combinedData.append(Data(bytes: &metadataLength, count: MemoryLayout<UInt32>.size))
        combinedData.append(metadataData)
        combinedData.append(payload)
        
        return combinedData
    }
    
    // Unpackage received data
    static func unpackageData(_ data: Data) -> (type: String, payload: Data)? {
        // Extract metadata length
        guard data.count > 4 else { return nil }
        
        var metadataLength: UInt32 = 0
        (data as NSData).getBytes(&metadataLength, length: 4)
        
        // Extract metadata
        let metadataEndIndex = 4 + Int(metadataLength)
        guard data.count >= metadataEndIndex else { return nil }
        
        let metadataData = data.subdata(in: 4..<metadataEndIndex)
        guard let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
              let type = metadata["type"] as? String else { return nil }
        
        // Extract payload
        let payload = data.subdata(in: metadataEndIndex..<data.count)
        
        return (type, payload)
    }
}