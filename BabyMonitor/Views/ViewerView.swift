import SwiftUI
import MultipeerConnectivity

struct ViewerView: View {
    @StateObject private var viewModel = ViewerViewModel()
    @Environment(\.presentationMode) var presentationMode
    @State private var isShowingSettings = false
    
    var body: some View {
        ZStack {
            // Video display
            if let image = viewModel.currentFrame {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .rotationEffect(.degrees(90))
                    .scaleEffect(x: -1, y: 1)
                    .edgesIgnoringSafeArea(.all)
            } else {
                Color.black
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    if viewModel.isSearching {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        
                        Text("Searching for monitors...")
                            .foregroundColor(.white)
                            .padding(.top)
                    } else {
                        Image(systemName: "video.slash.fill")
                            .font(.system(size: 70))
                            .foregroundColor(.white)
                        
                        Text("No monitor connected")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(.top)
                        
                        Button(action: {
                            viewModel.startBrowsing()
                        }) {
                            Text("Search for Monitors")
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        .padding(.top, 20)
                    }
                }
            }
            
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
                
                // Connection status and controls
                VStack {
                    if viewModel.isConnected {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 10, height: 10)
                            Text("Connected to \(viewModel.connectedPeerName)")
                                .foregroundColor(.white)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(20)
                        
                        // Controls
                        HStack(spacing: 30) {
                            Button(action: {
                                viewModel.toggleMute()
                            }) {
                                Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Circle().fill(Color.black.opacity(0.6)))
                            }
                            
                            Button(action: {
                                viewModel.takeSnapshot()
                            }) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Circle().fill(Color.black.opacity(0.6)))
                            }
                            
                            Button(action: {
                                viewModel.disconnect()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.red)
                                    .padding()
                                    .background(Circle().fill(Color.black.opacity(0.6)))
                            }
                        }
                    } else if !viewModel.isSearching {
                        Button(action: {
                            viewModel.startBrowsing()
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Search Again")
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(Color.blue)
                            .cornerRadius(20)
                        }
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            viewModel.startBrowsing()
        }
        .onDisappear {
            viewModel.stopBrowsing()
            viewModel.disconnect()
        }
        .sheet(isPresented: $isShowingSettings) {
            ViewerSettingsView(viewModel: viewModel)
        }
        .alert(isPresented: $viewModel.showAlert) {
            Alert(title: Text(viewModel.alertTitle), 
                  message: Text(viewModel.alertMessage), 
                  dismissButton: .default(Text("OK")))
        }
    }
}

struct ViewerSettingsView: View {
    @ObservedObject var viewModel: ViewerViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Connection")) {
                    Toggle("Auto-connect to last monitor", isOn: $viewModel.autoConnect)
                    
                    if !viewModel.knownMonitors.isEmpty {
                        Picker("Known Monitors", selection: $viewModel.selectedMonitor) {
                            Text("None").tag("")
                            ForEach(viewModel.knownMonitors, id: \.self) { monitor in
                                Text(monitor).tag(monitor)
                            }
                        }
                    }
                }
                
                Section(header: Text("Audio")) {
                    Toggle("Mute audio", isOn: $viewModel.isMuted)
                    
                    if !viewModel.isMuted {
                        HStack {
                            Text("Volume")
                            Slider(value: $viewModel.volume, in: 0...1)
                        }
                    }
                }
                
                Section(header: Text("Video")) {
                    Toggle("Keep screen on", isOn: $viewModel.keepScreenOn)
                }
                
                Section(header: Text("Notifications")) {
                    Toggle("Sound alerts", isOn: $viewModel.soundAlerts)
                    Toggle("Motion detection", isOn: $viewModel.motionDetection)
                }
            }
            .navigationTitle("Viewer Settings")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

struct ViewerView_Previews: PreviewProvider {
    static var previews: some View {
        ViewerView()
    }
}