import SwiftUI

struct ContentView: View {
    @State private var selectedMode: MonitorMode? = nil
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Baby Monitor")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Image(systemName: "video.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text("Select Mode")
                    .font(.title2)
                
                VStack(spacing: 20) {
                    NavigationLink(destination: MonitorView()) {
                        ModeSelectionButton(title: "Monitor Mode", systemImage: "camera.fill", description: "Place this device near the baby")
                    }
                    
                    NavigationLink(destination: ViewerView()) {
                        ModeSelectionButton(title: "Viewer Mode", systemImage: "eye.fill", description: "Watch the baby on this device")
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct ModeSelectionButton: View {
    let title: String
    let systemImage: String
    let description: String
    
    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .frame(width: 60, height: 60)
                .foregroundColor(.white)
                .background(Color.blue)
                .clipShape(Circle())
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.blue)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

enum MonitorMode {
    case monitor
    case viewer
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}