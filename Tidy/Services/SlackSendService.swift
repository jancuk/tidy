import Combine
import Foundation

@MainActor
final class SlackSendService: ObservableObject {
    @Published private(set) var records: [SlackSendRecord] = []
    @Published private(set) var isSending = false
    @Published private(set) var storageError: String?
    @Published private(set) var retryAfter: Date?
    private let store: SlackOutboxStore
    private let writer: any SlackMessageWriting
    private let clock: () -> Date
    private var reviews: [UUID: SlackSendRequest] = [:]
    private var storageReady = false
    private var generation = UUID()

    init(store: SlackOutboxStore, writer: any SlackMessageWriting, clock: @escaping () -> Date = Date.init) {
        self.store = store; self.writer = writer; self.clock = clock
        do {
            records = try store.load().map { record in
                var recovered = record
                if recovered.state == .sending {
                    recovered.state = .uncertain; recovered.detail = SlackSendError.uncertain.localizedDescription
                }
                return recovered
            }
            storageReady = true
            retryAfter = records.compactMap(\.retryAfter).max()
        } catch { storageError = "Could not load sent-message history. Sending is disabled to protect against duplicate messages." }
    }

    func review(_ draft: SlackReplyDraft, checkedUncertainDelivery: Bool = false) throws -> SlackSendRequest {
        guard storageReady else { throw SlackSendError.notSent(storageError ?? "Local send history is unavailable.") }
        guard !isSending else { throw SlackSendError.notSent("Wait for the current message to finish sending.") }
        guard !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draft.text.count <= 4000 else {
            throw SlackSendError.notSent("Write a message of up to 4,000 characters.")
        }
        guard draft.targetChannelID.range(of: "^[CDG][A-Z0-9]+$", options: .regularExpression) != nil else {
            throw SlackSendError.notSent("Enter a Slack channel or DM conversation ID beginning with C, D, or G.")
        }
        guard try writer.scope() == draft.scope else { throw SlackSendError.notSent("The Slack connection changed. Refresh the inbox and review again.") }
        let thread = draft.otherChannelID.isEmpty && draft.destination == .thread ? draft.parentTS : nil
        if hasUncertainDelivery(draft), !checkedUncertainDelivery {
            throw SlackSendError.notSent("An identical message has unconfirmed delivery. Check Slack before reviewing another send.")
        }
        if let thread, thread.range(of: "^[0-9]+\\.[0-9]+$", options: .regularExpression) == nil {
            throw SlackSendError.notSent("This message has no valid thread timestamp. Choose a new conversation message instead.")
        }
        let request = SlackSendRequest(id: UUID(), topicID: draft.topicID, scope: draft.scope, channelID: draft.targetChannelID,
                                       destinationLabel: draft.destinationLabel, threadTS: thread, text: draft.text, reviewedAt: clock())
        reviews = [request.id: request]
        return request
    }

    func cancelReview(_ id: UUID) { reviews[id] = nil }

    @discardableResult
    func sendApproved(_ id: UUID) async throws -> SlackSendRecord {
        guard !isSending, let request = reviews[id], !records.contains(where: { $0.id == id }) else {
            throw SlackSendError.notSent("Review the message before confirming a send.")
        }
        reviews[id] = nil
        guard clock().timeIntervalSince(request.reviewedAt) < 300 else {
            throw SlackSendError.notSent("This review expired. Review the message again before sending.")
        }
        guard try writer.scope() == request.scope else { throw SlackSendError.notSent("The Slack connection changed. Review again before sending.") }
        if let retryAfter, retryAfter > clock() {
            throw SlackSendError.notSent("Sending is paused until \(retryAfter.formatted(date: .omitted, time: .shortened)). Review again after the cooldown.")
        }
        var record = SlackSendRecord(request: request, state: .sending)
        var next = records; next.append(record)
        try store.save(next)
        records = next; isSending = true
        let token = generation
        defer { isSending = false }
        do {
            record.receipt = try await writer.send(request)
            record.state = .sent
        } catch SlackSendError.notSent(let message, let delay) {
            record.state = .failed; record.detail = message
            if let delay { record.retryAfter = clock().addingTimeInterval(max(60, delay)) }
        } catch {
            record.state = .uncertain; record.detail = SlackSendError.uncertain.localizedDescription
        }
        guard token == generation else { return record }
        if let cooldown = record.retryAfter { retryAfter = cooldown }
        if let index = records.firstIndex(where: { $0.id == id }) { records[index] = record }
        do { try store.save(records) }
        catch { storageError = "The delivery result could not be saved locally. Check Slack before sending again." }
        return record
    }

    func latest(for topicID: String, scope: String) -> SlackSendRecord? {
        records.last { $0.request.topicID == topicID && $0.request.scope == scope }
    }

    func hasUncertainDelivery(_ draft: SlackReplyDraft) -> Bool {
        records.contains {
            ($0.state == .uncertain || $0.state == .sending) && $0.request.scope == draft.scope
                && $0.request.channelID == draft.targetChannelID && $0.request.text == draft.text
                && $0.request.threadTS == (draft.otherChannelID.isEmpty && draft.destination == .thread ? draft.parentTS : nil)
        }
    }

    func reset() {
        guard !isSending else { return }
        reviews = [:]
        generation = UUID()
        do { try store.save([]); records = []; storageError = nil; storageReady = true }
        catch { storageError = "Could not clear local send history." }
    }
}
