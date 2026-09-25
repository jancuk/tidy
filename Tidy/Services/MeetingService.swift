import AVFoundation
import Combine
import Foundation

@MainActor
final class MeetingService: ObservableObject {
    enum ProcessingOperation { case transcription, summary, transcribeAndSummarize }
    enum ProcessingStage { case transcription, summary }

    typealias Transcriber = (MeetingAudioChunk, URL, MeetingTranscriptionProvider) async throws -> [MeetingSegment]
    typealias Summarizer = ([MeetingSegment], MeetingSummaryProvider, String, String) async throws -> MeetingSummary

    @Published private(set) var records: [MeetingRecord] = []
    @Published var selectedID: UUID?
    @Published private(set) var recordingID: UUID?
    @Published private(set) var processingID: UUID?
    @Published private(set) var processingStage: ProcessingStage?
    @Published private(set) var isStarting = false
    @Published private(set) var isStopping = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var levels: [String: Float] = [:]
    @Published private(set) var progress = ""
    @Published var errorMessage: String?
    @Published private(set) var playingSegmentID: String?
    @Published private(set) var playingRecordingID: UUID?
    @Published private(set) var isPreparingPlayback = false
    @Published private(set) var captureWarning: String?
    @Published private(set) var liveTranscriptProgress = ""
    @Published private(set) var liveTranscriptError: String?

    let store: MeetingStore
    private let recorder: any MeetingRecording
    private let transcribe: Transcriber
    private let resolveTranscription: (MeetingTranscriptionProvider) throws -> MeetingTranscriptionProvider
    private let summarize: Summarizer
    private let validateSummary: (MeetingSummaryProvider) throws -> Void
    private var work: Task<Void, Never>?
    private var liveWork: Task<Void, Never>?
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var captureFailure: String?
    private var player: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var recordingPlayer: AVPlayer?
    private var playbackWork: Task<Void, Never>?
    private var lastCallAudioTime: TimeInterval = 0

    init(directory: URL? = nil, recorder: (any MeetingRecording)? = nil, transcribe: Transcriber? = nil, summarize: Summarizer? = nil,
         resolveTranscription: ((MeetingTranscriptionProvider) throws -> MeetingTranscriptionProvider)? = nil,
         validateSummary: @escaping (MeetingSummaryProvider) throws -> Void = { try $0.validatePrivacy() }) {
        store = MeetingStore(directory: directory)
        self.recorder = recorder ?? MeetingRecorder()
        let ai = MeetingAIService()
        self.transcribe = transcribe ?? { try await ai.transcribe($0, url: $1, provider: $2) }
        self.resolveTranscription = resolveTranscription ?? ai.resolveTranscriptionProvider
        self.validateSummary = validateSummary
        self.summarize = summarize ?? { try await ai.summarize($0, provider: $1, language: $2, model: $3) }
        let loaded = store.load()
        records = loaded.records
        errorMessage = loaded.errors.isEmpty ? nil : loaded.errors.joined(separator: "\n")
        selectedID = records.first?.id
        self.recorder.onError = { [weak self] message in
            guard let self else { return }
            self.captureFailure = message
            if self.recordingID != nil, !self.isStarting, !self.isStopping {
                Task { await self.stop(andSummarize: false) }
            }
        }
    }

    var isBusy: Bool { isStarting || isStopping || recordingID != nil || processingID != nil }
    var selected: MeetingRecord? { records.first { $0.id == selectedID } }
    var isTakingNotes: Bool { records.first { $0.id == recordingID }?.notetakerEnabled == true }

