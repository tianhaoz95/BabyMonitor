import SwiftUI
import AVFoundation

struct MonitorView: View {
    @StateObject private var viewModel = MonitorViewModel()
    @Environment(\.presentationMode) var presentationMode
    @State private var isShowingSettings = false
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(session: viewModel.session)
                .edgesIgnoringSafeArea(.all)
            
            // Overlay controls
            VStack {
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        isShowingSettings.toggle()
                    }) {
                        Image(systemName: "gear")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                }
                .padding()
                
                Spacer()
                
                // Connection status
                VStack {
                    if viewModel.isStreaming {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 10, height: 10)
                            Text("Streaming")
                                .foregroundColor(.white)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(20)
                    } else {
                        HStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                            Text("Not Connected")
                                .foregroundColor(.white)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(20)
                    }
                    
                    // Controls
                    HStack(spacing: 30) {
                        Button(action: {
                            viewModel.toggleTorch()
                        }) {
                            Image(systemName: viewModel.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding()
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        }
                        
                        Button(action: {
                            viewModel.toggleStreaming()
                        }) {
                            Image(systemName: viewModel.isStreaming ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(viewModel.isStreaming ? .red : .green)
                                .padding()
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        }
                        
                        Button(action: {
                            viewModel.switchCamera()
                        }) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding()
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        }
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            viewModel.checkPermissions()
            viewModel.setupSession()
        }
        .onDisappear {
            viewModel.stopSession()
        }
        .sheet(isPresented: $isShowingSettings) {
            MonitorSettingsView(viewModel: viewModel)
        }
        .alert(isPresented: $viewModel.showAlert) {
            Alert(title: Text(viewModel.alertTitle), 
                  message: Text(viewModel.alertMessage), 
                  dismissButton: .default(Text("OK")))
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct MonitorSettingsView: View {
    @ObservedObject var viewModel: MonitorViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Connection")) {
                    Text("Device ID: \(viewModel.deviceID)")
                    
                    Toggle("Auto-connect on start", isOn: $viewModel.autoConnect)
                }
                
                Section(header: Text("Camera")) {
                    Toggle("Night vision mode", isOn: $viewModel.nightVisionMode)
                        .onChange(of: viewModel.nightVisionMode) { newValue in
                            if newValue {
                                viewModel.enableTorch()
                            } else {
                                viewModel.disableTorch()
                            }
                        }
                    
                    Toggle("High quality stream", isOn: $viewModel.highQualityStream)
                }
                
                Section(header: Text("Audio")) {
                    Toggle("Enable microphone", isOn: $viewModel.microphoneEnabled)
                }
            }
            .navigationTitle("Monitor Settings")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

struct MonitorView_Previews: PreviewProvider {
    static var previews: some View {
        MonitorView()
    }
}