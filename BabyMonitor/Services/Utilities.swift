import Foundation
import UIKit
import AVFoundation

// Utility class for helper functions
class Utilities {
    // MARK: - Image Processing
    
    // Compress an image to a specific quality level
    static func compressImage(_ image: UIImage, quality: CGFloat) -> Data? {
        return image.jpegData(compressionQuality: quality)
    }
    
    // Resize an image to a specific size
    static func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        
        // Figure out what our orientation is, and use that to form the rectangle
        var newSize: CGSize
        if(widthRatio > heightRatio) {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
        }
        
        // This is the rect that we've calculated out and this is what is actually used below
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        
        // Actually do the resizing to the rect using the ImageContext stuff
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? image
    }
    
    // Convert CMSampleBuffer to UIImage
    static func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - Data Conversion
    
    // Convert UIImage to Data with compression
    static func imageToData(_ image: UIImage, highQuality: Bool) -> Data? {
        let compressionQuality: CGFloat = highQuality ? 0.8 : 0.3
        return image.jpegData(compressionQuality: compressionQuality)
    }
    
    // MARK: - Device Information
    
    // Get device name
    static func getDeviceName() -> String {
        return UIDevice.current.name
    }
    
    // Get device model
    static func getDeviceModel() -> String {
        return UIDevice.current.model
    }
    
    // Check if device has torch
    static func deviceHasTorch() -> Bool {
        guard let device = AVCaptureDevice.default(for: .video) else { return false }
        return device.hasTorch
    }
    
    // MARK: - Network Utilities
    
    // Get device IP address
    static func getIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                
                guard let interface = ptr?.pointee else { continue }
                let addrFamily = interface.ifa_addr.pointee.sa_family
                
                if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                    // Check interface name: en0 is WiFi, en1 is Ethernet
                    let name = String(cString: interface.ifa_name)
                    if name == "en0" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                    &hostname, socklen_t(hostname.count),
                                    nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        
        return address
    }
    
    // Check if device is connected to WiFi
    static func isConnectedToWiFi() -> Bool {
        return getIPAddress() != nil
    }
    
    // MARK: - UI Utilities
    
    // Keep screen on
    static func keepScreenOn(_ on: Bool) {
        UIApplication.shared.isIdleTimerDisabled = on
    }
    
    // Show alert on top view controller
    static func showAlert(title: String, message: String, buttonTitle: String = "OK") {
        DispatchQueue.main.async {
            if let topController = UIApplication.shared.windows.first?.rootViewController {
                let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: buttonTitle, style: .default, handler: nil))
                topController.present(alertController, animated: true, completion: nil)
            }
        }
    }
    
    // MARK: - File Management
    
    // Save image to photo library
    static func saveImageToPhotoLibrary(_ image: UIImage, completion: @escaping (Bool, Error?) -> Void) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        completion(true, nil)
    }
    
    // Create temporary file URL
    static func createTemporaryFileURL(withExtension ext: String) -> URL {
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return temporaryDirectoryURL.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }
}