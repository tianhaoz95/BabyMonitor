import Foundation
import MultipeerConnectivity
import UIKit
import AVFoundation

class ViewerViewModel: NSObject, ObservableObject {
    // Multipeer connectivity
    private var peerID: MCPeerID!
    private var mcSession: MCSession!
    private var mcBrowser: MCNearbyServiceBrowser!
    
    // Video display
    @Published var currentFrame: UIImage?
    private var audioPlayer: AVAudioPlayer?
    
    // Connection state
    @Published var isSearching = false
    @Published var isConnected = false
    @Published var connectedPeerName = ""
    
    // UI state
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    
    // Settings
    @Published var autoConnect = true
    @Published var isMuted = false
    @Published var volume: Float = 0.8
    @Published var keepScreenOn = true
    @Published var soundAlerts = true
    @Published var motionDetection = false
    @Published var knownMonitors: [String] = []
    @Published var selectedMonitor = ""
    
    // Data processing
    private var videoFrameQueue = DispatchQueue(label: "videoFrameQueue")
    private var audioQueue = DispatchQueue(label: "audioQueue")
    
    override init() {
        super.init()
        setupMultipeerConnectivity()
        loadSettings()
    }
    
    // MARK: - Settings Management
    
    private func loadSettings() {
        let defaults = UserDefaults.standard
        autoConnect = defaults.bool(forKey: "autoConnect")
        isMuted = defaults.bool(forKey: "isMuted")
        volume = defaults.float(forKey: "volume")
        keepScreenOn = defaults.bool(forKey: "keepScreenOn")
        soundAlerts = defaults.bool(forKey: "soundAlerts")
        motionDetection = defaults.bool(forKey: "motionDetection")
        knownMonitors = defaults.stringArray(forKey: "knownMonitors") ?? []
        selectedMonitor = defaults.string(forKey: "selectedMonitor") ?? ""
    }
    
    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(autoConnect, forKey: "autoConnect")
        defaults.set(isMuted, forKey: "isMuted")
        defaults.set(volume, forKey: "volume")
        defaults.set(keepScreenOn, forKey: "keepScreenOn")
        defaults.set(soundAlerts, forKey: "soundAlerts")
        defaults.set(motionDetection, forKey: "motionDetection")
        defaults.set(knownMonitors, forKey: "knownMonitors")
        defaults.set(selectedMonitor, forKey: "selectedMonitor")
    }
    
    // MARK: - Multipeer Connectivity
    
    private func setupMultipeerConnectivity() {
        peerID = MCPeerID(displayName: UIDevice.current.name)
        mcSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        mcSession.delegate = self
    }
    
    func startBrowsing() {
        isSearching = true
        mcBrowser = MCNearbyServiceBrowser(peer: peerID, serviceType: "baby-monitor")
        mcBrowser.delegate = self
        mcBrowser.startBrowsingForPeers()
        
        // Auto-connect to selected monitor if enabled
        if autoConnect && !selectedMonitor.isEmpty {
            // This is a simplified implementation - in a real app, you would need
            // to match the peer ID with the stored monitor name
        }
    }
    
    func stopBrowsing() {
        isSearching = false
        mcBrowser?.stopBrowsingForPeers()
    }
    
    func disconnect() {
        if isConnected {
            mcSession.disconnect()
            isConnected = false
            connectedPeerName = ""
            currentFrame = nil
            saveSettings()
        }
    }
    
    // MARK: - Audio Controls
    
    func toggleMute() {
        isMuted.toggle()
        saveSettings()
    }
    
    // MARK: - Video Controls
    
    func takeSnapshot() {
        guard let image = currentFrame else {
            showAlert(title: "Cannot Take Snapshot", message: "No video feed is available.")
            return
        }
        
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    
    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            showAlert(title: "Save Error", message: error.localizedDescription)
        } else {
            showAlert(title: "Saved", message: "Snapshot saved to your photo library.")
        }
    }
    
    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            self.alertTitle = title
            self.alertMessage = message
            self.showAlert = true
        }
    }
    
    // MARK: - Data Processing
    
    private func processReceivedData(_ data: Data) {
        // Extract metadata length (first 4 bytes)
        guard data.count > 4 else { return }
        
        var metadataLength: UInt32 = 0
        (data as NSData).getBytes(&metadataLength, length: 4)
        
        // Extract metadata
        let metadataEndIndex = 4 + Int(metadataLength)
        guard data.count >= metadataEndIndex else { return }
        
        let metadataData = data.subdata(in: 4..<metadataEndIndex)
        guard let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
              let type = metadata["type"] as? String else { return }
        
        // Extract payload
        let payload = data.subdata(in: metadataEndIndex..<data.count)
        
        // Process based on type
        if type == "video" {
            processVideoData(payload)
        } else if type == "audio" {
            processAudioData(payload)
        }
    }
    
    private func processVideoData(_ data: Data) {
        guard let image = UIImage(data: data) else { return }
        
        DispatchQueue.main.async {
            self.currentFrame = image
        }
    }
    
    private func processAudioData(_ data: Data) {
        // In a real implementation, you would properly decode and play audio
        // This is simplified for demonstration purposes
        if isMuted { return }
        
        // Play audio data
        // Note: This is a simplified implementation and won't work with raw audio data
        // A real implementation would use AVAudioEngine or similar
    }
}

// MARK: - MCSessionDelegate
extension ViewerViewModel: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.isConnected = true
                self.isSearching = false
                self.connectedPeerName = peerID.displayName
                
                // Save to known monitors if not already saved
                if !self.knownMonitors.contains(peerID.displayName) {
                    self.knownMonitors.append(peerID.displayName)
                    self.selectedMonitor = peerID.displayName
                    self.saveSettings()
                }
                
                self.showAlert(title: "Connected", message: "Connected to \(peerID.displayName)")
                
            case .notConnected:
                if self.isConnected {
                    self.isConnected = false
                    self.currentFrame = nil
                    self.showAlert(title: "Disconnected", message: "Lost connection to \(peerID.displayName)")
                }
                
            case .connecting:
                print("Connecting to: \(peerID.displayName)")
                
            @unknown default:
                print("Unknown state: \(peerID.displayName)")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        processReceivedData(data)
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used in this implementation
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used in this implementation
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used in this implementation
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension ViewerViewModel: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        // Invite the peer to connect
        browser.invitePeer(peerID, to: mcSession, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("Lost peer: \(peerID.displayName)")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        isSearching = false
        showAlert(title: "Browsing Error", message: "Could not search for monitors: \(error.localizedDescription)")
    }
}