    func start(title: String, mode: MeetingMode, app: MeetingCaptureApp?, provider: MeetingSummaryProvider,
               language: String, participantsInformed: Bool, transcriptionProvider: MeetingTranscriptionProvider = .localWhisper,
               model: String = "", callAudioSource: MeetingCallAudioSource = .application, notetakerEnabled: Bool = false) async {
        guard !isBusy else { return }
        guard participantsInformed else { errorMessage = "Let participants know you are recording before starting."; return }
        guard mode != .call || callAudioSource == .system || app != nil else { errorMessage = "Select the app playing your call audio."; return }
        var resolvedTranscription = transcriptionProvider
        if notetakerEnabled {
            do {
                try validateSummary(provider)
                resolvedTranscription = try resolveTranscription(transcriptionProvider)
                try resolvedTranscription.validatePrivacy()
            } catch {
                let detail = error.localizedDescription.replacingOccurrences(of: " Your recording is saved.", with: "")
                    .replacingOccurrences(of: " Your recording is preserved.", with: "")
                errorMessage = "Notetaker setup needs attention: \(detail) Recording has not started."
                return
            }
        }
        isStarting = true
        errorMessage = nil
        captureFailure = nil
        captureWarning = nil
        liveTranscriptError = nil
        liveTranscriptProgress = ""
        lastCallAudioTime = 0
        stopPlayback()
        defer { isStarting = false }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var record = MeetingRecord(title: trimmed.isEmpty ? "Meeting · \(Date().formatted(date: .abbreviated, time: .shortened))" : trimmed,
                                   mode: mode, appName: app?.name, summaryProvider: provider, summaryLanguage: language)
        record.transcriptionProvider = resolvedTranscription
        record.notetakerEnabled = notetakerEnabled
        if mode == .call {
            record.callAudioSource = callAudioSource
            record.appName = callAudioSource == .system ? "System audio" : app?.name
        }
        record.summaryModel = provider.resolvedModel(model)
        do {
            try update(record)
            selectedID = record.id
            try await recorder.start(mode: mode, appID: app?.id, callAudioSource: callAudioSource, directory: store.folder(record.id),
                                     chunkDuration: notetakerEnabled ? 20 : 60)
            if let captureFailure { throw MeetingError.message(captureFailure) }
            recordingID = record.id
            elapsed = 0
            levels = [:]
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Recording a Tidy meeting")
            timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    await self.refreshRecording()
                }
            }
            if let timer { RunLoop.main.add(timer, forMode: .common) }
        } catch {
            _ = try? await recorder.stop()
            try? store.recoverChunks(in: &record)
            record.status = .interrupted
            record.error = error.localizedDescription
            try? update(record)
            errorMessage = error.localizedDescription
        }
    }

    func refreshRecording() async {
        guard recordingID != nil, !isStarting, !isStopping else { return }
        elapsed = min(recorder.elapsed, MeetingLimits.maximumRecordingDuration)
        levels = recorder.levels()
        if records.first(where: { $0.id == recordingID })?.mode == .call {
            if (levels["Call"] ?? 0) > 0.002 { lastCallAudioTime = elapsed }
            captureWarning = elapsed - lastCallAudioTime >= 20
                ? "No call audio detected for 20 seconds. If someone else is speaking, check that Meet is audible and its tab is not muted. For browser calls, use System audio. Check Tidy’s Screen & System Audio Recording permission."
                : nil
        }
        if elapsed >= MeetingLimits.maximumRecordingDuration {
            await stop(andSummarize: false)
        } else if isTakingNotes {
            queueLiveTranscription()
        }
    }

    private func queueLiveTranscription() {
        guard let id = recordingID, !isStopping, liveTranscriptError == nil,
              var record = records.first(where: { $0.id == id }) else { return }
        let known = Set(record.chunks.map(\.id))
        let completed = recorder.completedChunks().filter { !known.contains($0.id) }
        if !completed.isEmpty {
            record.chunks.append(contentsOf: completed)
            do { try update(record) }
            catch { liveTranscriptError = "Audio is still recording, but the transcript could not be saved: \(error.localizedDescription)"; return }
        }
        guard liveWork == nil, record.hasPendingTranscription else { return }
        liveWork = Task { [weak self] in
            guard let self else { return }
            defer { self.liveWork = nil; self.liveTranscriptProgress = "" }
            do {
                while let chunk = self.records.first(where: { $0.id == id })?.chunks.first(where: { !$0.transcribed }) {
                    try Task.checkCancellation()
                    guard self.recordingID == id, !self.isStopping else { return }
                    self.liveTranscriptProgress = "Transcribing \(chunk.source.lowercased()) audio…"
                    let provider = record.transcriptionProvider ?? .localWhisper
                    try provider.validatePrivacy()
                    let segments = chunk.hasSpeechLevelAudio
                        ? try await self.transcribe(chunk, self.store.audioURL(chunk, meetingID: id), provider) : []
                    try Task.checkCancellation()
                    guard self.recordingID == id, !self.isStopping,
                          var latest = self.records.first(where: { $0.id == id }),
                          let index = latest.chunks.firstIndex(where: { $0.id == chunk.id }) else { return }
                    latest.segments.removeAll { $0.chunkID == chunk.id }
                    latest.segments.append(contentsOf: segments)
                    latest.chunks[index].transcribed = true
                    try self.update(latest)
                }
            } catch {
                if !Task.isCancelled {
                    self.liveTranscriptError = "Live transcription paused. Recording continues; unfinished audio can be retried when you finish. \(error.localizedDescription)"
                }
            }
        }
    }

    func stop(andSummarize: Bool) async {
        guard let id = recordingID, !isStarting, !isStopping, var record = records.first(where: { $0.id == id }) else { return }
        isStopping = true
        let pendingLive = liveWork
        pendingLive?.cancel()
        elapsed = min(recorder.elapsed, MeetingLimits.maximumRecordingDuration)
        record.recordingLimitReached = elapsed >= MeetingLimits.maximumRecordingDuration
        timer?.invalidate()
        timer = nil
        defer {
            isStopping = false
            if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        }
        var failure = captureFailure
        var captured: [MeetingAudioChunk]?
        do { captured = try await recorder.stop() }
        catch { failure = error.localizedDescription }
        recordingID = nil
        await pendingLive?.value
        record = records.first(where: { $0.id == id }) ?? record
        record.recordingLimitReached = elapsed >= MeetingLimits.maximumRecordingDuration
        if let captured {
            // Capture metadata does not carry completed transcription state.
            let transcribed = Set(record.chunks.filter(\.transcribed).map(\.id))
            record.chunks = captured.map { chunk in
                var chunk = chunk
                chunk.transcribed = chunk.transcribed || transcribed.contains(chunk.id)
                return chunk
            }
        }
        captureWarning = nil
        liveTranscriptError = nil
        record.duration = elapsed
        do {
            try store.recoverChunks(in: &record)
            failure = failure ?? record.error
            if record.chunks.isEmpty { failure = failure ?? "No audio was captured. Check your input device and macOS permissions." }
            if record.mode == .call && !record.chunks.contains(where: { $0.source == "Call" && $0.hasSpeechLevelAudio }) {
                failure = failure ?? "No call audio was detected. This recording may contain only your microphone. For Google Meet, choose Online call → System audio and check that the Call meter moves when another participant speaks. Missing audio cannot be recovered from this recording."
            }
            record.status = failure == nil ? .recorded : .interrupted
            record.error = failure
            try update(record)
            errorMessage = failure
        } catch { errorMessage = "Audio was saved, but meeting metadata could not be updated: \(error.localizedDescription)"; return }
        if andSummarize && failure == nil && record.recordingLimitReached != true {
            isStopping = false
            process(id, provider: record.summaryProvider, language: record.summaryLanguage,
                    transcriptionProvider: record.transcriptionProvider ?? .localWhisper, model: record.summaryModel ?? "")
        }
    }

    @discardableResult
    func transcribeRecording(_ id: UUID, provider: MeetingTranscriptionProvider) -> Task<Void, Never>? {
        guard let record = records.first(where: { $0.id == id }), record.hasPendingTranscription else { return nil }
        return process(id, provider: record.summaryProvider, language: record.summaryLanguage,
                       transcriptionProvider: provider, model: record.summaryModel ?? "", operation: .transcription)
    }

    @discardableResult
    func createNotes(_ id: UUID, provider: MeetingSummaryProvider, language: String, model: String = "") -> Task<Void, Never>? {
        process(id, provider: provider, language: language, model: model, operation: .summary)
    }

    @discardableResult
    func process(_ id: UUID, provider: MeetingSummaryProvider, language: String,
                 transcriptionProvider: MeetingTranscriptionProvider = .localWhisper, model: String = "",
                 operation: ProcessingOperation = .transcribeAndSummarize) -> Task<Void, Never>? {
        guard !isBusy, var record = records.first(where: { $0.id == id }) else { return nil }
        let needsTranscription = operation != .summary
        let needsSummary = operation != .transcription
        do {
            if operation == .summary && !record.canCreateNotes {
                throw MeetingError.message("Finish creating the transcript before requesting meeting notes.")
            }
            if needsSummary { try validateSummary(provider) }
            if needsTranscription && record.chunks.contains(where: { !$0.transcribed && $0.hasSpeechLevelAudio }) {
                let resolved = try resolveTranscription(transcriptionProvider)
                try resolved.validatePrivacy()
                record.transcriptionProvider = resolved
            }
            record.status = .processing
            if needsSummary {
                if record.summary != nil, record.summary?.format == nil {
                    let existingFormat = record.summaryFormat
                    record.summary?.format = existingFormat
                }
                record.summaryProvider = provider
                record.summaryLanguage = language
                record.summaryModel = provider.resolvedModel(model)
            }
            record.error = nil
            try update(record)
        } catch { errorMessage = error.localizedDescription; return nil }
        processingID = id
        processingStage = needsTranscription && record.hasPendingTranscription ? .transcription : .summary
        errorMessage = nil
        stopPlayback()
        work = Task { [weak self] in
            guard let self else { return }
            defer { self.processingID = nil; self.processingStage = nil; self.progress = ""; self.work = nil }
            do {
                if needsTranscription {
                    for index in record.chunks.indices where !record.chunks[index].transcribed {
                        try Task.checkCancellation()
                        let chunk = record.chunks[index]
                        self.progress = "Transcribing audio \(index + 1) of \(record.chunks.count)…"
                        if chunk.hasSpeechLevelAudio {
                            let transcriptionProvider = record.transcriptionProvider ?? .openAI
                            try transcriptionProvider.validatePrivacy()
                            let segments = try await self.transcribe(chunk, self.store.audioURL(chunk, meetingID: id), transcriptionProvider)
                            try Task.checkCancellation()
                            record.segments.removeAll { $0.chunkID == chunk.id }
                            record.segments.append(contentsOf: segments)
                        }
                        record.chunks[index].transcribed = true
                        try self.update(record)
                    }
                }
                try Task.checkCancellation()
                if needsSummary {
                    guard !record.segments.isEmpty else { throw MeetingError.message("No speech was found. Play the saved audio and check your input settings.") }
                    try self.validateSummary(provider)
                    self.processingStage = .summary
                    self.progress = "Preparing meeting notes with \(provider.title)…"
                    var result = try await self.summarize(record.orderedSegments, provider, language, record.summaryModel ?? "")
                    try Task.checkCancellation()
                    result.format = provider == .typeSafe ? .transcriptExcerpts : .written
                    record.summary = result
                    record.status = .ready
                } else {
                    record.status = record.summary == nil ? .transcribed : .ready
                }
                record.error = nil
                try self.update(record)
            } catch {
                record.status = .interrupted
                record.error = Task.isCancelled ? "Processing cancelled. Completed transcripts are saved; you can resume when ready." : error.localizedDescription
                do { try self.update(record) }
                catch { self.errorMessage = "Could not save meeting progress: \(error.localizedDescription)" }
                self.errorMessage = self.errorMessage ?? record.error
            }
        }
        return work
    }

    func updatePersonalNotes(_ id: UUID, text: String) {
        guard processingID != id, !isStopping, var record = records.first(where: { $0.id == id }) else { return }
        record.personalNotes = text
        do { try update(record) } catch { errorMessage = "Could not save your notes: \(error.localizedDescription)" }
    }

    func cancelProcessing() { work?.cancel() }

    func prepareForQuit() async {
        while isStarting || isStopping { try? await Task.sleep(for: .milliseconds(100)) }
        if recordingID != nil { await stop(andSummarize: false) }
        let pending = work
        pending?.cancel()
        await pending?.value
        stopPlayback()
    }

    func rename(_ id: UUID, title: String) {
        guard recordingID != id, processingID != id, var record = records.first(where: { $0.id == id }) else { return }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        record.title = String(title.prefix(200))
        do { try update(record) } catch { errorMessage = error.localizedDescription }
    }

    func delete(_ id: UUID) {
        guard !isBusy else { return }
        stopPlayback()
        do {
            try store.delete(id)
            records.removeAll { $0.id == id }
            if selectedID == id { selectedID = records.first?.id }
        } catch { errorMessage = error.localizedDescription }
    }

    func saveAction(_ action: MeetingAction, from id: UUID, to productivity: ProductivityService) {
        guard !isBusy, var record = records.first(where: { $0.id == id }), !record.savedActionIDs.contains(action.id) else { return }
        let references = action.segmentIDs.compactMap { sid in record.segments.first { $0.id == sid } }
            .map { "[\(MeetingRecord.timestamp($0.start))] \($0.text)" }.joined(separator: "\n")
        let body = action.title + "\n\nMeeting: \(record.title)"
            + (action.owner.map { "\nOwner: " + $0 } ?? "") + (action.dueText.map { "\nDue as discussed: " + $0 } ?? "")
            + "\n\n" + references
        let source = CaptureSource(appName: "Tidy Meetings", bundleID: Bundle.main.bundleIdentifier,
                                   url: store.folder(id).appendingPathComponent("meeting.json"))
        guard productivity.captureText(body, kind: .task, source: source) else { errorMessage = productivity.errorMessage; return }
        record.savedActionIDs.append(action.id)
        do { try update(record) } catch { errorMessage = "Task saved to Today, but could not mark it as saved in this meeting." }
    }

    func play(_ segment: MeetingSegment, in record: MeetingRecord) {
        guard recordingID == nil, !isStarting, let chunk = record.chunks.first(where: { $0.id == segment.chunkID }) else { return }
        do {
            stopPlayback()
            let player = try AVAudioPlayer(contentsOf: store.audioURL(chunk, meetingID: record.id))
            player.currentTime = max(0, segment.start - chunk.start)
            guard player.play() else { throw MeetingError.message("Could not play this audio segment.") }
            self.player = player
            playingSegmentID = segment.id
            playbackTimer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if self.player?.isPlaying != true { self.stopPlayback() }
                }
            }
            if let playbackTimer { RunLoop.main.add(playbackTimer, forMode: .common) }
        } catch { errorMessage = error.localizedDescription }
    }

    func playRecording(_ record: MeetingRecord) {
        guard recordingID == nil, !isStarting, !record.chunks.isEmpty else { return }
        stopPlayback()
        playingRecordingID = record.id
        isPreparingPlayback = true
        playbackWork = Task { [weak self] in
            guard let self else { return }
            do {
                let files = try record.chunks.map { ($0, try self.store.audioURL($0, meetingID: record.id)) }
                let composition = try await MeetingAudioPlayback.composition(files)
                try Task.checkCancellation()
                let item = AVPlayerItem(asset: composition)
                let player = AVPlayer(playerItem: item)
                self.recordingPlayer = player
                self.isPreparingPlayback = false
                player.play()
                self.playbackTimer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.recordingPlayer === player else { return }
                        if item.status == .failed {
                            self.errorMessage = item.error?.localizedDescription ?? "Could not play this recording."
                            self.stopPlayback()
                        } else if item.duration.isNumeric, player.currentTime() >= item.duration {
                            self.stopPlayback()
                        }
                    }
                }
                if let timer = self.playbackTimer { RunLoop.main.add(timer, forMode: .common) }
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = "Could not play the full recording: \(error.localizedDescription)"
                self.stopPlayback()
            }
        }
    }

    func stopPlayback() {
        playbackWork?.cancel()
        playbackWork = nil
        recordingPlayer?.pause()
        recordingPlayer = nil
        playingRecordingID = nil
        isPreparingPlayback = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        player?.stop()
        player = nil
        playingSegmentID = nil
    }

    func update(_ record: MeetingRecord) throws {
        try store.save(record)
        if let index = records.firstIndex(where: { $0.id == record.id }) { records[index] = record }
        else { records.insert(record, at: 0) }
    }
}

