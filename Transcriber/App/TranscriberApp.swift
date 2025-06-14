import SwiftUI

@main
struct TranscriberApp: App {
    var body: some Scene {
        WindowGroup {
            TranscriptionView()
                #if os(macOS)
                .frame(minWidth: 800, minHeight: 600, maxHeight: .infinity)
                #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        #endif
        
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

#if os(macOS)
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            AudioSettingsView()
                .tabItem {
                    Label("Audio", systemImage: "speaker.wave.2")
                }
        }
        .padding()
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General Settings")
                .font(.headline)
            
            Text("Configure general application settings")
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
    }
}

struct AudioSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio Settings")
                .font(.headline)
            
            Text("Configure audio processing settings")
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
    }
}
#endif
