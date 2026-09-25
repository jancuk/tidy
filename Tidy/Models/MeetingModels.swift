import Foundation

enum MeetingLimits {
    static let maximumRecordingDuration: TimeInterval = 2 * 60 * 60
}

enum MeetingMode: String, Codable, CaseIterable, Identifiable {
    case inPerson, call
    var id: String { rawValue }
    var title: String { self == .inPerson ? "In person" : "Online call" }
}

enum MeetingCallAudioSource: String, Codable, CaseIterable, Identifiable {
    case system, application
    var id: String { rawValue }
    var title: String { self == .system ? "System audio (Google Meet)" : "Selected app" }
}

enum MeetingSummaryProvider: String, Codable, CaseIterable, Identifiable {
    case openAI, codexCLI, typeSafe
    var id: String { rawValue }
    var title: String {
        switch self {
        case .openAI: "OpenAI API"
        case .codexCLI: "Codex CLI"
        case .typeSafe: "TypeSafe / Jev — transcript excerpts"
        }
    }

    func validatePrivacy(localOnly: Bool = AppPrivacyPolicy.isLocalOnlyAIEnabled) throws {
        if localOnly { throw AppPrivacyError.localOnlyProviderRequired }
    }

    func resolvedModel(_ override: String, defaults: UserDefaults = .standard) -> String {
        let model = override.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty { return model }
        if self == .typeSafe { return "jev-latest" }
        return self == .codexCLI
            ? (defaults.string(forKey: AppDefaults.codexCLIModel) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            : "gpt-4.1-mini"
    }
}

enum MeetingTranscriptionProvider: String, Codable, CaseIterable, Identifiable {
    case localWhisper, automatic, gemini, openAI
    var id: String { rawValue }
    var title: String {
        switch self {
        case .localWhisper: "Local Whisper (no API key)"
        case .automatic: "Automatic (saved API key)"
        case .gemini: "Gemini"
        case .openAI: "OpenAI API"
        }
    }
    var providerID: GrammarProviderID? {
        switch self {
        case .automatic, .localWhisper: nil
        case .gemini: .gemini
        case .openAI: .openAI
        }
    }

    func validatePrivacy() throws {
        if let providerID { try AppPrivacyPolicy.validateAIProvider(providerID) }
        else if self != .localWhisper { throw MeetingError.message("Choose a transcription provider before processing.") }
    }
}

enum MeetingStatus: String, Codable {
    case recording, recorded, processing, transcribed, ready, interrupted
    var title: String { rawValue.capitalized }
}

struct MeetingAudioChunk: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var fileName: String
    var source: String
    var start: TimeInterval
    var duration: TimeInterval
    var hasSpeechLevelAudio: Bool
    var transcribed = false
}

struct MeetingSegment: Codable, Identifiable, Equatable {
    var id: String
    var chunkID: UUID
    var start: TimeInterval
    var end: TimeInterval
    var speaker: String
    var text: String
}

struct MeetingPoint: Codable, Equatable {
    var text: String
    var segmentIDs: [String]
}

struct MeetingAction: Codable, Equatable, Identifiable {
    var title: String
    var owner: String?
    var dueText: String?
    var segmentIDs: [String]
    var id: String { title + "|" + segmentIDs.joined(separator: ",") }
}

struct MeetingSummary: Codable, Equatable {
    enum Format: String, Codable { case written, transcriptExcerpts }

    var overview: String
    var decisions: [MeetingPoint]
    var actions: [MeetingAction]
    var questions: [MeetingPoint]
    var format: Format?

    var referencedSegmentIDs: [String] {
        decisions.flatMap(\.segmentIDs) + actions.flatMap(\.segmentIDs) + questions.flatMap(\.segmentIDs)
    }

    func mappingSegmentIDs(_ transform: (String) throws -> String) rethrows -> Self {
        var result = self
        result.decisions = try decisions.map { MeetingPoint(text: $0.text, segmentIDs: try $0.segmentIDs.map(transform)) }
        result.actions = try actions.map {
            MeetingAction(title: $0.title, owner: $0.owner, dueText: $0.dueText, segmentIDs: try $0.segmentIDs.map(transform))
        }
        result.questions = try questions.map { MeetingPoint(text: $0.text, segmentIDs: try $0.segmentIDs.map(transform)) }
        return result
    }

