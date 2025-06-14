enum AudioWithTranscriptState {
    case selectingFile      // Initial state - can select either audio or transcript first
    case selectingTranscript // Already have audio, need transcript
    case selectingAudio     // Already have transcript, need audio
}