import AppKit
import SwiftUI

struct NotificationCenterView: View {
    @EnvironmentObject private var appState: AppState
    @State private var overview = false

    var body: some View {
        VStack(spacing: 0) {
            if overview {
                HStack {
                    Button("← Slack replies") { overview = false }.buttonStyle(WorkspaceButtonStyle())
                    Spacer()
                }.padding(.horizontal, 28).padding(.top, 12)
                NotificationOverviewView()
            } else {
                SlackReplyInboxView(onOverview: { overview = true })
                    .environmentObject(appState.slackReplyService).environmentObject(appState.slackSendService)
            }
        }.background(WorkspaceDesign.canvas)
    }
}

struct SlackReplyInboxView: View {
    var onOverview: () -> Void = {}
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var service: SlackReplyService
    @EnvironmentObject private var sender: SlackSendService
    @State private var tab = "Inbox"
    @State private var selection: String?
    @State private var search = ""
    @State private var showSettings = false
    @State private var custom = ""
    @State private var copied: String?
    @State private var day = Date()
    @State private var draft: SlackReplyDraft?

    private var topics: [SlackReplyTopic] {
        (tab == "Cleared" ? service.clearedTopics : service.activeTopics).filter {
            search.isEmpty || ($0.latest.text + $0.latest.channelName + ($0.analysis?.summary ?? "")).localizedCaseInsensitiveContains(search)
        }
    }
    private var selected: SlackReplyTopic? { topics.first { $0.id == selection } ?? topics.first }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(title: "Reply inbox", subtitle: "Slack · The right words, with the context.") {
                Button("All sources", action: onOverview).buttonStyle(WorkspaceButtonStyle())
                Button("New message") { draft = SlackReplyDraft(scope: service.snapshot.scope) }
                    .buttonStyle(WorkspaceButtonStyle(prominent: true))
                    .disabled(service.snapshot.scope.isEmpty || sender.isSending)
                    .accessibilityIdentifier("slack-new-message")
                Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Slack reply settings")
                Button { Task { await service.refresh(force: true) } } label: {
                    Label(service.isWorking ? "Working…" : "Refresh", systemImage: "arrow.clockwise")
                }.disabled(service.isWorking || !service.snapshot.settings.enabled || !service.storageReady)
                    .accessibilityIdentifier("slack-replies-refresh")
            }
            navigation
            statusBar
            if !service.storageReady {
                ContentUnavailableView("Your saved inbox needs attention", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(service.errorMessage ?? "Retry loading the local cache."))
                Button("Retry loading inbox") { service.reload() }.padding()
            } else if !service.snapshot.settings.enabled {
                introduction
            } else if tab == "Insights" {
                insights
            } else {
                HSplitView {
                    topicList.frame(minWidth: 240, idealWidth: 290, maxWidth: 350)
                    ScrollView {
                        if let topic = selected { detail(topic).padding(26) }
                        else { emptyInbox.padding(36) }
                    }.frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("slack-reply-detail")
                        .background(WorkspaceDesign.surface)
                }
            }
        }
        .background(WorkspaceDesign.canvas)
        .sheet(isPresented: $showSettings) {
            SlackReplySettingsView(settings: service.snapshot.settings).environmentObject(service).environmentObject(appState)
        }
        .sheet(item: $draft) { draft in
            SlackReplyComposer(draft: draft).environmentObject(sender)
        }
        .onAppear { selection = topics.first?.id }
        .onChange(of: topics.map(\.id)) { _, ids in
            if selection == nil || !ids.contains(selection!) { selection = ids.first }
        }
        .onChange(of: selected?.id) { _, _ in custom = ""; copied = nil }
        .onChange(of: tab) { _, _ in selection = nil; custom = ""; copied = nil }
    }

    private var navigation: some View {
        HStack(spacing: 8) {
            ForEach(["Inbox", "Cleared", "Insights"], id: \.self) { name in
                Button { tab = name } label: {
                    HStack(spacing: 6) {
                        Text(name)
                        if name == "Inbox" { Text("\(service.activeTopics.count)").monospacedDigit().foregroundStyle(.secondary) }
                    }.font(.system(size: 12, weight: tab == name ? .semibold : .regular))
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(tab == name ? WorkspaceDesign.inset : .clear, in: Capsule())
                }.buttonStyle(.plain).accessibilityLabel("Slack \(name)")
            }
            Spacer()
            if tab != "Insights" {
                TextField("Find a discussion", text: $search).textFieldStyle(.roundedBorder).frame(width: 180)
                    .accessibilityLabel("Search Slack inbox")
                if tab == "Inbox" {
                    Button("Clear visible") { service.clear(Set(topics.map(\.id))) }
                        .buttonStyle(WorkspaceButtonStyle()).disabled(topics.isEmpty).help("Clear from Tidy only. Restore from Cleared.")
                }
            }
        }.padding(.horizontal, 28).padding(.bottom, 14)
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if service.isWorking { ProgressView().controlSize(.mini) }
                else { Image(systemName: "checkmark.shield").foregroundStyle(.secondary) }
                Text(service.status).lineLimit(2)
                Spacer()
                if let next = service.nextRefresh {
                    Text("Next check \(next.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
                } else { Text("Auto-refresh off").foregroundStyle(.secondary) }
                Text("· Review before sending").foregroundStyle(.secondary)
            }.font(.system(size: 11))
            if let error = service.errorMessage { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
        }.padding(.horizontal, 28).padding(.vertical, 12).background(WorkspaceDesign.inset)
    }

    private var introduction: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "bubble.left.and.text.bubble.right").font(.system(size: 38)).foregroundStyle(Color.accentColor)
                Text("A little context.\nA better reply.").font(.system(size: 38, design: .serif))
                Text("Bring mentions and direct messages into a calm inbox. Catch up on the discussion, choose a reply, and make it sound like you.")
                    .font(.system(size: 15)).foregroundStyle(.secondary).lineSpacing(5)
                HStack(alignment: .top, spacing: 24) {
                    benefit("text.bubble", "Two ways to reply", "A concise answer and a thoughtful alternative.")
                    benefit("wand.and.stars", "Your own direction", "Ask for a warmer tone, a question, or a different approach.")
                    benefit("clock", "At your pace", "Hourly checks by default. Clear the inbox without changing Slack.")
                }
                Button("Set up reply inbox") { showSettings = true }.buttonStyle(WorkspaceButtonStyle(prominent: true))
                Text("Uses your Workbench Slack connection and selected AI provider. Choose a suggestion or write your own reply, then review and confirm before sending to Slack.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(40).frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private func benefit(_ icon: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).foregroundStyle(Color.accentColor)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var topicList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                Text(tab == "Cleared" ? "OUT OF THE WAY" : "YOUR CONVERSATIONS")
                    .font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary).padding(.vertical, 10)
                ForEach(topics) { topic in
                    Button { selection = topic.id } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Label(topic.latest.isDM ? "Direct message" : topic.latest.channelName, systemImage: topic.latest.isDM ? "person.crop.circle" : "number")
                                    .font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                Spacer(minLength: 4)
                                if topic.observedReply(userID: service.snapshot.settings.userID) != nil {
                                    Image(systemName: "checkmark.bubble").foregroundStyle(.green)
                                } else if topic.analysisIsCurrent { Circle().fill(Color.accentColor).frame(width: 6, height: 6) }
                            }
                            Text(topic.latest.text).font(.system(size: 13)).lineLimit(3).multilineTextAlignment(.leading)
                            HStack {
                                Text(topic.latest.date.formatted(date: .abbreviated, time: .shortened))
                                Spacer()
                                Text(topic.analysisIsCurrent ? "2 replies" : "Needs context")
                            }.font(.system(size: 10)).foregroundStyle(.secondary)
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(selected?.id == topic.id ? Color.accentColor.opacity(0.09) : WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected?.id == topic.id ? Color.accentColor.opacity(0.4) : WorkspaceDesign.border))
                    }.buttonStyle(.plain).accessibilityIdentifier("slack-topic-\(topic.id)")
                }
            }.padding(16)
        }.background(WorkspaceDesign.canvas)
    }

    private var emptyInbox: some View {
        ContentUnavailableView(tab == "Cleared" ? "Nothing cleared yet" : search.isEmpty ? "A little breathing room." : "No matching discussions",
                               systemImage: "tray", description: Text(search.isEmpty ? "Refresh to check for mentions. Cleared items stay out of the inbox until a new mention arrives." : "Try a different phrase or clear the search."))
    }

    private func detail(_ topic: SlackReplyTopic) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(topic.latest.isDM ? "DIRECT MESSAGE" : "#\(topic.latest.channelName.uppercased())")
                    .font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                Spacer()
                if let url = topic.latest.sourceURL { Link("Open in Slack ↗", destination: url).font(.system(size: 12)) }
                if !topic.isDismissed {
                    Button("Write reply") { draft = SlackReplyDraft(topic: topic, scope: service.snapshot.scope) }
                        .buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(sender.isSending)
                        .accessibilityIdentifier("slack-write-reply")
                }
                Button(topic.isDismissed ? "Restore" : "Clear") {
                    if topic.isDismissed { service.restore(topic.id) } else { service.clear([topic.id]) }
                }.buttonStyle(WorkspaceButtonStyle()).accessibilityIdentifier("slack-clear-topic")
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("THE MENTION").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Text(topic.latest.text).font(.system(size: 14)).lineSpacing(4).lineLimit(4).textSelection(.enabled)
                Text("\(topic.latest.user) · \(topic.latest.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(WorkspaceDesign.inset, in: RoundedRectangle(cornerRadius: 14))
            if let sent = sender.latest(for: topic.id, scope: service.snapshot.scope) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: sent.state == .sent ? "checkmark.bubble.fill" : "exclamationmark.bubble")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sent.state == .sent ? "Sent from Tidy" : sent.state == .sending ? "Sending…" : sent.state == .failed ? "Message not sent" : "Delivery unconfirmed")
                            .font(.system(size: 12, weight: .semibold))
                        Text(sent.detail ?? "\(sent.request.destinationLabel) · \(sent.request.channelID)")
                            .font(.caption)
                    }
                }.foregroundStyle(sent.state == .sent ? .green : .secondary)
            }
            if topic.analysisIsCurrent, let analysis = topic.analysis {
                VStack(alignment: .leading, spacing: 9) {
                    Label("The conversation so far", systemImage: "text.alignleft").font(.system(size: 13, weight: .semibold))
                    Text(analysis.summary).font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(4).textSelection(.enabled)
                    if !analysis.needsReply { Text("May be informational · a reply is your choice").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if topic.contextIsPartial && topic.contextFetchedAt != nil {
                Text("Partial context · review the full discussion in Slack before sending.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = topic.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
            if !topic.isDismissed {
                Divider()
                HStack {
                    Text("MAKE IT YOUR REPLY").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                    Spacer()
                    Button(topic.analysisIsCurrent ? "Regenerate" : "Generate replies") { Task { await service.generate(for: topic.id) } }
                        .buttonStyle(WorkspaceButtonStyle()).disabled(service.isWorking)
                }
                if topic.analysisIsCurrent, let analysis = topic.analysis {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), alignment: .top)], alignment: .leading, spacing: 12) {
                        ForEach(Array(analysis.options.enumerated()), id: \.offset) { index, option in
                            replyCard(option, number: "0\(index + 1)", topic: topic)
                        }
                    }
                } else {
                    Text("Read the discussion and prepare two possible replies. Your configured AI provider uses the fetched context; nothing is posted.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Label("03  A different direction", systemImage: "wand.and.stars").font(.system(size: 13, weight: .semibold))
                    TextField("e.g. Ask what’s blocking them, in Indonesian", text: $custom, axis: .vertical)
                        .textFieldStyle(.plain).lineLimit(2...4).font(.system(size: 13))
                        .accessibilityIdentifier("slack-custom-instruction")
                    HStack {
                        Text("Refines a draft. Never sends it.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Suggest a reply") { Task { await service.generate(for: topic.id, custom: custom) } }
                            .buttonStyle(WorkspaceButtonStyle()).disabled(service.isWorking || custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("slack-custom-generate")
                    }
                }.padding(18).background(Color.accentColor.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor.opacity(0.18)))
                if let option = topic.customOption { replyCard(option, number: "03", topic: topic) }
            }
            if topic.contextFetchedAt != nil {
                DisclosureGroup("Discussion context · \(topic.context.count) messages\(topic.contextIsPartial ? " · partial" : "")") {
                    VStack(alignment: .leading, spacing: 15) {
                        ForEach(topic.context) { message in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(message.user) · \(message.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                                Text(message.text).font(.system(size: 12)).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.top, 12)
                }.font(.system(size: 12))
                if topic.contextIsPartial { Text("Only part of this discussion was retrieved. Check Slack before relying on a suggestion.").font(.caption).foregroundStyle(.secondary) }
            }
        }.frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
    }

    private func replyCard(_ option: SlackReplyOption, number: String, topic: SlackReplyTopic) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(number).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Color.accentColor)
                Text(option.title).font(.system(size: 13, weight: .semibold))
                Spacer()

            }
            Text(option.text).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
            HStack {
                Button("Use reply") { draft = SlackReplyDraft(topic: topic, scope: service.snapshot.scope, text: option.text) }
                    .buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(sender.isSending)
                    .accessibilityLabel("Use \(option.title)")
                Button(copied == option.id ? "Copied" : "Copy reply") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(option.text, forType: .string)
                    service.copied(topic.id); copied = option.id
                }.buttonStyle(WorkspaceButtonStyle()).accessibilityLabel("Copy \(option.title)")
                Spacer()
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(WorkspaceDesign.canvas, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WorkspaceDesign.border))
    }

    private var insights: some View {
        let topics = service.topics(on: day)
        let observed = topics.filter { $0.observedReply(userID: service.snapshot.settings.userID) != nil }.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("See how the day unfolded.").font(.system(size: 30, design: .serif))
                        Text("Response activity from the discussions Tidy has observed.").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: .date).labelsHidden().frame(width: 140)
                }
                HStack(spacing: 12) {
                    metric("Discussions", "\(topics.count)", "Mentioned or directly messaged")
                    metric("Observed replies", service.snapshot.settings.userID.isEmpty ? "—" : "\(observed)", "Your messages found after a mention")
                    metric("Cleared locally", "\(topics.filter(\.isDismissed).count)", "Does not count as a reply")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("YOUR LAST SEVEN DAYS").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                    ForEach((0..<7).reversed(), id: \.self) { offset in
                        let date = Calendar.current.date(byAdding: .day, value: -offset, to: day) ?? day
                        let count = service.topics(on: date).count
                        HStack {
                            Text(date.formatted(.dateTime.weekday(.abbreviated))).frame(width: 38, alignment: .leading)
                            GeometryReader { geometry in
                                Capsule().fill(Color.accentColor.opacity(0.7)).frame(width: count == 0 ? 0 : max(4, geometry.size.width * Double(count) / Double(max(1, service.snapshot.topics.count))))
                            }.frame(height: 7).background(WorkspaceDesign.inset, in: Capsule())
                            Text("\(count)").monospacedDigit().frame(width: 26, alignment: .trailing)
                        }.font(.system(size: 12)).accessibilityElement(children: .combine)
                    }
                }.padding(20).background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 14))
                HStack {
                    Text("Daily discussion recap").font(.system(size: 20, design: .serif))
                    Spacer()
                    Button("Summarize day") { Task { await service.dailyRecap(for: day) } }
                        .buttonStyle(WorkspaceButtonStyle()).disabled(service.isWorking || topics.isEmpty)
                }
                if let recap = service.snapshot.recaps.first(where: { $0.day == SlackReplyService.dayKey(day) }) {
                    MarkdownDocumentView(source: recap.text).textSelection(.enabled)
                    Text("Generated \(recap.generatedAt.formatted(date: .abbreviated, time: .shortened)) from saved context; newer activity may not be included.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Get highlights, decisions, and open follow-ups from up to 12 saved discussions. No extra Slack reads are needed.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Text("This is a partial view of communication, not a responsibility score. Cleared and copied drafts are not proof of a reply. Messages outside fetched threads, offline work, and your working hours are not measured. Add your Slack member ID in settings to identify observed replies.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            }.padding(32).frame(maxWidth: 960).frame(maxWidth: .infinity)
        }
    }

    private func metric(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit()
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SlackReplySettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var service: SlackReplyService
    @Environment(\.dismiss) private var dismiss
    @State var settings: SlackReplySettings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Your Slack reply inbox").font(.system(size: 27, design: .serif))
            Text("Choose what reaches you, and when.").foregroundStyle(.secondary)
            Toggle("Enable Slack reply inbox", isOn: $settings.enabled)
            VStack(alignment: .leading, spacing: 7) {
                Text("Names and handles to watch").font(.system(size: 12, weight: .semibold))
                TextField("alex.lee, Alex Lee", text: $settings.aliases).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("slack-watch-names")
                Text("Up to five, separated by commas. Mentions are searched across accessible channels, threads, and DMs.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField("Your Slack member ID (optional, e.g. U123ABC)", text: $settings.userID).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("slack-member-id")
            Text("Use Slack profile → More → Copy member ID to identify your own replies. Changing identity starts a new local inbox.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Also include direct messages without a name mention", isOn: $settings.includeDirectMessages)
            Divider()
            HStack {
                Toggle("Auto-refresh", isOn: $settings.autoRefresh)
                Spacer()
                Picker("Check every", selection: $settings.refreshMinutes) {
                    ForEach([15, 30, 60, 120, 240], id: \.self) { value in
                        Text(value < 60 ? "\(value) minutes" : "\(value / 60) hour\(value == 60 ? "" : "s")").tag(value)
                    }
                }.frame(width: 225)
            }
            Text("Checks run while Tidy is open. Searches are incremental and paged; context reads are queued and cached. Provider cooldowns take precedence over this interval.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Open Workbench connection settings") { dismiss(); appState.openMCPSettings() }.buttonStyle(WorkspaceButtonStyle())
            Text("When monitoring is enabled, Tidy sends discussion text to the AI provider in Model settings to generate suggestions. Drafts and cleared states stay in Tidy. Sending requires reviewing the exact message and destination, then confirming Send to Slack. Refresh never sends messages.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = service.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save settings") { if service.configure(settings) { dismiss() } }
                    .buttonStyle(WorkspaceButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
            }
        }.padding(30).frame(width: 570)
    }
}
