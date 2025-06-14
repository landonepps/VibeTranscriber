import SwiftUI

struct AudioPlayerView: View {
    @ObservedObject var playerViewModel: AudioPlayerViewModel
    let segments: [SpeakerSegment]
    let result: TranscriptionResult?
    
    @State private var isDraggingSlider = false
    @State private var sliderValue: Double = 0
    
    var body: some View {
        VStack(spacing: 16) {
            // Audio file info
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.blue)
                
                Text("Audio Player")
                    .font(.headline)
                
                Spacer()
                
                if playerViewModel.isLoaded {
                    Text(playerViewModel.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if playerViewModel.isLoaded {
                // Progress slider
                VStack(spacing: 8) {
                    HStack {
                        Text(playerViewModel.formattedCurrentTime)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .leading)
                        
                        Slider(
                            value: isDraggingSlider ? $sliderValue : .constant(playerViewModel.currentTime),
                            in: 0...playerViewModel.duration,
                            onEditingChanged: { editing in
                                isDraggingSlider = editing
                                if !editing {
                                    playerViewModel.seek(to: sliderValue)
                                }
                            }
                        )
                        .accentColor(.blue)
                        .onChange(of: playerViewModel.currentTime) { newValue in
                            if !isDraggingSlider {
                                sliderValue = newValue
                            }
                        }
                        
                        Text(playerViewModel.formattedDuration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    
                    // Current segment indicator
                    if let currentSegmentId = playerViewModel.currentSegmentId,
                       let currentSegment = segments.first(where: { $0.id == currentSegmentId }) {
                        Text("Playing: \(currentSegment.speakerName(from: result))")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                
                // Playback controls
                HStack(spacing: 20) {
                    // Skip backward 15s
                    Button(action: {
                        let newTime = max(0, playerViewModel.currentTime - 15)
                        playerViewModel.seek(to: newTime)
                    }) {
                        Image(systemName: "gobackward.15")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Play/Pause
                    Button(action: {
                        playerViewModel.togglePlayback()
                    }) {
                        Image(systemName: playerViewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Skip forward 15s
                    Button(action: {
                        let newTime = min(playerViewModel.duration, playerViewModel.currentTime + 15)
                        playerViewModel.seek(to: newTime)
                    }) {
                        Image(systemName: "goforward.15")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Playback speed control
                HStack {
                    Text("Speed:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("0.5x") {
                        setPlaybackRate(0.5)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    
                    Button("1x") {
                        setPlaybackRate(1.0)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    
                    Button("1.5x") {
                        setPlaybackRate(1.5)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    
                    Button("2x") {
                        setPlaybackRate(2.0)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.top, 8)
                
            } else {
                // No audio loaded state
                VStack(spacing: 8) {
                    Image(systemName: "speaker.slash")
                        .font(.title)
                        .foregroundColor(.secondary)
                    
                    Text("No audio file loaded")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 20)
            }
        }
        .padding()
        .background(Color.gray.quaternary)
        .cornerRadius(12)
        .onAppear {
            playerViewModel.updateSegments(segments)
        }
        .onChange(of: segments) { newSegments in
            playerViewModel.updateSegments(newSegments)
        }
    }
    
    // MARK: - Private Methods
    
    private func setPlaybackRate(_ rate: Float) {
        // Note: AVAudioPlayer doesn't support playback rate changes directly
        // This would require AVAudioEngine for advanced playback features
        // For now, this is a placeholder for future enhancement
        print("Playback rate change to \(rate)x requested - not currently supported")
    }
}

#Preview {
    let playerViewModel = AudioPlayerViewModel()
    let sampleSegments = [
        SpeakerSegment(startTime: 0, endTime: 10, speakerId: 0, text: "Hello, this is a test."),
        SpeakerSegment(startTime: 10, endTime: 20, speakerId: 1, text: "Yes, this is another speaker.")
    ]
    
    return AudioPlayerView(playerViewModel: playerViewModel, segments: sampleSegments, result: nil)
        .padding()
}
