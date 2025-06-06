import Foundation
import AVFoundation
import UIKit

// Protocol for camera service delegate
protocol CameraServiceDelegate: AnyObject {
    func cameraService(_ service: CameraService, didCaptureVideoFrame frame: UIImage)
    func cameraService(_ service: CameraService, didCaptureAudioSample buffer: CMSampleBuffer)
    func cameraService(_ service: CameraService, didFailWithError error: Error)
}

// Camera service class
class CameraService: NSObject {
    // Camera properties
    private let session = AVCaptureSession()
    private var videoOutput = AVCaptureVideoDataOutput()
    private var audioOutput = AVCaptureAudioDataOutput()
    private var captureDevice: AVCaptureDevice?
    private var frontCaptureDevice: AVCaptureDevice?
    private var backCaptureDevice: AVCaptureDevice?
    
    // Camera state
    private(set) var isRunning = false
    private(set) var currentPosition: AVCaptureDevice.Position = .back
    private(set) var isTorchOn = false
    
    // Quality settings
    var highQuality = false {
        didSet {
            configureSessionQuality()
        }
    }
    
    // Audio settings
    var microphoneEnabled = true {
        didSet {
            configureMicrophone()
        }
    }
    
    // Delegate
    weak var delegate: CameraServiceDelegate?
    
    // Initialize camera service
    override init() {
        super.init()
    }
    
    // MARK: - Camera Setup
    
    // Check camera and microphone permissions
    func checkPermissions(completion: @escaping (Bool) -> Void) {
        let cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let audioAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch (cameraAuthStatus, audioAuthStatus) {
        case (.authorized, .authorized):
            // Both permissions already granted
            completion(true)
            
        case (.notDetermined, _):
            // Request camera permission
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.checkAudioPermission(completion: completion)
                } else {
                    completion(false)
                }
            }
            
        case (_, .notDetermined):
            // Request audio permission
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                completion(granted)
            }
            
        default:
            // Permission denied for either camera or audio
            completion(false)
        }
    }
    
    private func checkAudioPermission(completion: @escaping (Bool) -> Void) {
        let audioAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch audioAuthStatus {
        case .authorized:
            completion(true)
            
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                completion(granted)
            }
            
        default:
            completion(false)
        }
    }
    
    // Set up the capture session
    func setupSession() -> Bool {
        session.beginConfiguration()
        
        // Set up video input
        guard setupVideoInput() else {
            session.commitConfiguration()
            return false
        }
        
        // Set up video output
        setupVideoOutput()
        
        // Set up audio input and output if enabled
        if microphoneEnabled {
            setupAudioInputOutput()
        }
        
        // Configure session quality
        configureSessionQuality()
        
        session.commitConfiguration()
        return true
    }
    
    private func setupVideoInput() -> Bool {
        // Find available camera devices
        backCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        frontCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        
        // Use back camera by default
        captureDevice = currentPosition == .back ? backCaptureDevice : frontCaptureDevice
        
        guard let videoDevice = captureDevice else {
            let error = NSError(domain: "CameraService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No camera device available"])
            delegate?.cameraService(self, didFailWithError: error)
            return false
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                return true
            } else {
                let error = NSError(domain: "CameraService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not add video input to session"])
                delegate?.cameraService(self, didFailWithError: error)
                return false
            }
        } catch {
            delegate?.cameraService(self, didFailWithError: error)
            return false
        }
    }
    
    private func setupVideoOutput() {
        videoOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)]
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
    }
    
    private func setupAudioInputOutput() {
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else { return }
        
        do {
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }
            
            audioOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "audioQueue"))
            if session.canAddOutput(audioOutput) {
                session.addOutput(audioOutput)
            }
        } catch {
            print("Error setting up audio: \(error.localizedDescription)")
        }
    }
    
    private func configureSessionQuality() {
        guard isRunning else { return }
        
        session.beginConfiguration()
        
        if highQuality {
            session.sessionPreset = .high
        } else {
            session.sessionPreset = .medium
        }
        
        session.commitConfiguration()
    }
    
    private func configureMicrophone() {
        guard isRunning else { return }
        
        session.beginConfiguration()
        
        // Remove existing audio inputs and outputs
        session.inputs.forEach { input in
            if input.ports.contains(where: { $0.mediaType == .audio }) {
                session.removeInput(input)
            }
        }
        
        session.outputs.forEach { output in
            if output is AVCaptureAudioDataOutput {
                session.removeOutput(output)
            }
        }
        
        // Add audio input and output if enabled
        if microphoneEnabled {
            setupAudioInputOutput()
        }
        
        session.commitConfiguration()
    }
    
    // MARK: - Camera Control
    
    // Start the capture session
    func startSession() {
        guard !isRunning else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            
            DispatchQueue.main.async {
                self?.isRunning = self?.session.isRunning ?? false
            }
        }
    }
    
    // Stop the capture session
    func stopSession() {
        guard isRunning else { return }
        
        session.stopRunning()
        isRunning = false
        
        // Turn off torch if it's on
        if isTorchOn {
            toggleTorch(on: false)
        }
    }
    
    // Switch between front and back cameras
    func switchCamera() -> Bool {
        guard let currentInput = session.inputs.first as? AVCaptureDeviceInput else { return false }
        
        // Determine which camera to switch to
        currentPosition = currentPosition == .back ? .front : .back
        captureDevice = currentPosition == .back ? backCaptureDevice : frontCaptureDevice
        
        guard let newCaptureDevice = captureDevice else { return false }
        
        session.beginConfiguration()
        session.removeInput(currentInput)
        
        do {
            let newInput = try AVCaptureDeviceInput(device: newCaptureDevice)
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                session.commitConfiguration()
                
                // Turn off torch when switching to front camera
                if currentPosition == .front && isTorchOn {
                    toggleTorch(on: false)
                }
                
                return true
            } else {
                // Restore the previous input if adding the new one fails
                session.addInput(currentInput)
                session.commitConfiguration()
                return false
            }
        } catch {
            // Restore the previous input if an error occurs
            session.addInput(currentInput)
            session.commitConfiguration()
            delegate?.cameraService(self, didFailWithError: error)
            return false
        }
    }
    
    // Toggle the torch (flashlight)
    func toggleTorch(on: Bool) -> Bool {
        guard let device = captureDevice, device.hasTorch, device.position == .back else {
            return false
        }
        
        do {
            try device.lockForConfiguration()
            
            if on {
                try device.setTorchModeOn(level: 1.0)
            } else {
                device.torchMode = .off
            }
            
            device.unlockForConfiguration()
            isTorchOn = device.torchMode == .on
            return true
        } catch {
            delegate?.cameraService(self, didFailWithError: error)
            return false
        }
    }
    
    // Get the capture session for preview layer
    func getCaptureSession() -> AVCaptureSession {
        return session
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate
extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Determine if this is video or audio
        if output is AVCaptureVideoDataOutput {
            processVideoSampleBuffer(sampleBuffer)
        } else if output is AVCaptureAudioDataOutput {
            processAudioSampleBuffer(sampleBuffer)
        }
    }
    
    private func processVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        let image = UIImage(cgImage: cgImage)
        delegate?.cameraService(self, didCaptureVideoFrame: image)
    }
    
    private func processAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        delegate?.cameraService(self, didCaptureAudioSample: sampleBuffer)
    }
}