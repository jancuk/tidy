import Foundation

struct GrammarProviderAttemptFailure: Sendable {
    let providerID: String
    let providerName: String
    let message: String
    let statusCode: Int?
    let durationMs: Int
}

struct GrammarCorrectionResult: Sendable {
    let correctedText: String
    let providerID: String
    let providerName: String
    let failures: [GrammarProviderAttemptFailure]
    let chunkCount: Int

    var usedFallback: Bool { !failures.isEmpty }
}

enum GrammarCorrectionPipelineError: LocalizedError {
    case noAvailableProvider
    case allProvidersFailed([GrammarProviderAttemptFailure])
    case implausibleCorrection(String)

    var errorDescription: String? {
        switch self {
        case .noAvailableProvider:
            return "No available grammar provider is configured. Add a provider or fallback in Settings."
        case .allProvidersFailed(let failures):
            let names = failures.map(\.providerName).uniqued().joined(separator: ", ")
            return "Couldn't tidy after trying \(names). Your text is unchanged."
        case .implausibleCorrection(let provider):
            return "\(provider) returned text that did not look like a safe grammar correction."
        }
    }
}

enum GrammarCorrectionPipeline {
    static let maximumInputCharacters = 100_000
    static let defaultChunkCharacters = 1_500
    static let noFallbackValue = "none"

    static func configuredProviderIDs(defaults: UserDefaults = .standard) -> [GrammarProviderID] {
        let rawValues = [
            defaults.string(forKey: AppDefaults.grammarProvider) ?? GrammarProviderID.gemini.rawValue,
            defaults.string(forKey: AppDefaults.grammarFallbackProvider1) ?? noFallbackValue,
            defaults.string(forKey: AppDefaults.grammarFallbackProvider2) ?? noFallbackValue,
        ]

        var seen = Set<GrammarProviderID>()
        let configured = rawValues.compactMap(GrammarProviderID.init(rawValue:)).filter { seen.insert($0).inserted }
        guard AppPrivacyPolicy.isLocalOnlyAIEnabled else { return configured }
        return configured.filter(\.processesContentLocally)
    }

    static func estimatedChunkCount(for text: String) -> Int {
        GrammarTextChunker.chunks(text, maximumCharacters: defaultChunkCharacters).count
    }

    static func correct(
        _ text: String,
        providerIDs: [GrammarProviderID]? = nil,
        language: String? = nil
    ) async throws -> GrammarCorrectionResult {
        let ids = providerIDs ?? configuredProviderIDs()
        let providers: [any GrammarProvider] = ids.map(GrammarProviderFactory.provider(for:))
        return try await correct(text, providers: providers, language: language)
    }

