import SwiftUI

struct SlackReplyComposer: View {
    @EnvironmentObject private var sender: SlackSendService
    @Environment(\.dismiss) private var dismiss
    @State var draft: SlackReplyDraft
    @State private var review: SlackSendRequest?
    @State private var result: SlackSendRecord?
    @State private var error: String?
    @State private var sending = false
    @State private var otherDestination = false
    @State private var checkedUncertainDelivery = false

    private var validText: Bool { !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.text.count <= 4000 }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if let result { deliveryResult(result) }
            else if let review { confirmation(review) }
            else { editor }
            if let error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if let error = sender.storageError { Text(error).font(.caption).foregroundStyle(.orange) }
            Divider()
            footer
        }
        .padding(28).frame(width: 650)
        .background(WorkspaceDesign.canvas)
        .interactiveDismissDisabled(sending)
        .onAppear { if draft.channelID.isEmpty { otherDestination = true } }
        .onDisappear { if let review { sender.cancelReview(review.id) } }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: result?.state == .sent ? "checkmark.bubble.fill" : "square.and.pencil")
                .font(.system(size: 24)).foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44).background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(result != nil ? "Your message" : review == nil ? "Make it yours." : "Ready to send?")
                    .font(.system(size: 27, design: .serif))
                Text(review == nil ? "Write, review, then send to Slack." : "Confirm this exact message and destination.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(result?.state == .sent ? "SENT" : review == nil ? "DRAFT" : "REVIEW")
                .font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("TO").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if !draft.channelID.isEmpty {
                        Toggle("Another channel or DM", isOn: $otherDestination).toggleStyle(.checkbox)
                            .font(.system(size: 11)).accessibilityIdentifier("slack-other-destination")
                    }
                }
                if otherDestination {
                    TextField("Channel or DM conversation ID (C…, D…, or G…)", text: $draft.otherChannelID)
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("slack-send-channel")
                    Text("Find the conversation ID in Slack’s channel details or its link. This posts a new message to that conversation.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text(draft.isDM ? "Direct message" : "#\(draft.channelName)").font(.system(size: 13, weight: .semibold))
                        Text(draft.channelID).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        Spacer()
                    }
                    Picker("Send as", selection: $draft.destination) {
                        Text("Thread reply").tag(SlackReplyDestination.thread)
                        Text(draft.isDM ? "Direct message" : "New channel message").tag(SlackReplyDestination.conversation)
                    }.pickerStyle(.segmented).accessibilityIdentifier("slack-send-destination")
                }
            }.padding(16).background(WorkspaceDesign.inset, in: RoundedRectangle(cornerRadius: 12))
            if !draft.anchorText.isEmpty {
                DisclosureGroup("Discussion you’re responding to") {
                    Text(draft.anchorText).font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(5).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
                }.font(.system(size: 12))
            }
            TextEditor(text: $draft.text)
                .font(.system(size: 15)).scrollContentBackground(.hidden)
                .padding(12).frame(height: 190)
                .background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WorkspaceDesign.border))
                .accessibilityIdentifier("slack-send-editor")
            HStack {
                Text("Nothing is sent until you review and confirm.")
                Spacer()
                Text("\(draft.text.count) / 4,000").monospacedDigit()
                    .foregroundStyle(draft.text.count > 4000 ? .orange : .secondary)
            }.font(.caption).foregroundStyle(.secondary)
            if sender.hasUncertainDelivery(draft) {
                Toggle("I checked Slack and this message was not delivered", isOn: $checkedUncertainDelivery)
                    .font(.caption).accessibilityIdentifier("slack-checked-delivery")
            }
        }
        .onChange(of: otherDestination) { _, _ in draft.otherChannelID = ""; checkedUncertainDelivery = false }
        .onChange(of: draft.text) { _, _ in checkedUncertainDelivery = false }
        .onChange(of: draft.otherChannelID) { _, _ in checkedUncertainDelivery = false }
    }

    private func confirmation(_ request: SlackSendRequest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(request.destinationLabel, systemImage: request.threadTS == nil ? "bubble.left" : "arrowshape.turn.up.left")
                .font(.system(size: 14, weight: .semibold))
            Text("Conversation: \(request.channelID)\(request.threadTS.map { " · Thread: \($0)" } ?? "")")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            ScrollView {
                Text(request.text).font(.system(size: 15)).lineSpacing(5).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }.frame(minHeight: 130, maxHeight: 260)
                .background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.3)))
            Text("Sent through your connected Workbench Slack account. Slack formatting, mentions, and notifications apply.")
                .font(.caption).foregroundStyle(.secondary)
            if sending { HStack { ProgressView().controlSize(.small); Text("Sending once…").font(.caption) } }
        }.accessibilityIdentifier("slack-send-review")
    }

    private func deliveryResult(_ record: SlackSendRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(record.state == .sent ? "Sent to Slack" : record.state == .failed ? "Message not sent" : "Delivery unconfirmed",
                  systemImage: record.state == .sent ? "checkmark.circle.fill" : "exclamationmark.bubble")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(record.state == .sent ? .green : .orange)
                .accessibilityIdentifier("slack-delivery-result")
            Text(record.request.destinationLabel + " · " + record.request.channelID).font(.caption).foregroundStyle(.secondary)
            Text(record.request.text).font(.system(size: 14)).lineLimit(8).textSelection(.enabled)
            if let detail = record.detail { Text(detail).font(.system(size: 13)).foregroundStyle(.secondary) }
            if let receipt = record.receipt { Text("Slack message ID: \(receipt.ts)").font(.caption).foregroundStyle(.secondary) }
            if record.request.channelID == draft.channelID, let url = draft.sourceURL {
                Link("Open conversation in Slack ↗", destination: url).font(.system(size: 13))
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var footer: some View {
        HStack {
            if result == nil {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(sending)
            }
            Spacer()
            if let record = result {
                if record.state != .sent {
                    Button("Edit draft") { result = nil; review = nil; error = nil; checkedUncertainDelivery = false }
                        .buttonStyle(WorkspaceButtonStyle())
                }
                Button("Done") { dismiss() }.buttonStyle(WorkspaceButtonStyle(prominent: true))
            } else if let request = review {
                Button("Back to edit") { sender.cancelReview(request.id); review = nil; error = nil }
                    .buttonStyle(WorkspaceButtonStyle()).disabled(sending)
                Button("Send to Slack") {
                    sending = true; error = nil
                    Task {
                        do { result = try await sender.sendApproved(request.id) }
                        catch { self.error = error.localizedDescription; review = nil }
                        sending = false
                    }
                }.buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(sending || sender.isSending)
                    .accessibilityIdentifier("slack-confirm-send")
            } else {
                Button("Review message") {
                    do {
                        guard !otherDestination || !draft.otherChannelID.isEmpty else {
                            throw SlackSendError.notSent("Enter the destination conversation ID.")
                        }
                        review = try sender.review(draft, checkedUncertainDelivery: checkedUncertainDelivery); error = nil
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(!validText || sender.isSending)
                    .accessibilityIdentifier("slack-review-message")
            }
        }
    }
}
