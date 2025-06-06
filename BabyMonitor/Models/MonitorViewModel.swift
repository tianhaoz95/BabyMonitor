import Foundation
import AVFoundation
import MultipeerConnectivity

class MonitorViewModel: NSObject, ObservableObject {
    // Camera properties
    let session = AVCaptureSession()
    var videoOutput = AVCaptureVideoDataOutput()
    var audioOutput = AVCaptureAudioDataOutput()
    private var captureDevice: AVCaptureDevice?
    private var frontCaptureDevice: AVCaptureDevice?
    private var backCaptureDevice: AVCaptureDevice?
    private var currentPosition: AVCaptureDevice.Position = .back
    
    // Streaming properties
    private var peerID: MCPeerID!
    private var mcSession: MCSession!
    private var mcAdvertiser: MCNearbyServiceAdvertiser!
    
    // UI state
    @Published var isStreaming = false
    @Published var isTorchOn = false
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    
    // Settings
    @Published var deviceID = UIDevice.current.name
    @Published var autoConnect = true
    @Published var nightVisionMode = false
    @Published var highQualityStream = false
    @Published var microphoneEnabled = true
    
    override init() {
        super.init()
        setupMultipeerConnectivity()
    }
    
    // MARK: - Camera Setup
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // Camera permission already granted
            checkAudioPermissions()
        case .notDetermined:
            // Request camera permission
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.checkAudioPermissions()
                } else {
                    self?.showPermissionAlert(for: "Camera")
                }
            }
        default:
            showPermissionAlert(for: "Camera")
        }
    }
    
    private func checkAudioPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            // Audio permission already granted
            break
        case .notDetermined:
            // Request audio permission
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if !granted {
                    self?.showPermissionAlert(for: "Microphone")
                }
            }
        default:
            showPermissionAlert(for: "Microphone")
        }
    }
    
    private func showPermissionAlert(for device: String) {
        DispatchQueue.main.async {
            self.alertTitle = "\(device) Access Required"
            self.alertMessage = "Please enable \(device.lowercased()) access in Settings to use this feature."
            self.showAlert = true
        }
    }
    
    func setupSession() {
        session.beginConfiguration()
        
        // Set up video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            showAlert(title: "Camera Error", message: "Could not find a camera device.")
            return
        }
        
        backCaptureDevice = videoDevice
        frontCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        captureDevice = backCaptureDevice
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }
            
            // Set up video output
            videoOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)]
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
            
            // Set up audio input if enabled
            if microphoneEnabled, let audioDevice = AVCaptureDevice.default(for: .audio) {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                }
                
                // Set up audio output
                audioOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "audioQueue"))
                if session.canAddOutput(audioOutput) {
                    session.addOutput(audioOutput)
                }
            }
            
            session.commitConfiguration()
            
            // Start session on background thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
            
        } catch {
            showAlert(title: "Camera Error", message: "Could not set up camera: \(error.localizedDescription)")
        }
    }
    
    func stopSession() {
        if session.isRunning {
            session.stopRunning()
        }
        if isStreaming {
            stopStreaming()
        }
    }
    
    func switchCamera() {
        guard let currentInput = session.inputs.first as? AVCaptureDeviceInput else { return }
        
        // Determine which camera to switch to
        currentPosition = currentPosition == .back ? .front : .back
        captureDevice = currentPosition == .back ? backCaptureDevice : frontCaptureDevice
        
        guard let newCaptureDevice = captureDevice else { return }
        
        session.beginConfiguration()
        session.removeInput(currentInput)
        
        do {
            let newInput = try AVCaptureDeviceInput(device: newCaptureDevice)
            if session.canAddInput(newInput) {
                session.addInput(newInput)
            }
            session.commitConfiguration()
        } catch {
            showAlert(title: "Camera Error", message: "Could not switch cameras.")
        }
    }
    
    // MARK: - Torch Control
    
    func toggleTorch() {
        isTorchOn ? disableTorch() : enableTorch()
    }
    
    func enableTorch() {
        guard let device = captureDevice, device.hasTorch, device.position == .back else { return }
        
        do {
            try device.lockForConfiguration()
            try device.setTorchModeOn(level: 1.0)
            device.unlockForConfiguration()
            isTorchOn = true
        } catch {
            showAlert(title: "Torch Error", message: "Could not enable torch.")
        }
    }
    
    func disableTorch() {
        guard let device = captureDevice, device.hasTorch, device.torchMode == .on else { return }
        
        do {
            try device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
            isTorchOn = false
        } catch {
            showAlert(title: "Torch Error", message: "Could not disable torch.")
        }
    }
    
    // MARK: - Multipeer Connectivity
    
    private func setupMultipeerConnectivity() {
        peerID = MCPeerID(displayName: UIDevice.current.name)
        mcSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        mcSession.delegate = self
    }
    
    func toggleStreaming() {
        if isStreaming {
            stopStreaming()
        } else {
            startStreaming()
        }
    }
    
    func startStreaming() {
        mcAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: "baby-monitor")
        mcAdvertiser.delegate = self
        mcAdvertiser.startAdvertisingPeer()
        isStreaming = true
    }
    
    func stopStreaming() {
        mcAdvertiser?.stopAdvertisingPeer()
        isStreaming = false
    }
    
    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            self.alertTitle = title
            self.alertMessage = message
            self.showAlert = true
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension MonitorViewModel: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isStreaming, mcSession.connectedPeers.count > 0 else { return }
        
        // Determine if this is video or audio
        let isVideo = output is AVCaptureVideoDataOutput
        
        // For high quality, send as is. For low quality, compress video further
        if isVideo && !highQualityStream {
            // Compress video for lower quality
            guard let compressedData = compressVideoSampleBuffer(sampleBuffer) else { return }
            sendData(compressedData, isVideo: true)
        } else {
            // Send original sample buffer data
            guard let data = sampleBufferToData(sampleBuffer, isVideo: isVideo) else { return }
            sendData(data, isVideo: isVideo)
        }
    }
    
    private func sampleBufferToData(_ sampleBuffer: CMSampleBuffer, isVideo: Bool) -> Data? {
        // Convert CMSampleBuffer to Data
        // This is a simplified implementation - in a real app, you would use
        // more efficient compression and serialization
        
        if isVideo, let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
            
            let uiImage = UIImage(cgImage: cgImage)
            // Compress image quality based on settings
            let compressionQuality: CGFloat = highQualityStream ? 0.7 : 0.3
            return uiImage.jpegData(compressionQuality: compressionQuality)
        } else {
            // For audio data, we would need proper audio encoding
            // This is simplified for demonstration
            return nil
        }
    }
    
    private func compressVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> Data? {
        // Further compress video for low quality streaming
        // This is a simplified implementation
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        
        // Create a smaller image
        let scale: CGFloat = 0.5 // 50% of original size
        let width = CGFloat(cgImage.width) * scale
        let height = CGFloat(cgImage.height) * scale
        
        UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: height), true, 1.0)
        let context2 = UIGraphicsGetCurrentContext()!
        context2.interpolationQuality = .low
        context2.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
    
        // Compress with low quality
        return scaledImage.jpegData(compressionQuality: 0.2)
    }
    
    private func sendData(_ data: Data, isVideo: Bool) {
        // Create a dictionary with metadata
        let metadata: [String: Any] = [
            "type": isVideo ? "video" : "audio",
            "timestamp": Date().timeIntervalSince1970
        ]
        
        // Serialize metadata
        guard let metadataData = try? JSONSerialization.data(withJSONObject: metadata) else { return }
        
        // Create a combined data package with metadata length + metadata + payload
        var combinedData = Data()
        var metadataLength = UInt32(metadataData.count)
        combinedData.append(Data(bytes: &metadataLength, count: MemoryLayout<UInt32>.size))
        combinedData.append(metadataData)
        combinedData.append(data)
        
        // Send to all connected peers
        do {
            try mcSession.send(combinedData, toPeers: mcSession.connectedPeers, with: .reliable)
        } catch {
            print("Error sending data: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCSessionDelegate
extension MonitorViewModel: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.showAlert(title: "Connected", message: "Viewer connected: \(peerID.displayName)")
            case .notConnected:
                print("Disconnected from: \(peerID.displayName)")
            case .connecting:
                print("Connecting to: \(peerID.displayName)")
            @unknown default:
                print("Unknown state: \(peerID.displayName)")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Handle commands from viewer if needed
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

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MonitorViewModel: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept connections
        invitationHandler(true, mcSession)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        showAlert(title: "Advertising Error", message: "Could not start advertising: \(error.localizedDescription)")
    }
}
