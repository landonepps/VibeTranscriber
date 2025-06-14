import Foundation
import AVFoundation
import UniformTypeIdentifiers

@MainActor
class TranscriptionViewModel: ObservableObject {
    @Published var status: TranscriptionStatus = .idle
    @Published var result: TranscriptionResult?
    @Published var progress: Double = 0.0

    private var recognizer: SherpaOnnxOfflineRecognizer?
    private var diarization: SherpaOnnxOfflineSpeakerDiarizationWrapper?
    private var currentSpeakerCount: Int = 0
    private var currentThreshold: Double = 0.6

    init() {
        setupRecognizer()
        Task {
            // Actually handle this?
            try await setupDiarization()
        }
    }

    // MARK: - Setup

    private func setupRecognizer() {
        let modelConfig = getNemoParakeetEn()
        let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80)

        var config = sherpaOnnxOfflineRecognizerConfig(
            featConfig: featConfig,
            modelConfig: modelConfig,
            decodingMethod: "greedy_search",
            maxActivePaths: 4
        )

        recognizer = SherpaOnnxOfflineRecognizer(config: &config)
    }

    private func setupDiarization(speakerCount: Int = 0, threshold: Double = 0.7) async throws {
        let segmentationModelPath = getResource("model.int8", "onnx")
        let embeddingModelPath = getResource("nemo_en_titanet_large", "onnx")
        
        print("🔧 Setting up speaker diarization...")
        print("   Segmentation model: \(segmentationModelPath)")
        print("   Embedding model: \(embeddingModelPath)")
        print("   Expected speakers: \(speakerCount == 0 ? "auto-detect" : "\(speakerCount)")")
        print("   Clustering threshold: \(threshold)")

        let segmentationConfig = sherpaOnnxOfflineSpeakerSegmentationPyannoteModelConfig(
            model: segmentationModelPath
        )

        let segmentationModelConfig = sherpaOnnxOfflineSpeakerSegmentationModelConfig(
            pyannote: segmentationConfig,
            numThreads: 8,
            debug: 0,
            provider: "coreml"
        )

        let embeddingConfig = sherpaOnnxSpeakerEmbeddingExtractorConfig(
            model: embeddingModelPath,
            numThreads: 8,
            debug: 0,
            provider: "coreml"
        )

        let clusteringConfig = sherpaOnnxFastClusteringConfig(
            numClusters: speakerCount == 0 ? -1 : speakerCount,  // Use specified count or auto-detect
            threshold: Float(threshold)
        )

        let diarizationConfig = sherpaOnnxOfflineSpeakerDiarizationConfig(
            segmentation: segmentationModelConfig,
            embedding: embeddingConfig,
            clustering: clusteringConfig,
            minDurationOn: 0.3,
            minDurationOff: 0.5
        )

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var config = diarizationConfig
                let diarizationWrapper = SherpaOnnxOfflineSpeakerDiarizationWrapper(config: &config)
                DispatchQueue.main.async {
                    self.diarization = diarizationWrapper
                    print("✅ Speaker diarization initialized successfully")
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - File Processing

    func processAudioFile(url: URL, expectedSpeakerCount: Int = 0, clusteringThreshold: Double = 0.6) async throws {
        await MainActor.run {
            status = .loadingFile
            progress = 0.0
            print("Starting audio processing...")
        }
        do {
            // Reconfigure diarization if parameters have changed
            if expectedSpeakerCount != currentSpeakerCount || clusteringThreshold != currentThreshold {
                try await setupDiarization(speakerCount: expectedSpeakerCount, threshold: clusteringThreshold)
                currentSpeakerCount = expectedSpeakerCount
                currentThreshold = clusteringThreshold
            }

            // Load and validate audio file
            let audioInfo = try await loadAudioFile(url: url)
            progress = 0.1

            // Convert audio to the required format
            let audioSamples = try await convertAudioToSamples(url: url)
            progress = 0.2

            // Process speaker diarization
            status = .processingDiarization
            let speakerSegments = await processSpeakerDiarization(samples: audioSamples)
            progress = 0.5

            // Process transcription for each speaker segment
            status = .processingTranscription
            let transcribedSegments = await transcribeSegments(segments: speakerSegments, samples: audioSamples)
            progress = 0.9

            // Combine results
            status = .combining
            let finalResult = TranscriptionResult(
                segments: transcribedSegments,
                audioFileName: audioInfo.fileName,
                audioFileURL: audioInfo.url,
                processingDate: Date(),
                totalDuration: audioInfo.duration,
                uniqueSpeakerCount: Set(speakerSegments.map { $0.speaker }).count
            )

            result = finalResult
            status = .completed
            progress = 1.0

        } catch {
            print("Error: \(error.localizedDescription)")
            status = .failed(error.localizedDescription)
            progress = 0.0
        }
    }

    private func loadAudioFile(url: URL) async throws -> AudioFileInfo {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration).seconds

        guard !duration.isNaN && duration > 0 else {
            throw TranscriptionError.invalidAudioFile
        }

        let audioInfo = AudioFileInfo(
            url: url,
            fileName: url.lastPathComponent,
            duration: duration,
            sampleRate: 16000, // We'll convert to this
            channelCount: 1     // We'll convert to mono
        )

        return audioInfo
    }

    private func convertAudioToSamples(url: URL) async throws -> [Float] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    guard let file = try? AVAudioFile(forReading: url) else {
                        throw TranscriptionError.processingFailed
                    }
                    guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                     sampleRate: 16000,
                                                     channels: 1,
                                                     interleaved: false) else {
                        throw TranscriptionError.processingFailed
                    }

                    guard let converter = AVAudioConverter(from: file.processingFormat,
                                                           to: outputFormat) else {
                        throw TranscriptionError.processingFailed
                    }

                    // Calculate output buffer size based on conversion ratio
                    let inputSampleRate = file.processingFormat.sampleRate
                    let outputSampleRate = outputFormat.sampleRate
                    let ratio = outputSampleRate / inputSampleRate
                    let outputFrameCount = AVAudioFrameCount(Double(file.length) * ratio)

                    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                                              frameCapacity: outputFrameCount) else {
                        throw TranscriptionError.processingFailed
                    }

                    var error: NSError?
                    let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                           frameCapacity: 1024) else {
                            outStatus.pointee = .noDataNow
                            return nil
                        }
                        do {
                            try file.read(into: inputBuffer)
                            if inputBuffer.frameLength == 0 {
                                outStatus.pointee = .noDataNow
                                return nil
                            }
                            outStatus.pointee = .haveData
                            return inputBuffer
                        } catch {
                            outStatus.pointee = .noDataNow
                            return nil
                        }
                    }

                    let status = converter.convert(to: outputBuffer, error: &error,
                                                   withInputFrom: inputBlock)

                    if let error = error {
                        throw error
                    }

                    guard status != .error else {
                        throw TranscriptionError.processingFailed
                    }

                    let samples = outputBuffer.array()
                    continuation.resume(returning: samples)

                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func processSpeakerDiarization(samples: [Float]) async -> [SherpaOnnxOfflineSpeakerDiarizationSegmentWrapper] {
        let diarizationEngine = diarization

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // If diarization is available, use it
                if let diarizationEngine = diarizationEngine {
                    let segments = diarizationEngine.process(samples: samples)
                    continuation.resume(returning: segments)
                } else {
                    // Fallback: create a single segment for the entire audio
                    let fallbackSegment = SherpaOnnxOfflineSpeakerDiarizationSegmentWrapper(
                        start: 0.0,
                        end: Float(samples.count) / 16000.0, // Convert samples to seconds
                        speaker: 0
                    )
                    continuation.resume(returning: [fallbackSegment])
                }
            }
        }
    }

    private func transcribeSegments(segments: [SherpaOnnxOfflineSpeakerDiarizationSegmentWrapper], samples: [Float]) async -> [SpeakerSegment] {
        var result: [SpeakerSegment] = []

        for (index, segment) in segments.enumerated() {
            await updateProgress(0.6 + (0.3 * Double(index) / Double(segments.count)))

            // Extract audio samples for this segment
            let startSample = Int(segment.start * 16000)
            let endSample = Int(segment.end * 16000)
            let segmentSamples = Array(samples[startSample..<min(endSample, samples.count)])

            // Transcribe this segment
            if let recognizer = recognizer {
                let transcriptionResult = recognizer.decode(samples: segmentSamples)
                let text = transcriptionResult.text.trimmingCharacters(in: .whitespacesAndNewlines)

                if !text.isEmpty {
                    let speakerSegment = SpeakerSegment(
                        startTime: Double(segment.start),
                        endTime: Double(segment.end),
                        speakerId: segment.speaker,
                        text: text
                    )
                    result.append(speakerSegment)
                }
            }
        }

        return result
    }

    private func updateProgress(_ value: Double) async {
        await MainActor.run {
            self.progress = value
        }
    }

    // MARK: - Export & Persistence

    func exportTranscription() -> String? {
        return result?.formattedTranscript
    }
    
    func saveTranscription(to url: URL) throws {
        guard let result = result else { return }
        let data = try JSONEncoder().encode(result)
        try data.write(to: url)
    }
    
    func loadTranscription(from url: URL) throws -> TranscriptionResult {
        let data = try Data(contentsOf: url)
        
        // Try JSON first
        if let transcriptionResult = try? JSONDecoder().decode(TranscriptionResult.self, from: data) {
            self.result = transcriptionResult
            self.status = .completed
            self.progress = 1.0
            return transcriptionResult
        }
        
        // Fallback to text format
        let content = String(data: data, encoding: .utf8) ?? ""
        let transcriptionResult = try parseTextTranscription(content: content, originalURL: url)
        self.result = transcriptionResult
        self.status = .completed
        self.progress = 1.0
        return transcriptionResult
    }
    
    func loadAudioWithTranscription(audioURL: URL, transcriptionURL: URL) throws {
        try loadTranscription(from: transcriptionURL)
        
        // Update the audio file URL if it's different
        if let result = result, result.audioFileURL != audioURL {
            let updatedResult = TranscriptionResult(
                segments: result.segments,
                audioFileName: audioURL.lastPathComponent,
                audioFileURL: audioURL,
                processingDate: result.processingDate,
                totalDuration: result.totalDuration,
                uniqueSpeakerCount: result.uniqueSpeakerCount
            )
            self.result = updatedResult
        }
    }

    private func parseTextTranscription(content: String, originalURL: URL) throws -> TranscriptionResult {
        let lines = content.components(separatedBy: .newlines)
        var segments: [SpeakerSegment] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            // Parse format: [startTime - endTime] Speaker X: text
            if let range = trimmed.range(of: #"\[(\d{2}:\d{2}\.\d{2}) - (\d{2}:\d{2}\.\d{2})\] Speaker (\d+): (.+)"#, options: .regularExpression) {
                let match = String(trimmed[range])
                let regex = try NSRegularExpression(pattern: #"\[(\d{2}:\d{2}\.\d{2}) - (\d{2}:\d{2}\.\d{2})\] Speaker (\d+): (.+)"#)
                let nsString = match as NSString
                
                if let result = regex.firstMatch(in: match, range: NSRange(location: 0, length: nsString.length)) {
                    let startTimeStr = nsString.substring(with: result.range(at: 1))
                    let endTimeStr = nsString.substring(with: result.range(at: 2))
                    let speakerIdStr = nsString.substring(with: result.range(at: 3))
                    let text = nsString.substring(with: result.range(at: 4))
                    
                    if let startTime = parseTime(startTimeStr),
                       let endTime = parseTime(endTimeStr),
                       let speakerId = Int(speakerIdStr) {
                        
                        let segment = SpeakerSegment(
                            startTime: startTime,
                            endTime: endTime,
                            speakerId: speakerId - 1, // Convert to 0-based
                            text: text
                        )
                        segments.append(segment)
                    }
                }
            }
        }
        
        guard !segments.isEmpty else {
            throw TranscriptionError.processingFailed
        }
        
        let totalDuration = segments.map { $0.endTime }.max() ?? 0.0
        let uniqueSpeakers = Set(segments.map { $0.speakerId }).count
        
        return TranscriptionResult(
            segments: segments,
            audioFileName: originalURL.deletingPathExtension().lastPathComponent,
            audioFileURL: originalURL, // This will need to be updated later
            processingDate: Date(),
            totalDuration: totalDuration,
            uniqueSpeakerCount: uniqueSpeakers
        )
    }
    
    private func parseTime(_ timeString: String) -> Double? {
        let components = timeString.components(separatedBy: ":")
        guard components.count == 2 else { return nil }
        
        let minutes = Double(components[0]) ?? 0
        let seconds = Double(components[1]) ?? 0
        
        return minutes * 60 + seconds
    }
    
    func reset() {
        status = .idle
        result = nil
        progress = 0.0
    }
    
    func setSpeakerName(_ name: String, for speakerId: Int) {
        guard var currentResult = result else { return }
        currentResult.setSpeakerName(name, for: speakerId)
        result = currentResult
    }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case invalidAudioFile
    case processingFailed
    case noRecognizer

    var errorDescription: String? {
        switch self {
        case .invalidAudioFile:
            return "Invalid or corrupted audio file"
        case .processingFailed:
            return "Failed to process audio"
        case .noRecognizer:
            return "Speech recognizer not available"
        }
    }
}