    static func correct(
        _ text: String,
        providers: [any GrammarProvider],
        language: String? = nil,
        chunkCharacters: Int = defaultChunkCharacters
    ) async throws -> GrammarCorrectionResult {
        guard !providers.isEmpty else {
            if AppPrivacyPolicy.isLocalOnlyAIEnabled {
                throw AppPrivacyError.localOnlyProviderRequired
            }
            throw GrammarCorrectionPipelineError.noAvailableProvider
        }

        let chunks = GrammarTextChunker.chunks(text, maximumCharacters: chunkCharacters)
        var failures: [GrammarProviderAttemptFailure] = []

        for provider in providers {
            try Task.checkCancellation()
            let start = Date()

            do {
                let correctedParts = try await correctChunks(chunks, with: provider, language: language)

                return GrammarCorrectionResult(
                    correctedText: correctedParts.joined(),
                    providerID: provider.id,
                    providerName: provider.displayName,
                    failures: failures,
                    chunkCount: chunks.count
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw error
            } catch {
                failures.append(GrammarProviderAttemptFailure(
                    providerID: provider.id,
                    providerName: provider.displayName,
                    message: error.localizedDescription,
                    statusCode: httpStatus(from: error),
                    durationMs: Int(Date().timeIntervalSince(start) * 1_000)
                ))
            }
        }

        throw GrammarCorrectionPipelineError.allProvidersFailed(failures)
    }

    private static func isPlausibleCorrection(original: String, corrected: String) -> Bool {
        guard !corrected.isEmpty else { return false }
        let originalCount = original.count
        let correctedCount = corrected.count
        if abs(correctedCount - originalCount) < 80 { return true }
        let ratio = Double(correctedCount) / Double(max(originalCount, 1))
        return ratio >= 0.4 && ratio <= 2.5
    }

    private static func correctChunks(
        _ chunks: [GrammarTextChunk],
        with provider: any GrammarProvider,
        language: String?
    ) async throws -> [String] {
        let serialProviderIDs: Set<String> = [
            GrammarProviderID.codexCLI.rawValue,
            GrammarProviderID.claudeCLI.rawValue,
            GrammarProviderID.ollama.rawValue,
        ]
        let maximumConcurrentRequests = serialProviderIDs.contains(provider.id) ? 1 : 3

        func processChunk(at index: Int) async throws -> (Int, String) {
            let chunk = chunks[index]
            guard !chunk.body.isEmpty else { return (index, chunk.original) }
            let corrected = try await provider.fixGrammar(chunk.body, language: language)
            let cleaned = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isPlausibleCorrection(original: chunk.body, corrected: cleaned) else {
                throw GrammarCorrectionPipelineError.implausibleCorrection(provider.displayName)
            }
            return (index, chunk.applying(cleaned))
        }

        return try await withThrowingTaskGroup(of: (Int, String).self) { group in
            var results = Array(repeating: "", count: chunks.count)
            var nextIndex = 0

            while nextIndex < min(maximumConcurrentRequests, chunks.count) {
                let index = nextIndex
                group.addTask { try await processChunk(at: index) }
                nextIndex += 1
            }

            while let (index, corrected) = try await group.next() {
                results[index] = corrected
                if nextIndex < chunks.count {
                    let indexToAdd = nextIndex
                    group.addTask { try await processChunk(at: indexToAdd) }
                    nextIndex += 1
                }
            }
            return results
        }
    }

    private static func httpStatus(from error: Error) -> Int? {
        if case GrammarProviderError.httpError(let status, _) = error { return status }
        return nil
    }
}

struct GrammarTextChunk: Equatable, Sendable {
    let original: String
    let leadingWhitespace: String
    let body: String
    let trailingWhitespace: String

    init(original: String) {
        self.original = original

        guard let firstBodyIndex = original.firstIndex(where: { !$0.isWhitespace }),
              let lastBodyIndex = original.lastIndex(where: { !$0.isWhitespace }) else {
            leadingWhitespace = original
            body = ""
            trailingWhitespace = ""
            return
        }

        let afterLastBodyIndex = original.index(after: lastBodyIndex)
        leadingWhitespace = String(original[..<firstBodyIndex])
        body = String(original[firstBodyIndex..<afterLastBodyIndex])
        trailingWhitespace = String(original[afterLastBodyIndex...])
    }

    func applying(_ correctedBody: String) -> String {
        guard !body.isEmpty else { return original }
        return leadingWhitespace + correctedBody + trailingWhitespace
    }
}

enum GrammarTextChunker {
    static func chunks(_ text: String, maximumCharacters: Int) -> [GrammarTextChunk] {
        guard !text.isEmpty else { return [GrammarTextChunk(original: text)] }
        let limit = max(200, maximumCharacters)
        guard text.count > limit else { return [GrammarTextChunk(original: text)] }

        var result: [GrammarTextChunk] = []
        var start = text.startIndex

        while text.distance(from: start, to: text.endIndex) > limit {
            let hardEnd = text.index(start, offsetBy: limit)
            let minimumBoundary = text.index(start, offsetBy: limit / 2)
            let searchRange = start..<hardEnd
            let patterns = ["\n\n", "\n", ". ", "? ", "! ", "; ", ", ", " "]

            let preferredEnd = patterns.compactMap { pattern -> String.Index? in
                guard let range = text.range(of: pattern, options: .backwards, range: searchRange),
                      range.upperBound >= minimumBoundary else { return nil }
                return range.upperBound
            }.max() ?? hardEnd

            result.append(GrammarTextChunk(original: String(text[start..<preferredEnd])))
            start = preferredEnd
        }

        if start < text.endIndex {
            result.append(GrammarTextChunk(original: String(text[start...])))
        }
        return result
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
