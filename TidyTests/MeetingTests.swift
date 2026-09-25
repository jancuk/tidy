import AVFoundation
import SwiftUI
import Testing
@testable import Tidy

struct MeetingTests {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("TidyMeetingTests-" + UUID().uuidString) }

    private func record() -> MeetingRecord {
        MeetingRecord(title: "Planning", mode: .inPerson, summaryProvider: .openAI, summaryLanguage: "English")
    }

    private func chunk(start: Double = 0) -> MeetingAudioChunk {
        MeetingAudioChunk(fileName: UUID().uuidString + ".wav", source: "Room", start: start, duration: 60, hasSpeechLevelAudio: true)
    }

    private func segment(_ chunk: MeetingAudioChunk, text: String = "We agreed to ship on Friday.") -> MeetingSegment {
        MeetingSegment(id: chunk.id.uuidString + "-0", chunkID: chunk.id, start: chunk.start + 3, end: chunk.start + 6,
                       speaker: "Speaker A", text: text)
    }

    private func summary(_ segments: [MeetingSegment]) -> MeetingSummary {
        MeetingSummary(overview: "Release planning.", decisions: [MeetingPoint(text: "Ship on Friday.", segmentIDs: [segments[0].id])],
                       actions: [], questions: [])
    }

    @Test func summaryRejectsInventedOrMissingEvidence() throws {
        let valid = """
        {"overview":"Plan","decisions":[{"text":"Ship","segmentIDs":["s1"]}],"actions":[],"questions":[]}
        """
        #expect(try MeetingSummary.decode("```json\n" + valid + "\n```", validSegmentIDs: ["s1"]).decisions.count == 1)
        #expect(throws: MeetingError.self) { try MeetingSummary.decode(valid, validSegmentIDs: ["different"]) }
        #expect(throws: MeetingError.self) { try MeetingSummary.decode(valid.replacingOccurrences(of: "[\"s1\"]", with: "[]"), validSegmentIDs: ["s1"]) }
    }

    @Test func transcriptionOffsetsAndSpeakerLabelsRemainScopedToChunk() throws {
        let data = Data("{\"segments\":[{\"start\":2.5,\"end\":5,\"speaker\":\"A\",\"text\":\"  Ship Friday.  \"}]}".utf8)
        let first = try MeetingAIService.decodeTranscript(data, chunk: chunk())
        let second = try MeetingAIService.decodeTranscript(data, chunk: chunk(start: 60))
        #expect(first[0].start == 2.5)
        #expect(second[0].start == 62.5)
        #expect(first[0].speaker != second[0].speaker)
        #expect(first[0].id != second[0].id)
        #expect(second[0].text == "Ship Friday.")
        let invalid = Data("{\"segments\":[{\"start\":2,\"end\":999,\"speaker\":\"A\",\"text\":\"Bad timestamp\"}]}".utf8)
        #expect(throws: MeetingError.self) { try MeetingAIService.decodeTranscript(invalid, chunk: chunk()) }
    }

    @Test func compactTranscriptPreservesTextAndScopedSpeakersWithinByteLimit() throws {
        let first = chunk()
        let second = chunk(start: 60)
        let text = String(repeating: "Kita ship Friday. \"quoted\" 👩🏽‍💻\n", count: 250)
        let segments = [segment(first, text: text), segment(second, text: "Do not ship yet.")]
        let transcript = try MeetingSummaryTranscript(segments)
        let batches = try transcript.batches(limit: 4000)
        #expect(batches.count > 1)
        #expect(batches.allSatisfy { $0.source.utf8.count <= 4000 })
        let rows = try batches.flatMap { try JSONDecoder().decode([[String]].self, from: Data($0.source.utf8)) }
        #expect(rows.filter { $0[0] == "s1" }.map { $0[2] }.joined() == text)
        #expect(rows.last?[2] == segments[1].text)
        #expect(rows.first?[1] != rows.last?[1])
        #expect(transcript.sourceIDs["s1"] == segments[0].id)
        #expect(!batches.contains { $0.source.contains(first.id.uuidString) })
        #expect(throws: MeetingError.self) { try MeetingSummaryTranscript([segments[0], segments[0]]) }
    }

    @Test func twoHourSummaryUsesLessInputAndRestoresEvidenceAfterMerging() async throws {
        let segments = (0..<1200).map { index in
            segment(chunk(start: Double(index * 6)), text: "Kita review deployment berikutnya. Ayu will finish the release checklist by Friday and confirm the test results.")
        }
        let batches = try MeetingSummaryTranscript(segments).batches()
        let oldBytes = try JSONEncoder().encode(segments).count
        let newBytes = batches.reduce(0) { $0 + $1.source.utf8.count }
        #expect(newBytes < oldBytes / 2)
        var calls = 0
        let ai = MeetingAIService(completion: { instructions, source, provider, model in
            calls += 1
            #expect(provider == .codexCLI)
            #expect(model == "chosen-model")
            let ids: [String]
            if instructions.contains("Merge the supplied partial notes") {
                let partials = try JSONDecoder().decode([MeetingSummary].self, from: Data(source.utf8))
                ids = partials.flatMap(\.referencedSegmentIDs)
            } else {
                let rows = try JSONDecoder().decode([[String]].self, from: Data(source.utf8))
                ids = rows.map { $0[0] }
            }
            let result = MeetingSummary(overview: "Release planning", decisions: [MeetingPoint(text: "Review the release", segmentIDs: [ids.first!, ids.last!])], actions: [], questions: [])
            return String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        })
        let result = try await ai.summarize(segments, provider: .codexCLI, language: "Auto", model: "chosen-model")
        #expect(calls == batches.count + 1)
        #expect(result.decisions[0].segmentIDs == [segments.first!.id, segments.last!.id])
        let originalBatches = Int(ceil(Double(segments.reduce(0) { $0 + $1.text.utf8.count + $1.speaker.utf8.count + 200 }) / 20_000))
        #expect(batches.count < originalBatches / 2)
        print("Meeting input fixture: \(oldBytes) → \(newBytes) JSON bytes; initial calls approximately \(originalBatches) → \(batches.count), total new calls \(calls)")
    }

    @Test func summaryRejectsReferencesOutsideItsBatch() async throws {
        let ai = MeetingAIService(completion: { _, _, _, _ in
            "{\"overview\":\"Plan\",\"decisions\":[{\"text\":\"Ship\",\"segmentIDs\":[\"s999\"]}],\"actions\":[],\"questions\":[]}"
        })
        await #expect(throws: MeetingError.self) {
            try await ai.summarize([segment(chunk())], provider: .codexCLI, language: "Auto")
        }
    }

    @Test func openAIPipelineUsesAudioUploadThenEvidenceBasedJSONSummary() async throws {
        let root = root()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audio = root.appendingPathComponent("test.wav")
        try Data(repeating: 0, count: 100).write(to: audio)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MeetingMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let ai = MeetingAIService(session: session, apiKey: { "test-key" })
        var chunk = chunk()
        chunk.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let segments = try await ai.transcribe(chunk, url: audio, provider: .openAI)
        let summary = try await ai.summarize(segments, provider: .openAI, language: "English")
        #expect(segments.count == 1)
        #expect(summary.decisions[0].segmentIDs == [segments[0].id])
    }

    @Test func automaticTranscriptionUsesSavedGeminiWithoutAnOpenAIKey() throws {
        let ai = MeetingAIService(apiKey: { " \n" }, geminiAPIKey: { "gemini-test-key" })
        #expect(try ai.resolveTranscriptionProvider(.automatic) == .gemini)
        #expect(throws: MeetingError.self) { try ai.resolveTranscriptionProvider(.openAI) }
        let both = MeetingAIService(apiKey: { "openai-test-key" }, geminiAPIKey: { "gemini-test-key" })
        #expect(try both.resolveTranscriptionProvider(.automatic) == .openAI)
        #expect(try both.resolveTranscriptionProvider(.gemini) == .gemini)
        let neither = MeetingAIService(apiKey: { nil }, geminiAPIKey: { nil })
        #expect(throws: MeetingError.self) { try neither.resolveTranscriptionProvider(.automatic) }
    }

    @MainActor @Test func geminiAudioAndCodexSummaryWorkWithoutOpenAIKey() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MeetingGeminiMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let ai = MeetingAIService(session: session, apiKey: { nil }, geminiAPIKey: { "gemini-test-key" })
        var summaryCalled = false
        let service = MeetingService(directory: root,
            transcribe: { try await ai.transcribe($0, url: $1, provider: $2) },
            summarize: { segments, provider, language, _ in
                #expect(provider == .codexCLI)
                #expect(language == "Bahasa Indonesia")
                #expect(segments[0].text == "Kita rilis hari Jumat.")
                summaryCalled = true
                return summary(segments)
            }, resolveTranscription: ai.resolveTranscriptionProvider)
        var record = record()
        record.status = .recorded
        record.chunks = [chunk(start: 60)]
        try service.update(record)
        try Data(repeating: 0, count: 100).write(to: service.store.audioURL(record.chunks[0], meetingID: record.id))
        await service.process(record.id, provider: .codexCLI, language: "Bahasa Indonesia", transcriptionProvider: .automatic)?.value
        let saved = try #require(service.store.load().records.first)
        #expect(saved.status == .ready)
        #expect(saved.transcriptionProvider == .gemini)
        #expect(saved.segments[0].start == 60)
        #expect(saved.chunks[0].transcribed)
        #expect(summaryCalled)
    }

    @Test func geminiRejectsBlockedAndTruncatedTranscripts() throws {
        for body in ["{}", "{\"candidates\":[]}", "{\"candidates\":[{\"finishReason\":\"MAX_TOKENS\"}]}",
                     "{\"candidates\":[{\"finishReason\":\"SAFETY\"}]}"] {
            #expect(throws: MeetingError.self) { try MeetingAIService.decodeGeminiTranscript(Data(body.utf8), chunk: chunk()) }
        }
    }

    @Test func existingMeetingsLoadWithoutTranscriptionProvider() throws {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(record())) as? [String: Any])
        json.removeValue(forKey: "transcriptionProvider")
        let restored = try JSONDecoder().decode(MeetingRecord.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.transcriptionProvider == nil)
        #expect(restored.summaryProvider == .openAI)
        #expect(restored.summaryModel == nil)
        #expect(restored.personalNotes == nil)
    }

    @Test func localTranscriptPreservesOffsetsWithoutInventingSpeakers() throws {
        let data = Data("{\"transcription\":[{\"offsets\":{\"from\":1500,\"to\":4250},\"text\":\" Kita rilis Jumat. \"}]}".utf8)
        let segments = try MeetingLocalTranscriber.decodeTranscript(data, chunk: chunk(start: 60))
        #expect(segments[0].start == 61.5)
        #expect(segments[0].end == 64.25)
        #expect(segments[0].speaker == "Room")
        #expect(segments[0].text == "Kita rilis Jumat.")
        let invalid = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "4250", with: "999999").utf8)
        #expect(throws: MeetingError.self) { try MeetingLocalTranscriber.decodeTranscript(invalid, chunk: chunk()) }
    }

    @Test func localTranscriptionNeedsNoCloudProviderAndKeepsOriginalLanguage() throws {
        try MeetingTranscriptionProvider.localWhisper.validatePrivacy()
        let args = MeetingLocalTranscriber.arguments(audio: URL(fileURLWithPath: "/tmp/meeting audio.wav"),
            model: URL(fileURLWithPath: "/tmp/small model.bin"), output: URL(fileURLWithPath: "/tmp/transcript"))
        #expect(args.contains("/tmp/meeting audio.wav"))
        #expect(args.contains("auto"))
        #expect(!args.contains("--translate"))
        #expect(!args.contains("--diarize"))
        #expect(!args.contains("--tinydiarize"))
    }

    @Test func localTranscriptClampsWhisperWindowPaddingToSavedAudio() throws {
        let data = Data("""
        {"transcription":[
          {"offsets":{"from":51920,"to":81920},"text":" Keep this final sentence. "},
          {"offsets":{"from":60000,"to":90000},"text":"Padding only"}
        ]}
        """.utf8)
        let chunk = chunk(start: 180)
        let segments = try MeetingLocalTranscriber.decodeTranscript(data, chunk: chunk)
        #expect(segments.count == 1)
        let segment = try #require(segments.first)
        #expect(abs(segment.start - 231.92) < 0.000001)
        #expect(segment.end == 240)
        #expect(segment.text == "Keep this final sentence.")
        #expect(segment.id == "\(chunk.id.uuidString)-0")
    }

    @Test func localTranscriptIgnoresBlankSegmentsBeforeValidatingTimestamps() throws {
        let data = Data("""
        {"transcription":[
          {"offsets":{"from":-1000,"to":999999},"text":" [BLANK_AUDIO] "},
          {"offsets":{"from":90000,"to":80000},"text":" "},
          {"offsets":{"from":1000,"to":2000},"text":"Speech"}
        ]}
        """.utf8)
        let chunk = chunk()
        let segments = try MeetingLocalTranscriber.decodeTranscript(data, chunk: chunk)
        #expect(segments.map(\.text) == ["Speech"])
        #expect(segments.first?.id == "\(chunk.id.uuidString)-2")
    }

    @Test func localTranscriptStillRejectsMalformedSpeechTimestamps() throws {
        for (start, end) in [(-1, 2000), (2000, 1000), (51920, 90001), (999999, 999999)] {
            let data = Data("{\"transcription\":[{\"offsets\":{\"from\":\(start),\"to\":\(end)},\"text\":\"Speech\"}]}".utf8)
            #expect(throws: MeetingError.self) { try MeetingLocalTranscriber.decodeTranscript(data, chunk: chunk()) }
        }
    }

    @Test func localTranscriptClampsPaddingForShortFinalAudioPart() throws {
        var chunk = chunk(start: 120)
        chunk.duration = 5.125
        let data = Data("{\"transcription\":[{\"offsets\":{\"from\":4500,\"to\":30000},\"text\":\"Final words\"}]}".utf8)
        let segments = try MeetingLocalTranscriber.decodeTranscript(data, chunk: chunk)
        #expect(segments.first?.start == 124.5)
        #expect(segments.first?.end == 125.125)
    }

    @Test func localTranscriptRejectsInvalidAudioMetadata() throws {
        let data = Data("{\"transcription\":[]}".utf8)
        for (start, duration) in [(Double.nan, 60.0), (-1, 60), (0, Double.infinity), (0, 0), (0, -1)] {
            var chunk = chunk(start: start)
            chunk.duration = duration
            #expect(throws: MeetingError.self) { try MeetingLocalTranscriber.decodeTranscript(data, chunk: chunk) }
        }
    }

    @Test func customSummaryModelOverridesSettingsWithoutChangingThem() throws {
        let suite = "TidyMeetingModels-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("settings-model", forKey: AppDefaults.codexCLIModel)
        #expect(MeetingSummaryProvider.codexCLI.resolvedModel("  meeting-model  ", defaults: defaults) == "meeting-model")
        #expect(MeetingSummaryProvider.codexCLI.resolvedModel(" \n", defaults: defaults) == "settings-model")
        #expect(defaults.string(forKey: AppDefaults.codexCLIModel) == "settings-model")
        #expect(MeetingSummaryProvider.openAI.resolvedModel("", defaults: defaults) == "gpt-4.1-mini")
        let args = CodexTextRunner.arguments(output: URL(fileURLWithPath: "/tmp/output"),
            directory: URL(fileURLWithPath: "/tmp"), model: "meeting-model")
        let index = try #require(args.firstIndex(of: "--model"))
        #expect(args[index + 1] == "meeting-model")
    }

    @MainActor @Test func localAudioAndChosenCodexModelAreSavedTogether() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        var record = record()
        record.chunks = [chunk()]
        var summarized = false
        let service = MeetingService(directory: root, transcribe: { chunk, _, provider in
            #expect(provider == .localWhisper)
            return [segment(chunk)]
        }, summarize: { segments, provider, _, model in
            #expect(provider == .codexCLI)
            #expect(model == "chosen-model")
            summarized = true
            return summary(segments)
        }, resolveTranscription: { preference in
            #expect(preference == .localWhisper)
            return .localWhisper
        })
        try service.update(record)
        await service.process(record.id, provider: .codexCLI, language: "English", model: "chosen-model")?.value
        let saved = try #require(service.store.load().records.first)
        #expect(saved.status == .ready)
        #expect(saved.summaryModel == "chosen-model")
        #expect(saved.transcriptionProvider == .localWhisper)
        #expect(summarized)
    }

    @Test func localProcessTimeoutTerminatesWork() async throws {
        let root = root()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let start = Date()
        await #expect(throws: MeetingError.self) {
            try await MeetingLocalTranscriber.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"],
                directory: root, timeout: 0.1, name: "Test transcription")
        }
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @MainActor @Test func savedTranscriptCanUseCodexWithoutAnyTranscriptionKey() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        var record = record()
        var chunk = chunk()
        chunk.transcribed = true
        record.chunks = [chunk]
        record.segments = [segment(chunk)]
        let service = MeetingService(directory: root, summarize: { segments, provider, _, _ in
            #expect(provider == .codexCLI)
            return summary(segments)
        }, resolveTranscription: { _ in throw MeetingError.message("Must not require a key for saved transcripts") })
        try service.update(record)
        await service.process(record.id, provider: .codexCLI, language: "English")?.value
        #expect(service.records[0].status == .ready)
    }

    @Test func recordingChunksPersistRecoverAndStayBelowUploadLimit() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(directory: root)
        let record = record()
        try store.save(record)
        let sink = MeetingAudioSink(directory: store.folder(record.id), epoch: 0)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24000))
        buffer.frameLength = 24000
        let samples = try #require(buffer.floatChannelData?[0])
        for i in 0..<24000 { samples[i] = sin(Float(i) * 0.1) * 0.1 }
        for second in 0..<65 { sink.append(buffer, source: "Room", time: Double(second)) }
        let chunks = try sink.finish()
        #expect(chunks.count == 2)
        #expect(chunks[0].start == 0)
        #expect(chunks[0].duration == 60)
        #expect(chunks[1].start == 60)
        #expect(chunks[1].duration == 5)
        #expect(chunks.allSatisfy { $0.hasSpeechLevelAudio })
        let loaded = store.load()
        #expect(loaded.errors.isEmpty)
        let recovered = try #require(loaded.records.first)
        #expect(recovered.status == .interrupted)
        #expect(recovered.chunks.count == 2)
        #expect(recovered.duration == 65)
        for chunk in recovered.chunks {
            let url = try store.audioURL(chunk, meetingID: recovered.id)
            #expect(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize! < 25_000_000)
            let audio = try AVAudioFile(forReading: url)
            #expect(audio.length > 0)
            let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            #expect(permissions?.intValue == 0o600)
        }
    }

    @Test func silenceAndAudioGapsArePreservedWithoutInventingSpeech() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(directory: root)
        let record = record()
        try store.save(record)
        let sink = MeetingAudioSink(directory: store.folder(record.id), epoch: 10)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24000))
        buffer.frameLength = 24000
        for i in 0..<24000 { buffer.floatChannelData![0][i] = 0 }
        sink.append(buffer, source: "Call", time: 10)
        sink.append(buffer, source: "Call", time: 20)
        let chunks = try sink.finish()
        #expect(chunks.count == 2)
        #expect(chunks[1].start == 10)
        #expect(chunks.allSatisfy { !$0.hasSpeechLevelAudio })
    }

    @Test func damagedRecordsArePreservedAndPathsCannotEscapeMeeting() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MeetingStore(directory: root)
        let record = record()
        try store.save(record)
        var badChunk = chunk()
        badChunk.fileName = "../elsewhere.wav"
        #expect(throws: MeetingError.self) { try store.audioURL(badChunk, meetingID: record.id) }
        let file = store.folder(record.id).appendingPathComponent("meeting.json")
        try Data("broken source".utf8).write(to: file)
        #expect(store.load().errors.count == 1)
        #expect(try String(contentsOf: file, encoding: .utf8) == "broken source")
    }

    @MainActor @Test func failedTranscriptionRetriesOnlyUnfinishedChunks() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        var calls: [UUID] = []
        var fail = true
        var record = record()
        record.status = .recorded
        record.chunks = [chunk(), chunk(start: 60)]
        let lastID = record.chunks[1].id
        let service = MeetingService(directory: root, transcribe: { chunk, _, provider in
            #expect(provider == .gemini)
            calls.append(chunk.id)
            if chunk.id == lastID && fail { throw MeetingError.message("Network unavailable") }
            return [segment(chunk)]
        }, summarize: { segments, _, _, _ in summary(segments) }, resolveTranscription: { _ in .gemini })
        try service.update(record)
        await service.process(record.id, provider: .openAI, language: "English")?.value
        #expect(service.records[0].status == .interrupted)
        #expect(service.records[0].segments.count == 1)
        fail = false
        await service.process(record.id, provider: .openAI, language: "English")?.value
        #expect(service.records[0].status == .ready)
        #expect(service.records[0].segments.count == 2)
        #expect(calls.filter { $0 == record.chunks[0].id }.count == 1)
        #expect(calls.filter { $0 == lastID }.count == 2)
        #expect(service.store.load().records[0].segments.count == 2)
    }

    @MainActor @Test func localTranscriptDoesNotRequireCloudAccessOrGenerateNotes() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        var record = record()
        record.chunks = [chunk()]
        var transcriptionCalls = 0
        var summaryCalls = 0
        var summaryAllowed = false
        let service = MeetingService(directory: root, transcribe: { chunk, _, provider in
            #expect(provider == .localWhisper)
            transcriptionCalls += 1
            return [segment(chunk)]
        }, summarize: { segments, _, _, _ in
            summaryCalls += 1
            return summary(segments)
        }, resolveTranscription: { $0 }, validateSummary: { _ in
            if !summaryAllowed { throw MeetingError.message("Cloud access disabled") }
        })
        try service.update(record)
        await service.transcribeRecording(record.id, provider: .localWhisper)?.value
        let saved = try #require(service.store.load().records.first)
        #expect(saved.status == .transcribed)
        #expect(saved.canCreateNotes)
        #expect(saved.displayStatus == "Transcript ready")
        #expect(saved.summary == nil)
        #expect(summaryCalls == 0)
        #expect(transcriptionCalls == 1)
        #expect(service.transcribeRecording(record.id, provider: .localWhisper) == nil)
        #expect(service.createNotes(record.id, provider: .codexCLI, language: "Auto") == nil)
        #expect(service.records[0].status == .transcribed)
        summaryAllowed = true
        await service.createNotes(record.id, provider: .codexCLI, language: "Auto")?.value
        #expect(summaryCalls == 1)
        #expect(transcriptionCalls == 1)
        #expect(service.records[0].status == .ready)
    }

    @MainActor @Test func writtenSummaryReplacesLegacyExcerptsOnlyAfterSuccess() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        var record = record()
        record.summaryProvider = .typeSafe
        record.segments = [segment(chunk())]
        record.summary = summary(record.segments)
        record.summary?.overview = "Original transcript excerpts"
        record.status = .ready
        #expect(record.summaryFormat == .transcriptExcerpts)
        #expect(record.markdown.contains("## Transcript highlights"))
        var fail = true
        let service = MeetingService(directory: root, transcribe: { _, _, _ in
            Issue.record("Creating a written summary must reuse the saved transcript")
            return []
        }, summarize: { segments, provider, _, _ in
            #expect(provider == .codexCLI)
            #expect(segments == record.segments)
            if fail { throw MeetingError.message("Temporary summary failure") }
            return summary(segments)
        })
        try service.update(record)
        await service.createNotes(record.id, provider: .codexCLI, language: "Auto")?.value
        let failed = try #require(service.store.load().records.first)
        #expect(failed.summary?.overview == "Original transcript excerpts")
        #expect(failed.summaryFormat == .transcriptExcerpts)
        #expect(failed.segments == record.segments)
        fail = false
        await service.createNotes(record.id, provider: .codexCLI, language: "Auto")?.value
        let saved = try #require(service.store.load().records.first)
        #expect(saved.summaryFormat == .written)
        #expect(saved.summary?.overview == "Release planning.")
        #expect(saved.markdown.contains("## Summary"))
        #expect(saved.markdown.contains("## Decisions"))
        #expect(saved.markdown.contains("## Action items"))
        #expect(saved.markdown.contains("## Open questions"))
        #expect(saved.segments == record.segments)
    }

    @MainActor @Test func notesCannotSilentlyTranscribeUnfinishedAudio() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        var record = record()
        record.chunks = [chunk()]
        record.segments = [segment(record.chunks[0])]
        var calls = 0
        let service = MeetingService(directory: root, transcribe: { _, _, _ in calls += 1; return [] },
                                     summarize: { segments, _, _, _ in calls += 1; return summary(segments) })
        try service.update(record)
        #expect(service.createNotes(record.id, provider: .codexCLI, language: "Auto") == nil)
        #expect(calls == 0)
        #expect(service.processingID == nil)
        #expect(service.records[0].segments == record.segments)
    }

    @MainActor @Test func standaloneTranscriptionResumesAndPreservesPersonalNotes() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        var record = record()
        record.chunks = [chunk(), chunk(start: 60)]
        var fail = true
        var calls: [UUID] = []
        let service = MeetingService(directory: root, transcribe: { chunk, _, _ in
            calls.append(chunk.id)
            if chunk.start == 60 && fail { throw MeetingError.message("Interrupted") }
            return [segment(chunk)]
        }, summarize: { _, _, _, _ in throw MeetingError.message("Must not call summary") }, resolveTranscription: { $0 })
        try service.update(record)
        service.updatePersonalNotes(record.id, text: "Check the rollout risks.")
        await service.transcribeRecording(record.id, provider: .localWhisper)?.value
        #expect(service.records[0].status == .interrupted)
        #expect(service.records[0].segments.count == 1)
        fail = false
        await service.transcribeRecording(record.id, provider: .localWhisper)?.value
        #expect(calls.filter { $0 == record.chunks[0].id }.count == 1)
        #expect(calls.filter { $0 == record.chunks[1].id }.count == 2)
        let saved = try #require(service.store.load().records.first)
        #expect(saved.status == .transcribed)
        #expect(saved.personalNotes == "Check the rollout risks.")
        #expect(saved.markdown.contains("## Your notes\n\nCheck the rollout risks."))
    }

    @MainActor @Test func silentRecordingFinishesWithoutSummaryOrRepeatedWork() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        var record = record()
        var audio = chunk()
        audio.hasSpeechLevelAudio = false
        record.chunks = [audio]
        let service = MeetingService(directory: root, transcribe: { _, _, _ in throw MeetingError.message("Must skip silence") },
            summarize: { _, _, _, _ in throw MeetingError.message("Must not summarize silence") },
            resolveTranscription: { _ in throw MeetingError.message("Must not require provider setup for silence") })
        try service.update(record)
        await service.transcribeRecording(record.id, provider: .localWhisper)?.value
        #expect(service.records[0].status == .transcribed)
        #expect(service.records[0].displayStatus == "No speech found")
        #expect(!service.records[0].canCreateNotes)
        #expect(service.transcribeRecording(record.id, provider: .localWhisper) == nil)
    }

    @MainActor @Test func recordingRequiresConsentAndStopSavesWithoutCallingAI() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = StubMeetingRecorder(chunks: [chunk()])
        var aiCalls = 0
        let service = MeetingService(directory: root, recorder: recorder, transcribe: { _, _, _ in aiCalls += 1; return [] })
        await service.start(title: "Offline discussion", mode: .inPerson, app: nil, provider: .openAI, language: "Auto", participantsInformed: false)
        #expect(recorder.starts == 0)
        await service.start(title: "Offline discussion", mode: .inPerson, app: nil, provider: .openAI, language: "Auto", participantsInformed: true)
        #expect(service.recordingID != nil)
        #expect(recorder.starts == 1)
        await service.start(title: "Duplicate", mode: .inPerson, app: nil, provider: .openAI, language: "Auto", participantsInformed: true)
        #expect(recorder.starts == 1)
        await service.stop(andSummarize: false)
        #expect(!service.isBusy)
        #expect(service.records[0].status == .recorded)
        #expect(service.records[0].chunks.count == 1)
        #expect(aiCalls == 0)
        #expect(service.store.load().records[0].status == .recorded)
    }

    @MainActor @Test func recordingLimitStopsBothModesSavesAndNeverCallsAI() async throws {
        for mode in MeetingMode.allCases {
            let root = root()
            defer { try? FileManager.default.removeItem(at: root) }
            var audio = chunk()
            audio.source = mode == .call ? "Call" : "Room"
            let recorder = StubMeetingRecorder(chunks: [audio])
            var aiCalls = 0
            let service = MeetingService(directory: root, recorder: recorder,
                transcribe: { _, _, _ in aiCalls += 1; return [] },
                summarize: { segments, _, _, _ in aiCalls += 1; return summary(segments) })
            await service.start(title: "Long meeting", mode: mode, app: MeetingCaptureApp(id: 1, name: "Browser"),
                                provider: .codexCLI, language: "Auto", participantsInformed: true)
            recorder.elapsed = 7199.9
            await service.refreshRecording()
            #expect(service.recordingID != nil)
            recorder.elapsed = mode == .call ? 7203 : 7200
            await service.refreshRecording()
            #expect(service.recordingID == nil)
            #expect(recorder.stops == 1)
            #expect(service.records[0].duration == 7200)
            #expect(service.records[0].recordingLimitReached == true)
            #expect(service.records[0].status == .recorded)
            #expect(service.store.load().records[0].recordingLimitReached == true)
            await service.refreshRecording()
            await service.stop(andSummarize: true)
            #expect(recorder.stops == 1)
            #expect(aiCalls == 0)
            await service.start(title: "Next meeting", mode: mode, app: MeetingCaptureApp(id: 1, name: "Browser"),
                                provider: .codexCLI, language: "Auto", participantsInformed: true)
            recorder.elapsed = 30
            await service.stop(andSummarize: false)
            #expect(service.records[0].recordingLimitReached == false)
            #expect(recorder.stops == 2)
        }
    }

    @Test func audioAtLimitIsTrimmedAndLateBuffersAreNotSaved() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sink = MeetingAudioSink(directory: root, epoch: 10)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24000))
        buffer.frameLength = 24000
        for i in 0..<24000 { buffer.floatChannelData![0][i] = 0.1 }
        for source in ["Room", "Call", "Microphone"] {
            sink.append(buffer, source: source, time: 7209.75)
            #expect(buffer.frameLength == 24000)
            sink.append(buffer, source: source, time: 7210)
            sink.append(buffer, source: source, time: 8000)
        }
        let chunks = try sink.finish()
        #expect(chunks.count == 3)
        for chunk in chunks {
            #expect(chunk.start + chunk.duration == 7200)
            #expect(chunk.duration == 0.25)
            let audio = try AVAudioFile(forReading: root.appendingPathComponent(chunk.fileName))
            #expect(audio.length == 6000)
        }
    }

    @MainActor @Test func missingCallAudioIsMarkedIncompleteInsteadOfAutoSummarized() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        var microphone = chunk()
        microphone.source = "Microphone"
        let service = MeetingService(directory: root, recorder: StubMeetingRecorder(chunks: [microphone]))
        await service.start(title: "Call", mode: .call, app: MeetingCaptureApp(id: 1, name: "Browser"), provider: .openAI, language: "Auto", participantsInformed: true)
        await service.stop(andSummarize: true)
        #expect(service.processingID == nil)
        #expect(service.records[0].status == .interrupted)
        #expect(service.records[0].error?.contains("No call audio") == true)
    }

    @MainActor @Test(arguments: [true, false]) func systemAudioNeedsNoAppAndBothSourcesReachSummary(microphoneAudible: Bool) async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        var call = chunk()
        call.source = "Call"
        var microphone = chunk()
        microphone.source = "Microphone"
        microphone.hasSpeechLevelAudio = microphoneAudible
        let recorder = StubMeetingRecorder(chunks: [call, microphone])
        var summarizedSources: Set<String> = []
        let service = MeetingService(directory: root, recorder: recorder,
            transcribe: { chunk, _, _ in
                [MeetingSegment(id: chunk.id.uuidString, chunkID: chunk.id, start: chunk.start, end: chunk.start + 1,
                                speaker: chunk.source, text: chunk.source == "Call" ? "Ship Friday." : "I agree.")]
            }, summarize: { segments, _, _, _ in
                summarizedSources = Set(segments.map(\.speaker))
                return summary(segments)
            }, resolveTranscription: { $0 }, validateSummary: { _ in })
        await service.start(title: "Google Meet", mode: .call, app: nil, provider: .codexCLI,
                            language: "Auto", participantsInformed: true, callAudioSource: .system)
        #expect(recorder.starts == 1)
        #expect(recorder.callAudioSource == .system)
        await service.stop(andSummarize: false)
        let saved = try #require(service.selected)
        #expect(saved.status == .recorded)
        #expect(saved.callAudioSource == .system)
        #expect(saved.appName == "System audio")
        #expect(service.store.load().records.first?.callAudioSource == .system)
        await service.process(saved.id, provider: .codexCLI, language: "Auto")?.value
        #expect(summarizedSources == (microphoneAudible ? ["Call", "Microphone"] : ["Call"]))
        #expect(service.selected?.status == .ready)
    }

    @MainActor @Test func selectedAppCannotSilentlyExpandToSystemAudio() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = StubMeetingRecorder(chunks: [])
        let service = MeetingService(directory: root, recorder: recorder)
        await service.start(title: "Missing app", mode: .call, app: nil, provider: .codexCLI,
                            language: "Auto", participantsInformed: true, callAudioSource: .application)
        #expect(recorder.starts == 0)
        #expect(service.records.isEmpty)
        #expect(service.errorMessage?.contains("Select the app") == true)
    }

    @MainActor @Test func silentCallWarnsDuringRecordingAndClearsWhenAudioReturns() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = StubMeetingRecorder(chunks: [])
        let service = MeetingService(directory: root, recorder: recorder)
        await service.start(title: "Meet", mode: .call, app: nil, provider: .codexCLI,
                            language: "Auto", participantsInformed: true, callAudioSource: .system)
        recorder.elapsed = 19
        recorder.audioLevels = ["Microphone": 0.5]
        await service.refreshRecording()
        #expect(service.captureWarning == nil)
        recorder.elapsed = 20
        await service.refreshRecording()
        #expect(service.captureWarning != nil)
        recorder.audioLevels = ["Call": 0.1]
        recorder.elapsed = 21
        await service.refreshRecording()
        #expect(service.captureWarning == nil)
        recorder.audioLevels = [:]
        recorder.elapsed = 41
        await service.refreshRecording()
        #expect(service.captureWarning != nil)
        await service.stop(andSummarize: false)
        #expect(service.captureWarning == nil)
    }

    @MainActor @Test func fullPlaybackMixesBothTracksAndPreservesGaps() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sink = MeetingAudioSink(directory: root, epoch: 0)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24000))
        buffer.frameLength = 24000
        for i in 0..<24000 { buffer.floatChannelData![0][i] = 0.1 }
        sink.append(buffer, source: "Microphone", time: 0)
        sink.append(buffer, source: "Microphone", time: 2)
        for i in 0..<24000 { buffer.floatChannelData![0][i] = 0.2 }
        sink.append(buffer, source: "Call", time: 0.5)
        let chunks = try sink.finish()
        let composition = try await MeetingAudioPlayback.composition(chunks.map { ($0, root.appendingPathComponent($0.fileName)) })
        let tracks = try await composition.loadTracks(withMediaType: .audio)
        #expect(tracks.count == 2)
        #expect(abs(composition.duration.seconds - 3) < 0.001)
        let reader = try AVAssetReader(asset: composition)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 24000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(output)
        #expect(reader.startReading())
        var samples: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            let description = try #require(sample.formatDescription)
            let pcm = try #require(AVAudioPCMBuffer(pcmFormat: AVAudioFormat(cmAudioFormatDescription: description), frameCapacity: AVAudioFrameCount(sample.numSamples)))
            pcm.frameLength = AVAudioFrameCount(sample.numSamples)
            #expect(CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(sample.numSamples), into: pcm.mutableAudioBufferList) == noErr)
            samples.append(contentsOf: UnsafeBufferPointer(start: pcm.floatChannelData![0], count: sample.numSamples))
        }
        #expect(reader.status == .completed)
        #expect(samples.count >= 72000)
        guard samples.count >= 72000 else { return }
        #expect(abs(samples[6000] - 0.1) < 0.01)
        #expect(abs(samples[18000] - 0.3) < 0.01)
        #expect(abs(samples[30000] - 0.2) < 0.01)
        #expect(abs(samples[42000]) < 0.01)
        #expect(abs(samples[54000] - 0.1) < 0.01)
    }

    @Test func notetakerExposesOnlyClosedAudioParts() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sink = MeetingAudioSink(directory: root, epoch: 0, chunkDuration: 20)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24000))
        buffer.frameLength = 24000
        for i in 0..<24000 { buffer.floatChannelData![0][i] = 0.1 }
        for second in 0..<20 { sink.append(buffer, source: "Call", time: Double(second)) }
        #expect(sink.completedChunks().isEmpty)
        sink.append(buffer, source: "Call", time: 20)
        let completed = try #require(sink.completedChunks().first)
        let audio = try AVAudioFile(forReading: root.appendingPathComponent(completed.fileName))
        #expect(audio.length == 480000)
        #expect(completed.duration == 20)
        #expect(try sink.finish().count == 2)
    }

    @MainActor @Test func notetakerPreservesLiveTranscriptAndNotesThenFinishesAutomatically() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        var first = chunk()
        first.source = "Call"
        var last = chunk(start: 60)
        last.source = "Microphone"
        let recorder = StubMeetingRecorder(chunks: [first, last])
        var calls: [UUID] = []
        var summarized: [String] = []
        var pending: CheckedContinuation<Void, Never>?
        let service = MeetingService(directory: root, recorder: recorder, transcribe: { chunk, _, _ in
            calls.append(chunk.id)
            if chunk.id == first.id { await withCheckedContinuation { pending = $0 } }
            return [segment(chunk, text: chunk.source)]
        }, summarize: { segments, _, _, _ in
            summarized = segments.map(\.text)
            return summary(segments)
        }, resolveTranscription: { $0 }, validateSummary: { _ in })
        await service.start(title: "Notetaker", mode: .call, app: nil, provider: .codexCLI, language: "Auto",
                            participantsInformed: true, callAudioSource: .system, notetakerEnabled: true)
        #expect(service.isTakingNotes)
        #expect(recorder.chunkDuration == 20)
        let id = try #require(service.recordingID)
        recorder.readyChunks = [first]
        await service.refreshRecording()
        for _ in 0..<100 where pending == nil { await Task.yield() }
        let continuation = try #require(pending)
        service.updatePersonalNotes(id, text: "Remember the release checklist.")
        continuation.resume()
        for _ in 0..<100 where service.selected?.segments.isEmpty != false { await Task.yield() }
        #expect(service.selected?.segments.count == 1)
        #expect(service.selected?.personalNotes == "Remember the release checklist.")
        await service.refreshRecording()
        #expect(calls == [first.id])
        await service.stop(andSummarize: true)
        for _ in 0..<100 where service.processingID != nil { await Task.yield() }
        #expect(service.selected?.status == .ready)
        #expect(calls == [first.id, last.id])
        #expect(summarized == ["Call", "Microphone"])
        #expect(service.selected?.notetakerEnabled == true)
        #expect(service.store.load().records.first?.segments.count == 2)
    }

    @MainActor @Test func failedLiveTranscriptionKeepsRecordingAndCanResumeAtFinish() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        var audio = chunk()
        audio.source = "Call"
        let recorder = StubMeetingRecorder(chunks: [audio])
        var attempts = 0
        let service = MeetingService(directory: root, recorder: recorder, transcribe: { chunk, _, _ in
            attempts += 1
            if attempts == 1 { throw MeetingError.message("Temporary transcription failure") }
            return [segment(chunk)]
        }, summarize: { segments, _, _, _ in summary(segments) }, resolveTranscription: { $0 }, validateSummary: { _ in })
        await service.start(title: "Retry", mode: .call, app: nil, provider: .codexCLI, language: "Auto",
                            participantsInformed: true, callAudioSource: .system, notetakerEnabled: true)
        recorder.readyChunks = [audio]
        await service.refreshRecording()
        for _ in 0..<100 where service.liveTranscriptError == nil { await Task.yield() }
        #expect(service.liveTranscriptError != nil)
        #expect(service.recordingID != nil)
        #expect(recorder.stops == 0)
        await service.refreshRecording()
        #expect(attempts == 1)
        await service.stop(andSummarize: true)
        for _ in 0..<100 where service.processingID != nil { await Task.yield() }
        #expect(attempts == 2)
        #expect(service.selected?.status == .ready)
    }

    @MainActor @Test func notetakerChecksSetupBeforeRecordingButManualRecordingStillWorks() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = StubMeetingRecorder(chunks: [])
        let service = MeetingService(directory: root, recorder: recorder,
            resolveTranscription: { _ in throw MeetingError.message("Missing speech model") }, validateSummary: { _ in })
        await service.start(title: "Needs setup", mode: .inPerson, app: nil, provider: .codexCLI, language: "Auto",
                            participantsInformed: true, notetakerEnabled: true)
        #expect(recorder.starts == 0)
        #expect(service.records.isEmpty)
        #expect(service.errorMessage?.contains("Missing speech model") == true)
        await service.start(title: "Audio only", mode: .inPerson, app: nil, provider: .codexCLI, language: "Auto", participantsInformed: true)
        #expect(recorder.starts == 1)
        #expect(recorder.chunkDuration == 60)
        await service.stop(andSummarize: false)
    }

    @MainActor @Test func cancelledLiveRequestCannotOverwriteStoppedRecording() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        var audio = chunk()
        audio.source = "Call"
        let recorder = StubMeetingRecorder(chunks: [audio])
        var pending: CheckedContinuation<Void, Never>?
        var summaries = 0
        let service = MeetingService(directory: root, recorder: recorder, transcribe: { chunk, _, _ in
            await withCheckedContinuation { pending = $0 }
            return [segment(chunk)]
        }, summarize: { segments, _, _, _ in summaries += 1; return summary(segments) }, resolveTranscription: { $0 }, validateSummary: { _ in })
        await service.start(title: "Cancel", mode: .call, app: nil, provider: .codexCLI, language: "Auto",
                            participantsInformed: true, callAudioSource: .system, notetakerEnabled: true)
        recorder.readyChunks = [audio]
        await service.refreshRecording()
        for _ in 0..<100 where pending == nil { await Task.yield() }
        let continuation = try #require(pending)
        let stopping = Task { await service.stop(andSummarize: false) }
        for _ in 0..<100 where !service.isStopping { await Task.yield() }
        continuation.resume()
        await stopping.value
        #expect(service.selected?.segments.isEmpty == true)
        #expect(service.selected?.hasPendingTranscription == true)
        #expect(service.selected?.status == .recorded)
        #expect(summaries == 0)
    }

    @MainActor @Test func meetDetectionRejectsOtherSitesAndLobbyURLs() {
        #expect(GoogleMeetMonitor.meetingCode(document: "https://meet.google.com/abc-defg-hij?authuser=1", title: nil) == "abc-defg-hij")
        #expect(GoogleMeetMonitor.meetingCode(document: nil, title: "Meet – abc-defg-hij – Google Chrome") == "abc-defg-hij")
        for url in ["https://meet.google.com.evil.test/abc-defg-hij", "https://example.com/abc-defg-hij", "https://meet.google.com/landing",
                    "http://meet.google.com/abc-defg-hij", "https://user@meet.google.com/abc-defg-hij"] {
            #expect(GoogleMeetMonitor.meetingCode(document: url, title: "Meet - abc-defg-hij") == nil)
        }
        #expect(GoogleMeetMonitor.meetingCode(document: nil, title: "Article about Meet - abc-defg-hij") == nil)
    }

    @MainActor @Test func cancelledSummaryCannotOverwriteSavedMeeting() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        var continuation: CheckedContinuation<MeetingSummary, Never>?
        var record = record()
        var chunk = chunk()
        chunk.transcribed = true
        record.chunks = [chunk]
        record.segments = [segment(chunk)]
        record.status = .recorded
        let service = MeetingService(directory: root, summarize: { _, _, _, _ in
            await withCheckedContinuation { continuation = $0 }
        })
        try service.update(record)
        let task = try #require(service.process(record.id, provider: .openAI, language: "English"))
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        let pending = try #require(continuation)
        service.cancelProcessing()
        pending.resume(returning: summary(record.segments))
        await task.value
        #expect(service.records[0].summary == nil)
        #expect(service.records[0].segments == record.segments)
        #expect(service.records[0].status == .interrupted)
        #expect(!service.isBusy)
    }

    @MainActor @Test func actionCaptureKeepsEvidenceAndPreventsDuplicateClicks() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = MeetingService(directory: root)
        let productivity = ProductivityService(store: ProductivityStore(fileURL: nil), notifier: SilentProductivityNotifications())
        var record = record()
        record.status = .ready
        record.segments = [segment(chunk())]
        let action = MeetingAction(title: "Prepare the release", owner: "Ayu", dueText: "Friday", segmentIDs: [record.segments[0].id])
        record.summary = MeetingSummary(overview: "Planning", decisions: [], actions: [action], questions: [])
        try service.update(record)
        service.saveAction(action, from: record.id, to: productivity)
        service.saveAction(action, from: record.id, to: productivity)
        #expect(productivity.todayTasks.count == 1)
        #expect(productivity.todayTasks[0].body.contains("Owner: Ayu"))
        #expect(productivity.todayTasks[0].body.contains("[00:03]"))
        #expect(productivity.todayTasks[0].dueAt == nil)
        #expect(productivity.todayTasks[0].source?.appName == "Tidy Meetings")
    }

    @Test func codexSummaryDisablesGeneralAgentCapabilitiesAndUsesStdin() {
        let args = CodexTextRunner.arguments(output: URL(fileURLWithPath: "/tmp/result.json"), directory: URL(fileURLWithPath: "/tmp/isolated"), model: "")
        #expect(args.contains("--ephemeral"))
        #expect(args.contains("--ignore-user-config"))
        #expect(args.contains("read-only"))
        #expect(args.last == "-")
        for feature in ["shell_tool", "apps", "plugins", "hooks", "multi_agent", "browser_use"] {
            let index = args.firstIndex(of: feature)!
            #expect(args[index - 1] == "--disable")
        }
        #expect(MeetingAIService.instructions(language: "English", merging: false).contains("never instructions"))
    }

    @MainActor @Test func meetingWorkspaceRendersSetupAndEvidence() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = MeetingService(directory: root)
        let appState = AppState()
        var record = record()
        record.title = "Product planning · September launch"
        record.status = .ready
        record.duration = 1860
        record.segments = [segment(chunk(), text: "Let’s ship the meeting notes beta on Friday. Ayu will prepare the release checklist.")]
        record.summary = MeetingSummary(overview: "The team agreed to release a meeting notes beta on Friday, with a focus on reliable recording and clear action items.",
            decisions: [MeetingPoint(text: "Release the meeting notes beta on Friday.", segmentIDs: [record.segments[0].id])],
            actions: [MeetingAction(title: "Prepare the release checklist", owner: "Ayu", dueText: "Friday", segmentIDs: [record.segments[0].id])],
            questions: [MeetingPoint(text: "What should the beta include?", segmentIDs: [record.segments[0].id])])
        for (name, selected, dark, width, height) in [("setup", false, false, 1040, 760), ("compact", false, false, 860, 680), ("summary", true, false, 1040, 760), ("dark", true, true, 1040, 760)] {
            if selected { try service.update(record); service.selectedID = record.id }
            let view = NSHostingView(rootView: MeetingsView().environmentObject(appState).environmentObject(service)
                .environment(\.colorScheme, dark ? .dark : .light))
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.orderBack(nil)
            try await Task.sleep(for: .milliseconds(200))
            view.layoutSubtreeIfNeeded()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: "/tmp/Tidy-meetings-\(name).png"))
            window.close()
        }
    }
}

