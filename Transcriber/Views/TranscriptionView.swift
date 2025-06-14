import SwiftUI
import UniformTypeIdentifiers

struct TranscriptionView: View {
    @StateObject private var viewModel = TranscriptionViewModel()
    @StateObject private var audioPlayerViewModel = AudioPlayerViewModel()
    @State private var showingFilePicker = false
    @State private var currentImportType: ImportType = .audio
    @State private var audioWithTranscriptState: AudioWithTranscriptState = .selectingFile
    @State private var showingExportSheet = false
    @State private var showingSaveSheet = false
    @State private var expectedSpeakerCount = 0 // 0 means auto-detect
    @State private var clusteringThreshold = 0.6
    @State private var showAdvancedSettings = false
    @State private var selectedFileURL: URL?
    @State private var securityScopedBookmarkData: Data?
    @State private var showingSpeakerRename = false
    @State private var renamingSpeakerId: Int = 0
    @State private var newSpeakerName = ""

    var body: some View {
        let _ = Self._printChanges()
        
        #if os(macOS)
        NavigationSplitView {
            // Sidebar for macOS
            sidebarContent
        } detail: {
            mainContent
        }
        .navigationSplitViewStyle(.balanced)
        #else
        NavigationView {
            mainContent
        }
        #endif
    }
    
