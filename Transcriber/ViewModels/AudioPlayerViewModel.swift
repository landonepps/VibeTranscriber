import Foundation
import AVFoundation
import Combine

@MainActor
class AudioPlayerViewModel: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var currentSegmentId: UUID?
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var audioURL: URL?
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    deinit {
        timer?.invalidate()
        audioPlayer?.stop()
    }
    
    // MARK: - Audio Session Setup
    
    private func setupAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
        #elseif os(macOS)
        // macOS doesn't require explicit audio session setup
        // AVAudioPlayer handles audio routing automatically
        #endif
    }
    
    // MARK: - Audio File Loading
    
    func loadAudioFile(url: URL) {
        do {
            // Stop current playback
            stop()
            
            // Create new audio player
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            
            // Update duration
            duration = audioPlayer?.duration ?? 0
            currentTime = 0
            audioURL = url
            
        } catch {
            print("Failed to load audio file: \(error)")
        }
    }
    
    // MARK: - Playback Controls
    
    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func play() {
        guard let player = audioPlayer else { return }
        
        player.play()
        isPlaying = true
        startTimer()
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentTime = 0
        currentSegmentId = nil
        stopTimer()
    }
    
    func reset() {
        stop()
        audioPlayer = nil
        audioURL = nil
        duration = 0
        cachedSegments = []
    }
    
    // MARK: - Seeking
    
    func seek(to time: Double) {
        guard let player = audioPlayer else { return }
        
        let clampedTime = max(0, min(time, duration))
        player.currentTime = clampedTime
        currentTime = clampedTime
        
        updateCurrentSegment()
    }
    
    func jumpToTimestamp(_ timestamp: Double, segmentId: UUID, segments: [SpeakerSegment]) {
        seek(to: timestamp)
        currentSegmentId = segmentId
        
        if !isPlaying {
            play()
        }
    }
    
    // MARK: - Timer Management
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCurrentTime()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateCurrentTime() {
        guard let player = audioPlayer else { return }
        currentTime = player.currentTime
        updateCurrentSegment()
    }
    
    // MARK: - Segment Tracking
    
    private var cachedSegments: [SpeakerSegment] = []
    
    func updateSegments(_ segments: [SpeakerSegment]) {
        cachedSegments = segments
        updateCurrentSegment()
    }
    
    private func updateCurrentSegment() {
        let currentSegment = cachedSegments.first { segment in
            currentTime >= segment.startTime && currentTime <= segment.endTime
        }
        
        if currentSegmentId != currentSegment?.id {
            currentSegmentId = currentSegment?.id
        }
    }
    
    // MARK: - Utility
    
    var isLoaded: Bool {
        audioPlayer != nil
    }
    
    var formattedCurrentTime: String {
        formatTime(currentTime)
    }
    
    var formattedDuration: String {
        formatTime(duration)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlayerViewModel: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
            currentTime = 0
            currentSegmentId = nil
            stopTimer()
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            print("Audio player decode error: \(error?.localizedDescription ?? "Unknown error")")
            isPlaying = false
            stopTimer()
        }
    }
}