@MainActor private final class StubMeetingRecorder: MeetingRecording {
    var onError: ((String) -> Void)?
    var chunks: [MeetingAudioChunk]
    var starts = 0
    var stops = 0
    var elapsed: TimeInterval = 0
    var callAudioSource: MeetingCallAudioSource?
    var audioLevels: [String: Float] = [:]
    var readyChunks: [MeetingAudioChunk] = []
    var chunkDuration: TimeInterval = 60
    init(chunks: [MeetingAudioChunk]) { self.chunks = chunks }
    func start(mode: MeetingMode, appID: Int32?, callAudioSource: MeetingCallAudioSource, directory: URL, chunkDuration: TimeInterval) async throws {
        starts += 1
        elapsed = 0
        self.callAudioSource = callAudioSource
        self.chunkDuration = chunkDuration
    }
    func levels() -> [String: Float] { audioLevels }
    func completedChunks() -> [MeetingAudioChunk] { readyChunks }
    func stop() async throws -> [MeetingAudioChunk] { stops += 1; return chunks }
}

private final class MeetingMockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard request.httpMethod == "POST", request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key" else {
                throw MeetingError.message("Unexpected authentication or HTTP method")
            }
            let responseBody: String
            if request.url?.path == "/v1/audio/transcriptions" {
                guard request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=Tidy-") == true else {
                    throw MeetingError.message("Missing audio multipart boundary")
                }
                responseBody = "{\"segments\":[{\"start\":0,\"end\":1,\"speaker\":\"A\",\"text\":\"Ship on Friday.\"}]}"
            } else if request.url?.path == "/v1/chat/completions" {
                let summary = "{\"overview\":\"Planning\",\"decisions\":[{\"text\":\"Ship Friday\",\"segmentIDs\":[\"s1\"]}],\"actions\":[],\"questions\":[]}"
                let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": summary], "finish_reason": "stop"]]])
                responseBody = String(decoding: data, as: UTF8.self)
            } else { throw MeetingError.message("Unexpected endpoint") }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(responseBody.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

private final class MeetingGeminiMockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard request.url?.host == "generativelanguage.googleapis.com",
                  request.url?.path == "/v1beta/models/gemini-2.5-flash:generateContent",
                  request.httpMethod == "POST",
                  request.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-test-key",
                  request.value(forHTTPHeaderField: "Authorization") == nil else {
                throw MeetingError.message("Unexpected Gemini endpoint or authentication")
            }
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count >= 0 else { throw MeetingError.message("Could not read request body") }
                    if count == 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let contents = json?["contents"] as? [[String: Any]]
            let parts = contents?.first?["parts"] as? [[String: Any]]
            let audio = parts?.first?["inlineData"] as? [String: String]
            let config = json?["generationConfig"] as? [String: Any]
            guard audio?["mimeType"] == "audio/wav",
                  Data(base64Encoded: audio?["data"] ?? "") == Data(repeating: 0, count: 100),
                  config?["responseMimeType"] as? String == "application/json",
                  config?["responseSchema"] != nil, json?["systemInstruction"] != nil else {
                throw MeetingError.message("Missing audio payload or structured transcription instructions")
            }
            let transcript = "{\"segments\":[{\"start\":0,\"end\":1,\"speaker\":\"A\",\"text\":\"Kita rilis hari Jumat.\"}]}"
            let data = try JSONSerialization.data(withJSONObject: ["candidates": [[
                "finishReason": "STOP", "content": ["parts": [["text": "internal reasoning", "thought": true], ["text": transcript]]]
            ]]])
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