    private var mainContent: some View {
        VStack(spacing: 20) {
            headerSection

            if viewModel.result == nil && !viewModel.status.isProcessing {
                fileImportSection
            } else {
                contentSection
            }

            // Start button section (only show when file is selected but not processing)
            if selectedFileURL != nil && viewModel.result == nil && !viewModel.status.isProcessing {
                startButtonSection
            }
        }
        .padding()
        .navigationTitle("Audio Transcription")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if viewModel.result != nil {
                    Button("Save") {
                        showingSaveSheet = true
                    }
                    .foregroundColor(.green)

                    Button("New File") {
                        resetForNewFile()
                    }
                    .foregroundColor(.blue)

                    Button("Export") {
                        showingExportSheet = true
                    }
                }
            }
            #else
            ToolbarItemGroup(placement: .automatic) {
                if viewModel.result != nil {
                    Button("Save") {
                        showingSaveSheet = true
                    }
                    .foregroundColor(.green)

                    Button("New File") {
                        resetForNewFile()
                    }
                    .foregroundColor(.blue)

                    Button("Export") {
                        showingExportSheet = true
                    }
                }
            }
            #endif
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: currentImportType.allowedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportView(transcription: viewModel.exportTranscription() ?? "")
        }
        .fileExporter(
            isPresented: $showingSaveSheet,
            document: TranscriptionDocument(transcription: viewModel.result),
            contentType: .json,
            defaultFilename: viewModel.result?.audioFileName.replacingOccurrences(of: ".", with: "_") ?? "transcription"
        ) { result in
            switch result {
            case .success(let url):
                print("Transcription saved to: \(url)")
            case .failure(let error):
                print("Save failed: \(error)")
            }
        }
        .overlay {
            if showingSpeakerRename {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showingSpeakerRename = false
                    }

                SpeakerRenameView(
                    speakerId: renamingSpeakerId,
                    currentName: viewModel.result?.speakerName(for: renamingSpeakerId) ?? "Speaker \(renamingSpeakerId + 1)",
                    newName: $newSpeakerName,
                    onSave: {
                        saveSpeakerName()
                    },
                    onCancel: {
                        showingSpeakerRename = false
                    }
                )
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "waveform.and.person.filled")
                    .font(.title2)
                    .foregroundColor(.blue)

                Text("Speaker-Aware Transcription")
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            Text("Upload an audio file to transcribe with speaker identification")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical)
    }

    // MARK: - File Import Section

    private var fileImportSection: some View {
        VStack(spacing: 24) {
            // Drop zone
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [8]))
                .frame(height: 120)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.badge.plus")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)

                        Text("Drop audio file here")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("or tap to browse")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .onTapGesture {
                    showingFilePicker = true
                }

            // Supported formats
            VStack(alignment: .leading, spacing: 4) {
                Text("Supported Formats:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("MP3, WAV, M4A, FLAC, AAC")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Speaker Configuration
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Speaker Configuration")
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack {
                        Text("Expected Speakers:")
                            .font(.subheadline)

                        Spacer()

                        Picker("Speaker Count", selection: $expectedSpeakerCount) {
                            Text("Auto-detect").tag(0)
                            ForEach(2...10, id: \.self) { count in
                                Text("\(count) speakers").tag(count)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 140)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Clustering Sensitivity:")
                                .font(.subheadline)

                            Spacer()

                            Text(String(format: "%.1f", clusteringThreshold))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Slider(value: $clusteringThreshold, in: 0.3...0.9, step: 0.1)
                            .accentColor(.blue)

                        HStack {
                            Text("More sensitive")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("Less sensitive")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Helpful note
                    VStack(alignment: .leading, spacing: 4) {
                        Text("💡 Tip for better results:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)

                        Text("Set expected speaker count to avoid over-detection. Use higher sensitivity (0.8-0.9) if same speaker appears as multiple people.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
                .background(Color.gray.quaternary)
                .cornerRadius(8)
            }

            // Divider with "or" text
            HStack {
                VStack { Divider() }
                Text("or")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                VStack { Divider() }
            }

            // Import options
            HStack(spacing: 12) {
                // Load audio + transcript
                Button(action: {
                    currentImportType = .audioWithTranscript
                    showingFilePicker = true
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "waveform.path.ecg.text.page")
                            .font(.title2)
                        Text("Audio + Transcript")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .cornerRadius(12)
                }

                // Open saved transcription only
                Button(action: {
                    currentImportType = .transcription
                    showingFilePicker = true
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.title2)
                        Text("Transcript Only")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(12)
                }
            }

            // Selected file info
            if let selectedFileURL = selectedFileURL {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected File:")
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.blue)

                        Text(selectedFileURL.lastPathComponent)
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Spacer()

                        Button("Change") {
                            showingFilePicker = true
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
                .padding()
                .background(Color.gray.quaternary)
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Start Button Section

    private var startButtonSection: some View {
        VStack(spacing: 16) {
            Button {
                startTranscription()
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                        .font(.title2)

                    Text("Start Transcription")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }

            Button("Cancel") {
                selectedFileURL = nil
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Content Section

    private var contentSection: some View {
        VStack(spacing: 20) {
            // Status and Progress
            statusSection

            // Results
            if let result = viewModel.result {
                resultsSection(result: result)
            }
        }
    }

    private var statusSection: some View {
        VStack(spacing: 12) {
            HStack {
                if viewModel.status.isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                Text(viewModel.status.description)
                    .font(.subheadline)
                    .foregroundColor(viewModel.status.isProcessing ? .blue : .primary)

                Spacer()

                if viewModel.status.isProcessing {
                    Text("\(Int(viewModel.progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if viewModel.status.isProcessing {
                ProgressView(value: viewModel.progress)
                    .progressViewStyle(LinearProgressViewStyle())
            }

            // Reset button
            if viewModel.result != nil, case .failed = viewModel.status {
                Button("Process New File") {
                    viewModel.reset()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.gray.quaternary)
        .cornerRadius(8)
    }

    private func resultsSection(result: TranscriptionResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary
            HStack {
                VStack(alignment: .leading) {
                    Text("File: \(result.audioFileName)")
                        .font(.headline)

                    HStack {
                        Text("Duration: \(formatDuration(result.totalDuration))")
                        Spacer()
                        Text("Speakers: \(result.uniqueSpeakerCount)")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(Color.gray.quaternary)
            .cornerRadius(8)

            // Audio Player
            AudioPlayerView(playerViewModel: audioPlayerViewModel, segments: result.segments, result: result)
                .onAppear {
                    audioPlayerViewModel.loadAudioFile(url: result.audioFileURL)
                }

            // Transcript
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(result.segments) { segment in
                        SpeakerSegmentView(
                            segment: segment,
                            result: result,
                            isCurrentlyPlaying: audioPlayerViewModel.currentSegmentId == segment.id,
                            onTap: {
                                audioPlayerViewModel.jumpToTimestamp(segment.startTime, segmentId: segment.id, segments: result.segments)
                            },
                            onRenameSpeaker: { speakerId in
                                renamingSpeakerId = speakerId
                                newSpeakerName = result.speakerName(for: speakerId)
                                showingSpeakerRename = true
                            }
                        )
                    }
                }
                .padding(.vertical)
            }
        }
    }

    // MARK: - Helper Methods

    private func resetForNewFile() {
        audioPlayerViewModel.reset()
        viewModel.reset()
        selectedFileURL = nil
        securityScopedBookmarkData = nil
    }

    private func startTranscription() {
        guard let url = selectedFileURL else { return }
        
        #if os(macOS)
        // Reacquire security-scoped resource access
        var isStale = false
        guard let bookmarkData = securityScopedBookmarkData,
              let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
              ),
              resolvedURL.startAccessingSecurityScopedResource() else {
            print("Failed to reacquire security-scoped resource access")
            return
        }
        defer { resolvedURL.stopAccessingSecurityScopedResource() }
        #endif

        Task {
            do {
                #if os(macOS)
                try await viewModel.processAudioFile(
                    url: resolvedURL,
                    expectedSpeakerCount: expectedSpeakerCount,
                    clusteringThreshold: clusteringThreshold
                )
                #else
                try await viewModel.processAudioFile(
                    url: url,
                    expectedSpeakerCount: expectedSpeakerCount,
                    clusteringThreshold: clusteringThreshold
                )
                #endif
            } catch {
                print("Failed to process audio file: \(error)")
            }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                switch currentImportType {
                case .audio:
                    #if os(macOS)
                    guard url.startAccessingSecurityScopedResource() else {
                        print("Failed to access security-scoped resource")
                        return
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    
                    do {
                        securityScopedBookmarkData = try url.bookmarkData(
                            options: .withSecurityScope,
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        )
                        selectedFileURL = url
                    } catch {
                        print("Failed to create security-scoped bookmark: \(error)")
                    }
                    #else
                    selectedFileURL = url
                    #endif
                case .transcription:
                    do {
                        let result = try viewModel.loadTranscription(from: url)
                        if FileManager.default.fileExists(atPath: result.audioFileURL.path) {
                            audioPlayerViewModel.loadAudioFile(url: result.audioFileURL)
                        } else {
                            currentImportType = .audioForTranscription
                            showingFilePicker = true
                        }
                    } catch {
                        print("Failed to load transcription: \(error)")
                    }
                case .audioForTranscription:
                    if let currentResult = viewModel.result {
                        let updatedResult = TranscriptionResult(
                            segments: currentResult.segments,
                            audioFileName: url.lastPathComponent,
                            audioFileURL: url,
                            processingDate: currentResult.processingDate,
                            totalDuration: currentResult.totalDuration,
                            uniqueSpeakerCount: currentResult.uniqueSpeakerCount
                        )
                        viewModel.result = updatedResult
                        audioPlayerViewModel.loadAudioFile(url: url)
                    }
                case .audioWithTranscript:
                    handleAudioWithTranscriptSelection(url: url)
                }
            }
        case .failure(let error):
            print("File selection failed: \(error)")
        }
    }


    private func handleAudioWithTranscriptSelection(url: URL) {
        #if os(macOS)
        guard url.startAccessingSecurityScopedResource() else {
            print("Failed to access security-scoped resource")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        #endif

        let isAudioFile = ["mp3", "wav", "m4a", "flac", "aac"].contains(url.pathExtension.lowercased())

        if isAudioFile {
            switch audioWithTranscriptState {
            case .selectingFile:
                selectedFileURL = url
                audioWithTranscriptState = .selectingTranscript
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showingFilePicker = true
                }
            case .selectingTranscript:
                // This shouldn't happen for audio files in transcript selection state
                break
            case .selectingAudio:
                // We already have transcript, now loading audio
                if let currentResult = viewModel.result {
                    let updatedResult = TranscriptionResult(
                        segments: currentResult.segments,
                        audioFileName: url.lastPathComponent,
                        audioFileURL: url,
                        processingDate: currentResult.processingDate,
                        totalDuration: currentResult.totalDuration,
                        uniqueSpeakerCount: currentResult.uniqueSpeakerCount
                    )
                    viewModel.result = updatedResult
                    audioPlayerViewModel.loadAudioFile(url: url)
                }
                audioWithTranscriptState = .selectingFile
            }
        } else {
            // It's a transcript file
            switch audioWithTranscriptState {
            case .selectingFile:
                // Load transcript first, then ask for audio
                do {
                    let result = try viewModel.loadTranscription(from: url)
                    audioWithTranscriptState = .selectingAudio
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showingFilePicker = true
                    }
                } catch {
                    print("Failed to load transcription: \(error)")
                    audioWithTranscriptState = .selectingFile
                }
            case .selectingTranscript:
                // We already have audio, now loading transcript
                do {
                    let result = try viewModel.loadTranscription(from: url)
                    if let audioURL = selectedFileURL {
                        let updatedResult = TranscriptionResult(
                            segments: result.segments,
                            audioFileName: audioURL.lastPathComponent,
                            audioFileURL: audioURL,
                            processingDate: result.processingDate,
                            totalDuration: result.totalDuration,
                            uniqueSpeakerCount: result.uniqueSpeakerCount
                        )
                        viewModel.result = updatedResult
                        audioPlayerViewModel.loadAudioFile(url: audioURL)
                    }
                    audioWithTranscriptState = .selectingFile
                } catch {
                    print("Failed to load transcription: \(error)")
                    audioWithTranscriptState = .selectingFile
                }
            case .selectingAudio:
                // This shouldn't happen for transcript files in audio selection state
                break
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func saveSpeakerName() {
        let trimmedName = newSpeakerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            viewModel.setSpeakerName(trimmedName, for: renamingSpeakerId)
        }
        showingSpeakerRename = false
    }
    
    #if os(macOS)
    @ViewBuilder
    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Transcription")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("Convert audio to text with speaker identification")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Actions")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Button(action: {
                    showingFilePicker = true
                    currentImportType = .audio
                }) {
                    Label("Import Audio", systemImage: "waveform")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.blue)
                
                Button(action: {
                    showingFilePicker = true
                    currentImportType = .transcription
                }) {
                    Label("Import Transcript", systemImage: "doc.text")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.blue)
                
                if viewModel.result != nil {
                    Button(action: {
                        showingSaveSheet = true
                    }) {
                        Label("Save Results", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.green)
                }
            }
            
            if viewModel.result != nil {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Statistics")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if let result = viewModel.result {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Duration: \(formatDuration(result.totalDuration))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("Speakers: \(result.uniqueSpeakerCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("Segments: \(result.segments.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 200)
    }
    #endif
}

// MARK: - Speaker Segment View

struct SpeakerSegmentView: View {
    let segment: SpeakerSegment
    let result: TranscriptionResult
    let isCurrentlyPlaying: Bool
    let onTap: () -> Void
    let onRenameSpeaker: (Int) -> Void

    private var speakerColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .pink, .teal, .indigo]
        return colors[segment.speakerId % colors.count]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Speaker indicator
            VStack {
                Circle()
                    .fill(speakerColor)
                    .frame(width: 8, height: 8)

                Rectangle()
                    .fill(speakerColor.opacity(0.3))
                    .frame(width: 2)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(segment.speakerName(from: result))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(speakerColor)

                    if isCurrentlyPlaying {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundColor(speakerColor)
                    }

                    Spacer()

                    Text(segment.timeRange)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Image(systemName: "play.circle")
                        .font(.caption)
                        .foregroundColor(.blue)
                }

                Text(segment.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        #if os(iOS)
        .background(isCurrentlyPlaying ? speakerColor.opacity(0.1) : Color(.systemBackground))
        #else
        .background(isCurrentlyPlaying ? speakerColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        #endif
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCurrentlyPlaying ? speakerColor : Color.clear, lineWidth: 2)
        )
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            Button {
                onRenameSpeaker(segment.speakerId)
            } label: {
                Label("Rename Speaker", systemImage: "pencil")
            }
        }
    }
}

// MARK: - Export View

struct ExportView: View {
    let transcription: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack {
                ScrollView {
                    Text(transcription)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.gray.quaternary)
                .cornerRadius(8)

                HStack {
                    #if os(iOS)
                    Button("Copy to Clipboard") {
                        UIPasteboard.general.string = transcription
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Share") {
                        shareTranscription()
                    }
                    .buttonStyle(.borderedProminent)
                    #else
                    Button("Copy to Clipboard") {
                        NSPasteboard.general.setString(transcription, forType: .string)
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    #endif
                }
                .padding(.top)
            }
            .padding()
            .navigationTitle("Export Transcription")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            #endif
        }
    }
    

    #if os(iOS)
    private func shareTranscription() {
        let activityVC = UIActivityViewController(
            activityItems: [transcription],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityVC, animated: true)
        }
    }
    #endif
}

// MARK: - Transcription Document for File Export

struct TranscriptionDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let transcription: TranscriptionResult?

    init(transcription: TranscriptionResult?) {
        self.transcription = transcription
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.transcription = try JSONDecoder().decode(TranscriptionResult.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let transcription = transcription else {
            throw CocoaError(.fileWriteUnknown)
        }
        let data = try JSONEncoder().encode(transcription)
        return .init(regularFileWithContents: data)
    }
}

#Preview {
    TranscriptionView()
}
