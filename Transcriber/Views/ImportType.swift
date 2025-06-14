import UniformTypeIdentifiers

enum ImportType {
    case audio
    case transcription
    case audioForTranscription
    case audioWithTranscript
    
    var allowedTypes: [UTType] {
        switch self {
        case .audio, .audioForTranscription:
            return [.audio, .video]
        case .transcription:
            return [.json, .plainText]
        case .audioWithTranscript:
            return [.audio, .video, .json, .plainText]
        }
    }
}