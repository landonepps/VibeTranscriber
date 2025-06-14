import Foundation

// MARK: - Data Models

struct SpeakerSegment: Identifiable, Hashable, Codable {
    let id = UUID()
    let startTime: Double
    let endTime: Double
    let speakerId: Int
    let text: String
    
    var duration: Double {
        endTime - startTime
    }
    
    func speakerName(from result: TranscriptionResult? = nil) -> String {
        return result?.speakerName(for: speakerId) ?? "Speaker \(speakerId + 1)"
    }
    
    var timeRange: String {
        let start = formatTime(startTime)
        let end = formatTime(endTime)
        return "\(start) - \(end)"
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let millisecs = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, secs, millisecs)
    }
}

struct TranscriptionResult: Codable {
    let segments: [SpeakerSegment]
    let audioFileName: String
    let audioFileURL: URL
    let processingDate: Date
    let totalDuration: Double
    let uniqueSpeakerCount: Int
    var speakerNames: [Int: String] = [:]
    
    var formattedTranscript: String {
        segments.map { segment in
            let speakerName = speakerNames[segment.speakerId] ?? "Speaker \(segment.speakerId + 1)"
            return "[\(segment.timeRange)] \(speakerName): \(segment.text)"
        }.joined(separator: "\n\n")
    }
    
    func speakerName(for speakerId: Int) -> String {
        return speakerNames[speakerId] ?? "Speaker \(speakerId + 1)"
    }
    
    mutating func setSpeakerName(_ name: String, for speakerId: Int) {
        speakerNames[speakerId] = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TranscriptionStatus {
    case idle
    case loadingFile
    case processingDiarization
    case processingTranscription
    case combining
    case completed
    case failed(String)
    
    var description: String {
        switch self {
        case .idle: return "Ready"
        case .loadingFile: return "Loading audio file..."
        case .processingDiarization: return "Identifying speakers..."
        case .processingTranscription: return "Transcribing speech..."
        case .combining: return "Combining results..."
        case .completed: return "Completed"
        case .failed(let error): return "Error: \(error)"
        }
    }
    
    var isProcessing: Bool {
        switch self {
        case .idle, .completed, .failed: return false
        default: return true
        }
    }
}

// MARK: - Audio Processing

struct AudioFileInfo {
    let url: URL
    let fileName: String
    let duration: Double
    let sampleRate: Double
    let channelCount: Int
}
