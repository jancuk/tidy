import Combine
import Foundation

@MainActor
final class SlackReplyService: ObservableObject {
    @Published private(set) var snapshot = SlackReplySnapshot()
    @Published private(set) var storageReady = false
    @Published private(set) var isWorking = false
    @Published private(set) var status = "Connect your Slack inbox"
    @Published private(set) var errorMessage: String?
    private let store: SlackReplyStore
    private let reader: any SlackReplyReading
    private let generator: any SlackReplyGenerating
    private let clock: () -> Date
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var generation = UUID()

    init(store: SlackReplyStore, reader: any SlackReplyReading, generator: any SlackReplyGenerating, clock: @escaping () -> Date = Date.init) {
        self.store = store; self.reader = reader; self.generator = generator; self.clock = clock
        reload()
    }

    var activeTopics: [SlackReplyTopic] { snapshot.topics.filter { !$0.isDismissed }.sorted { $0.latest.date > $1.latest.date } }
    var clearedTopics: [SlackReplyTopic] { snapshot.topics.filter(\.isDismissed).sorted { $0.latest.date > $1.latest.date } }
    var nextRefresh: Date? {
        guard snapshot.settings.enabled, snapshot.settings.autoRefresh else { return nil }
        return max(snapshot.retryAfter ?? .distantPast, (snapshot.lastAttempt ?? clock()).addingTimeInterval(Double(snapshot.settings.refreshMinutes * 60)))
    }

    func reload() {
        do {
            snapshot = try store.load(); storageReady = true; errorMessage = nil
            status = snapshot.settings.enabled ? "\(activeTopics.count) saved discussions · ready when you are" : "Connect your Slack inbox"
        }
        catch { storageReady = false; errorMessage = "Could not load the Slack inbox. The original file is preserved. \(error.localizedDescription)" }
    }

