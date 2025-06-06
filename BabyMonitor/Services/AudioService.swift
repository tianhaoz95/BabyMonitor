import Foundation
import AVFoundation

// Protocol for audio service delegate
protocol AudioServiceDelegate: AnyObject {
    func audioService(_ service: AudioService, didDetectSoundLevel level: Float)
    func audioService(_ service: AudioService, didFailWithError error: Error)
}

// Audio service class
class AudioService: NSObject {
    // Audio properties
    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayer?
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayerNode: AVAudioPlayerNode?
    
    // Audio state
    private(set) var isPlaying = false
    private(set) var isRecording = false
    private(set) var isMuted = false
    
    // Audio settings
    var volume: Float = 1.0 {
        didSet {
            updateVolume()
        }
    }
    
    // Sound detection
    private var soundDetectionTimer: Timer?
    private var soundThreshold: Float = 0.05
    
    // Delegate
    weak var delegate: AudioServiceDelegate?
    
    // Initialize audio service
    override init() {
        super.init()
        setupAudioSession()
    }
    
    deinit {
        stopAudioEngine()
        stopSoundDetection()
    }
    
    // MARK: - Audio Setup
    
    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            delegate?.audioService(self, didFailWithError: error)
        }
    }
    
    // Set up audio engine for processing
    func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        
        guard let engine = audioEngine else { return }
        
        // Set up audio player node
        audioPlayerNode = AVAudioPlayerNode()
        if let playerNode = audioPlayerNode {
            engine.attach(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        }
        
        do {
            try engine.start()
        } catch {
            delegate?.audioService(self, didFailWithError: error)
        }
    }
    
    // Stop audio engine
    func stopAudioEngine() {
        audioEngine?.stop()
        audioPlayerNode?.stop()
    }
    
    // MARK: - Audio Playback
    
    // Play audio from data
    func playAudioData(_ data: Data) {
        guard !isMuted else { return }
        
        do {
            // Create a temporary file to play the audio data
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
            
            try data.write(to: tempFile)
            
            audioPlayer = try AVAudioPlayer(contentsOf: tempFile)
            audioPlayer?.volume = volume
            audioPlayer?.play()
            
            isPlaying = true
            
            // Clean up temp file after playing
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                try? FileManager.default.removeItem(at: tempFile)
            }
        } catch {
            delegate?.audioService(self, didFailWithError: error)
        }
    }
    
    // Play audio from sample buffer
    func playAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard !isMuted, let audioPlayerNode = audioPlayerNode, audioEngine?.isRunning == true else { return }
        
        // Convert CMSampleBuffer to AVAudioPCMBuffer
        // This is a simplified implementation - in a real app, you would need proper conversion
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        
        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        
        guard let data = dataPointer, length > 0 else { return }
        
        let audioData = Data(bytes: data, count: length)
        playAudioData(audioData)
    }
    
    // Toggle mute state
    func toggleMute() -> Bool {
        isMuted = !isMuted
        
        if isMuted {
            audioPlayer?.pause()
            isPlaying = false
        }
        
        return isMuted
    }
    
    // Update volume
    private func updateVolume() {
        audioPlayer?.volume = volume
        audioPlayerNode?.volume = volume
    }
    
    // MARK: - Sound Detection
    
    // Start sound level detection
    func startSoundDetection() {
        guard audioEngine == nil else { return }
        
        setupAudioEngine()
        
        guard let engine = audioEngine else { return }
        
        // Set up input node for monitoring
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Install tap on input node to monitor audio levels
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // Calculate audio level from buffer
            let level = self.calculateAudioLevel(buffer: buffer)
            
            // Notify delegate on main thread
            DispatchQueue.main.async {
                self.delegate?.audioService(self, didDetectSoundLevel: level)
                
                // Check if sound level exceeds threshold
                if level > self.soundThreshold {
                    // Sound detected - could trigger notifications or other actions
                }
            }
        }
        
        do {
            try engine.start()
        } catch {
            delegate?.audioService(self, didFailWithError: error)
        }
    }
    
    // Stop sound detection
    func stopSoundDetection() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        stopAudioEngine()
        audioEngine = nil
    }
    
    // Calculate audio level from buffer
    private func calculateAudioLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }
        
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map { channelDataValue[$0] }
        
        let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        
        // Convert to decibels and normalize
        let avgPower = 20 * log10(rms)
        let normalizedValue = max(0.0, min(1.0, (avgPower + 50) / 50))
        
        return normalizedValue
    }
    
    // Set sound detection threshold
    func setSoundThreshold(_ threshold: Float) {
        soundThreshold = max(0.0, min(1.0, threshold))
    }
}