@MainActor
enum MeetingAudioPlayback {
    static func composition(_ files: [(MeetingAudioChunk, URL)]) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        for group in Dictionary(grouping: files, by: { $0.0.source }).values {
            guard let destination = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw MeetingError.message("Could not prepare an audio track.")
            }
            let ordered = group.sorted { $0.0.start < $1.0.start }
            for (index, entry) in ordered.enumerated() {
                try Task.checkCancellation()
                let (chunk, url) = entry
                guard chunk.start.isFinite, chunk.start >= 0, chunk.duration.isFinite, chunk.duration > 0 else {
                    throw MeetingError.message("The recording has invalid audio timing.")
                }
                let asset = AVURLAsset(url: url)
                guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                    throw MeetingError.message("A saved audio track could not be read.")
                }
                let range = try await track.load(.timeRange)
                var duration = min(chunk.duration, range.duration.seconds)
                // Trim clock overlap within a source while preserving gaps and simultaneous speakers.
                if index + 1 < ordered.count { duration = min(duration, ordered[index + 1].0.start - chunk.start) }
                guard duration.isFinite, duration > 0 else { continue }
                try destination.insertTimeRange(CMTimeRange(start: range.start, duration: CMTime(seconds: duration, preferredTimescale: 48000)),
                                                of: track, at: CMTime(seconds: chunk.start, preferredTimescale: 48000))
            }
        }
        guard !composition.tracks.isEmpty else { throw MeetingError.message("No saved audio is available.") }
        return composition
    }
}