    func start() {
        timer?.invalidate(); timer = nil
        guard storageReady, snapshot.settings.enabled, snapshot.settings.autoRefresh else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshIfDue() }
        }
        refreshIfDue()
    }

    private func refreshIfDue() {
        guard !isWorking else { return }
        refreshTask = Task { await refresh() }
    }

    @discardableResult func configure(_ settings: SlackReplySettings) -> Bool {
        do {
            let validated = try settings.validated()
            var next = snapshot
            if validated.names != next.settings.names || validated.userID != next.settings.userID || validated.includeDirectMessages != next.settings.includeDirectMessages {
                next = SlackReplySnapshot()
            }
            next.settings = validated
            generation = UUID()
            refreshTask?.cancel()
            guard commit(next) else { return false }
            start()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func refresh(force: Bool = false) async {
        guard storageReady, snapshot.settings.enabled, (force || snapshot.settings.autoRefresh), !isWorking else { return }
        let now = clock()
        if let retry = snapshot.retryAfter, retry > now {
            status = "Paused until \(retry.formatted(date: .omitted, time: .shortened))"; return
        }
        let interval = force ? 60.0 : Double(snapshot.settings.refreshMinutes * 60)
        if let last = snapshot.lastAttempt, now.timeIntervalSince(last) < interval { return }
        isWorking = true; errorMessage = nil
        let token = generation
        defer { isWorking = false }
        var attempt = snapshot; attempt.lastAttempt = now
        guard commit(attempt) else { return }
        do {
            let scope = try reader.scope()
            if !snapshot.scope.isEmpty && snapshot.scope != scope {
                var fresh = SlackReplySnapshot(); fresh.settings = snapshot.settings; fresh.scope = scope; fresh.lastAttempt = now
                guard commit(fresh) else { return }
            }
            var next = snapshot; next.scope = scope
            if next.pendingSearches.isEmpty {
                let since = max(now.addingTimeInterval(-90 * 86400), (next.lastRefresh ?? now.addingTimeInterval(-6 * 86400)).addingTimeInterval(-86400))
                next.pendingSearches = next.settings.queries(since: since).map { SlackSearchJob(query: $0) }
                next.scanStartedAt = now
            }
            guard commit(next) else { return }
            for _ in 0..<4 {
                guard let job = snapshot.pendingSearches.first else { break }
                status = "Checking mentions · page \(job.page)"
                let page: SlackSearchPage
                do {
                    page = try await reader.search(query: job.query, page: job.page, count: job.count)
                } catch MCPError.responseTooLarge where job.count > 1 {
                    try validate(token)
                    var smaller = snapshot
                    smaller.pendingSearches[0] = SlackSearchJob(query: job.query, count: max(1, job.count / 2))
                    guard commit(smaller) else { return }
                    status = "Workbench response was too large · reducing the page size"
                    continue
                }
                try validate(token)
                var updated = snapshot
                Self.merge(page.messages, into: &updated, userID: updated.settings.userID)
                updated.pendingSearches.removeFirst()
                if page.hasMore {
                    updated.pendingSearches.append(SlackSearchJob(query: job.query, page: job.page + 1, count: job.count))
                }
                guard commit(updated) else { return }
            }
            if snapshot.pendingSearches.isEmpty {
                var finished = snapshot; finished.lastRefresh = finished.scanStartedAt ?? now; finished.scanStartedAt = nil; finished.retryAfter = nil
                guard commit(finished) else { return }
            }
            let candidates = activeTopics.filter {
                !$0.analysisIsCurrent || ($0.contextFetchedAt.map { now.timeIntervalSince($0) > 3600 } ?? true)
            }.sorted {
                if $0.analysisIsCurrent != $1.analysisIsCurrent { return !$0.analysisIsCurrent }
                let left = $0.contextAttemptAt ?? .distantPast
                let right = $1.contextAttemptAt ?? .distantPast
                if left != right { return left < right }
                return $0.latest.date > $1.latest.date
            }.prefix(3).map(\.id)
            var ready: [SlackReplyTopic] = []
            for id in candidates {
                if let topic = try await loadContext(id, token: token), !topic.analysisIsCurrent { ready.append(topic) }
            }
            if !ready.isEmpty {
                status = "Preparing reply options for \(ready.count) discussions"
                let analyses = try await generator.analyze(ready, settings: snapshot.settings)
                try validate(token)
                var updated = snapshot
                for analysis in analyses {
                    guard let original = ready.first(where: { $0.id == analysis.topicID }),
                          let index = updated.topics.firstIndex(where: { $0.id == analysis.topicID }),
                          !updated.topics[index].isDismissed, updated.topics[index].fingerprint == original.fingerprint else { continue }
                    updated.topics[index].analysis = analysis
                    updated.topics[index].analysisFingerprint = original.fingerprint
                    updated.topics[index].lastError = nil
                }
                guard commit(updated) else { return }
            }
            status = snapshot.pendingSearches.isEmpty ? "You're up to date with the fetched messages" : "More results queued for the next refresh"
        } catch is CancellationError { status = "Refresh stopped" }
        catch { record(error) }
    }

    func generate(for id: String, custom: String? = nil) async {
        guard storageReady, snapshot.settings.enabled, !isWorking else { return }
        if let retry = snapshot.retryAfter, retry > clock() { status = "Waiting for the API cooldown"; return }
        if let custom, custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || custom.count > 1500 {
            errorMessage = "Enter up to 1,500 characters describing the reply you want."; return
        }
        isWorking = true; errorMessage = nil; status = "Reading discussion context…"
        let token = generation
        defer { isWorking = false }
        do {
            guard snapshot.scope == (try reader.scope()) else {
                throw SlackReplyError.message("The Slack connection changed. Refresh the inbox before generating replies.")
            }
            guard let topic = try await loadContext(id, token: token) else { return }
            status = custom == nil ? "Preparing two reply options…" : "Refining your reply…"
            let option: SlackReplyOption?
            let analysis: SlackReplyAnalysis?
            if let custom { option = try await generator.refine(topic, instruction: custom, settings: snapshot.settings); analysis = nil }
            else { analysis = try await generator.analyze([topic], settings: snapshot.settings).first; option = nil }
            try validate(token)
            var next = snapshot
            guard let index = next.topics.firstIndex(where: { $0.id == id }), !next.topics[index].isDismissed,
                  next.topics[index].fingerprint == topic.fingerprint else { return }
            if let option { next.topics[index].customOption = option; next.topics[index].customInstruction = custom }
            if let analysis { next.topics[index].analysis = analysis; next.topics[index].analysisFingerprint = topic.fingerprint }
            next.topics[index].lastError = nil
            if commit(next) { status = "Suggestions ready · nothing sent" }
        } catch is CancellationError { status = "Stopped" }
        catch { record(error) }
    }

    private func loadContext(_ id: String, token: UUID) async throws -> SlackReplyTopic? {
        guard var topic = snapshot.topics.first(where: { $0.id == id && !$0.isDismissed }) else { return nil }
        if let fetched = topic.contextFetchedAt, clock().timeIntervalSince(fetched) < 3600, topic.context.contains(where: { $0.ts == topic.latest.ts && $0.text == topic.latest.text }) { return topic }
        status = "Loading #\(topic.latest.channelName) · reads are paced to respect Slack limits"
        if let index = snapshot.topics.firstIndex(where: { $0.id == id }) {
            var attempted = snapshot; attempted.topics[index].contextAttemptAt = clock()
            guard commit(attempted) else { return nil }
        }
        do {
            let response = try await reader.context(for: topic.latest)
            try validate(token)
            guard let index = snapshot.topics.firstIndex(where: { $0.id == id && !$0.isDismissed }) else { return nil }
            topic = snapshot.topics[index]
            topic.context = response.messages
            topic.contextIsPartial = response.partial || !response.messages.contains { $0.ts == topic.latest.ts }
            topic.contextFetchedAt = clock()
            topic.customOption = nil; topic.customInstruction = nil
            var next = snapshot; next.topics[index] = topic
            guard commit(next) else { return nil }
            return topic
        } catch {
            if error is CancellationError || SlackReadGate.retryDelay(error) != nil { throw error }
            var next = snapshot
            if let index = next.topics.firstIndex(where: { $0.id == id }) {
                next.topics[index].lastError = "Context unavailable: \(error.localizedDescription)"
                _ = commit(next)
            }
            return nil
        }
    }

    func clear(_ ids: Set<String>) {
        var next = snapshot
        for index in next.topics.indices where ids.contains(next.topics[index].id) {
            next.topics[index].dismissedThrough = next.topics[index].latest.ts
            next.topics[index].analysis = nil; next.topics[index].analysisFingerprint = nil
            next.topics[index].customOption = nil; next.topics[index].customInstruction = nil
        }
        _ = commit(next)
    }

    func restore(_ id: String) {
        var next = snapshot
        if let index = next.topics.firstIndex(where: { $0.id == id }) { next.topics[index].dismissedThrough = nil }
        _ = commit(next)
    }

    func copied(_ id: String) {
        var next = snapshot
        if let index = next.topics.firstIndex(where: { $0.id == id }) { next.topics[index].copiedAt = clock() }
        _ = commit(next)
    }

    func topics(on day: Date) -> [SlackReplyTopic] {
        snapshot.topics.compactMap { topic in
            var scoped = topic
            scoped.mentions = topic.mentions.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            guard !scoped.mentions.isEmpty else { return nil }
            scoped.context = topic.context.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            scoped.contextIsPartial = topic.contextIsPartial || scoped.context.count != topic.context.count
            return scoped
        }.sorted { $0.latest.date > $1.latest.date }
    }

    func dailyRecap(for day: Date) async {
        guard storageReady, !isWorking else { return }
        let topics = Array(topics(on: day).prefix(12))
        guard !topics.isEmpty else { return }
        let key = Self.dayKey(day)
        let fingerprint = SlackReplyFingerprint.make(topics.map(\.fingerprint).joined())
        if snapshot.recaps.contains(where: { $0.day == key && $0.fingerprint == fingerprint }) { return }
        isWorking = true; errorMessage = nil; status = "Summarizing saved discussion context…"
        let token = generation
        defer { isWorking = false }
        do {
            let text = try await generator.recap(topics, day: key)
            try validate(token)
            var next = snapshot
            next.recaps.removeAll { $0.day == key }
            next.recaps.append(SlackDailyRecap(day: key, text: text, fingerprint: fingerprint, generatedAt: clock()))
            if commit(next) { status = "Daily recap ready" }
        } catch is CancellationError { status = "Stopped" }
        catch { record(error) }
    }

    static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    func reset() {
        generation = UUID(); refreshTask?.cancel(); timer?.invalidate(); timer = nil
        var fresh = SlackReplySnapshot(); fresh.settings = snapshot.settings; fresh.settings.enabled = false
        _ = commit(fresh)
    }

    static func merge(_ messages: [SlackReplyMessage], into value: inout SlackReplySnapshot, userID: String) {
        for message in messages where message.user != userID || userID.isEmpty {
            if let index = value.topics.firstIndex(where: { $0.id == message.topicID }) {
                if let old = value.topics[index].mentions.firstIndex(where: { $0.id == message.id }) { value.topics[index].mentions[old] = message }
                else { value.topics[index].mentions.append(message) }
                value.topics[index].mentions.sort { $0.date < $1.date }
                if !value.topics[index].analysisIsCurrent { value.topics[index].customOption = nil }
            } else { value.topics.append(SlackReplyTopic(id: message.topicID, mentions: [message])) }
        }
    }

    func loadPreview() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil else { return }
        var preview = SlackReplySnapshot()
        preview.settings.enabled = true; preview.settings.autoRefresh = false; preview.settings.userID = "UME"
        preview.scope = "local-slack-preview"
        Self.merge(SlackReplyPreviewReader.messages, into: &preview, userID: "UME")
        for index in preview.topics.indices {
            preview.topics[index].context = preview.topics[index].mentions
            preview.topics[index].contextFetchedAt = clock()
            preview.topics[index].contextIsPartial = false
            preview.topics[index].analysis = SlackReplyPreviewGenerator.analysis(preview.topics[index])
            preview.topics[index].analysisFingerprint = preview.topics[index].fingerprint
        }
        preview.lastRefresh = clock()
        _ = commit(preview)
        status = "Local preview · no Slack requests"
    }

    private func validate(_ token: UUID) throws {
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
    }

    private func record(_ error: Error) {
        errorMessage = error.localizedDescription
        if let delay = SlackReadGate.retryDelay(error) {
            var next = snapshot; next.retryAfter = clock().addingTimeInterval(delay); _ = commit(next)
        }
        status = "Refresh incomplete · saved discussions kept"
    }

    @discardableResult private func commit(_ value: SlackReplySnapshot) -> Bool {
        guard storageReady else { return false }
        do {
            var retained = value
            let cutoff = clock().addingTimeInterval(-90 * 86400)
            retained.topics.removeAll { $0.latest.date < cutoff }
            retained.recaps.removeAll { $0.generatedAt < cutoff }
            try store.save(retained); snapshot = retained; return true
        }
        catch { errorMessage = "Could not save the Slack inbox locally: \(error.localizedDescription)"; return false }
    }
}