    static func decode(_ answer: String, validSegmentIDs: Set<String>) throws -> Self {
        var json = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```"), let newline = json.firstIndex(of: "\n"), json.hasSuffix("```") {
            json = String(json[json.index(after: newline)...].dropLast(3))
        }
        let result = try JSONDecoder().decode(Self.self, from: Data(json.utf8))
        let references = result.decisions.map(\.segmentIDs) + result.actions.map(\.segmentIDs) + result.questions.map(\.segmentIDs)
        guard !result.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              references.allSatisfy({ !$0.isEmpty && Set($0).isSubset(of: validSegmentIDs) }) else {
            throw MeetingError.message("The summary contained missing or invalid transcript references. Your transcript is saved; try summarizing again.")
        }
        return result
    }
}

struct MeetingRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var createdAt = Date()
    var duration: TimeInterval = 0
    var mode: MeetingMode
    var appName: String?
    var callAudioSource: MeetingCallAudioSource?
    var summaryProvider: MeetingSummaryProvider
    var summaryLanguage: String
    var transcriptionProvider: MeetingTranscriptionProvider?
    var summaryModel: String?
    var recordingLimitReached: Bool?
    var personalNotes: String?
    var notetakerEnabled: Bool?
    var status: MeetingStatus = .recording
    var chunks: [MeetingAudioChunk] = []
    var segments: [MeetingSegment] = []
    var summary: MeetingSummary?
    var error: String?
    var savedActionIDs: [String] = []

    var hasPendingTranscription: Bool { chunks.contains { !$0.transcribed } }
    var summaryFormat: MeetingSummary.Format {
        summary?.format ?? (summaryProvider == .typeSafe ? .transcriptExcerpts : .written)
    }
    var canCreateNotes: Bool { !segments.isEmpty && !hasPendingTranscription }
    var displayStatus: String {
        if status == .recording { return "Recording" }
        if status == .processing { return "Processing" }
        if status == .interrupted { return "Needs attention" }
        if summary != nil { return "Notes ready" }
        if !hasPendingTranscription && !chunks.isEmpty { return segments.isEmpty ? "No speech found" : "Transcript ready" }
        return "Audio saved"
    }

    var orderedSegments: [MeetingSegment] {
        segments.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    var transcript: String {
        orderedSegments.map { "[\(Self.timestamp($0.start))] \($0.speaker): \($0.text)" }.joined(separator: "\n\n")
    }

    var markdown: String {
        var text = "# \(title)\n\n\(createdAt.formatted()) · \(Self.timestamp(duration)) · \(mode.title)\n"
        if let summary {
            text += "\n## \(summaryFormat == .transcriptExcerpts ? "Transcript highlights" : "Summary")\n\n\(summary.overview)\n\n## Decisions\n\n"
            text += summary.decisions.map { "- \($0.text)\(citations($0.segmentIDs))" }.joined(separator: "\n")
            if summary.decisions.isEmpty { text += "No explicit decisions recorded." }
            text += "\n\n## Action items\n\n"
            text += summary.actions.map { "- [ ] \($0.title)\($0.owner.map { " — " + $0 } ?? "")\($0.dueText.map { " · " + $0 } ?? "")\(citations($0.segmentIDs))" }.joined(separator: "\n")
            if summary.actions.isEmpty { text += "No explicit follow-ups recorded." }
            text += "\n\n## Open questions\n\n"
            text += summary.questions.map { "- \($0.text)\(citations($0.segmentIDs))" }.joined(separator: "\n")
            if summary.questions.isEmpty { text += "No open questions recorded." }
        }
        if let personalNotes, !personalNotes.isEmpty { text += "\n\n## Your notes\n\n" + personalNotes }
        return text + "\n\n## Transcript\n\n" + transcript + "\n"
    }

    private func citations(_ ids: [String]) -> String {
        let times = ids.compactMap { id in segments.first { $0.id == id }.map { Self.timestamp($0.start) } }
        return times.isEmpty ? "" : " [" + times.joined(separator: ", ") + "]"
    }

    static func timestamp(_ seconds: TimeInterval) -> String {
        let value = seconds.isFinite ? max(0, Int(seconds)) : 0
        return value >= 3600
            ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
            : String(format: "%02d:%02d", value / 60, value % 60)
    }
}

enum MeetingError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}
