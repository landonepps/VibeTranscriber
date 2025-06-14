# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Transcriber is an iOS/macOS SwiftUI app for Automatic Speech Recognition (ASR) using sherpa-onnx library with pre-trained models. The app performs both offline transcription and speaker diarization.

## Build Commands

```bash
# Build the project
xcodebuild -project Transcriber.xcodeproj -scheme SherpaOnnx -configuration Debug

# Run tests
xcodebuild test -project Transcriber.xcodeproj -scheme SherpaOnnx

# Run only unit tests
xcodebuild test -project Transcriber.xcodeproj -scheme SherpaOnnx -only-testing:TranscriberTests

# Run only UI tests
xcodebuild test -project Transcriber.xcodeproj -scheme SherpaOnnx -only-testing:TranscriberUITests
```

## Architecture

### Core Components
- **TranscriptionViewModel.swift**: Main business logic for offline transcription and speaker diarization
- **AudioPlayerViewModel.swift**: Audio playback control, timestamp navigation, and segment tracking
- **SherpaOnnx.swift**: Swift wrapper for C API, provides recognizer classes and configuration builders
- **TranscriptionView.swift**: SwiftUI interface for transcription controls and results display
- **AudioPlayerView.swift**: Audio playback controls with play/pause, seeking, and progress display
- **ModelConfigurations.swift**: ASR model configurations (currently focused on Nemo Parakeet)

### Processing Pipeline
1. File input/selection → 2. Convert to 16kHz mono float32 → 3. Offline recognizer (batch processing) → 4. Speaker diarization → 5. Combined transcription with speaker labels → 6. Audio playback with timestamp navigation

### Framework Dependencies
- **sherpa-onnx.xcframework**: Core ASR library (C/C++)
- **onnxruntime.xcframework**: ONNX Runtime for neural network inference
- Pre-trained models in `/Transcriber/Resources/Models/` directory

## Key Configurations

### Audio Processing Requirements
- Sample Rate: 16000 Hz, Feature Dimension: 80
- Input: Audio files (WAV, MP3, etc.) for both transcription and playback
- Single-threaded processing for model compatibility
- AVAudioPlayer for audio playback with timestamp seeking

### Model Configuration
- Default: Nemo Parakeet (offline transcription) + Reverb Diarization (speaker identification)
- Models configured in `ModelConfigurations.swift`
- Models must be included in "Copy Bundle Resources" build phase

### C API Integration
- Bridging header: `/Transcriber/Core/SherpaOnnx/Headers/SherpaOnnx-Bridging-Header.h`
- C API headers in `/Transcriber/Core/SherpaOnnx/Headers/sherpa-onnx/`

## Development Notes

- Targets iOS 13.0+/macOS 10.15+, requires Xcode 16+
- Test files exist but contain minimal boilerplate - no actual tests implemented
- CPU-based inference, models are INT8 quantized for efficiency
- Bundle resources include both ASR and diarization models

## Audio Playback Features

### Implemented
- Play/pause audio with transcript synchronization
- Tap transcript segments to jump to specific timestamps
- Real-time progress tracking with visual segment highlighting
- Skip forward/backward 15 seconds
- Progress slider for manual seeking

### Known Limitations
- Playback speed controls are UI-only (non-functional) - requires AVAudioEngine
- Limited error handling for unsupported audio formats
- No background audio or remote control support