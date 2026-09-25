import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MeetingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var meetings: MeetingService
    @AppStorage(AppDefaults.meetingSummaryProvider) private var provider = MeetingSummaryProvider.codexCLI
    @AppStorage(AppDefaults.meetingTranscriptionProvider) private var transcriptionProvider = MeetingTranscriptionProvider.localWhisper
    @AppStorage(AppDefaults.meetingCodexModel) private var codexModel = ""
    @AppStorage(AppDefaults.meetingTypeSafeModel) private var typeSafeModel = ""
    @AppStorage(AppDefaults.meetingOpenAIModel) private var openAIModel = ""
    @AppStorage(AppDefaults.codexCLIModel) private var settingsCodexModel = ""
    @AppStorage(AppDefaults.meetingWhisperCLIPath) private var whisperCommand = "whisper-cli"
    @AppStorage(AppDefaults.meetingWhisperModelPath) private var whisperModelPath = ""
    @AppStorage(AppDefaults.meetingSummaryLanguage) private var language = "Auto"
    @AppStorage(AppDefaults.meetingRecordingMode) private var mode = MeetingMode.inPerson
    @AppStorage(AppDefaults.meetingCaptureBundleID) private var captureBundleID = ""
    @AppStorage(AppDefaults.meetingCallAudioSource) private var callAudioSource = MeetingCallAudioSource.system
    @AppStorage(AppDefaults.meetingNotetakerEnabled) private var notetakerEnabled = true
    @AppStorage(AppDefaults.meetingDetectGoogleMeet) private var detectGoogleMeet = false
    @AppStorage(AppDefaults.localOnlyAI) private var localOnlyAI = false
    @State private var title = ""
    @State private var apps: [MeetingCaptureApp] = []
    @State private var appID: Int32?
    @State private var participantsInformed = false
    @State private var search = ""
    @State private var tab = "Notes"
    @State private var focusSegmentID: String?
    @State private var sourceSegmentID: String?
    @State private var deleting: MeetingRecord?
    @State private var renameTitle = ""
    @State private var renaming = false
    @State private var showingPreferences = false
    @State private var localSetupError: String?

    private var filtered: [MeetingRecord] {
        meetings.records.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.transcript.localizedCaseInsensitiveContains(search) }
    }
    private var summaryModel: Binding<String> {
        switch provider {
        case .codexCLI: $codexModel
        case .openAI: $openAIModel
        case .typeSafe: $typeSafeModel
        }
    }
    private var sidebarColor: Color { Color(NSColor.windowBackgroundColor) }
    private var transcriptionBlocked: Bool { localOnlyAI && transcriptionProvider != .localWhisper }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                history.frame(width: geometry.size.width < 950 ? 200 : 220)
                Divider()
                VStack(spacing: 0) {
                    workspaceToolbar
                    Divider()
                    if let error = meetings.errorMessage, error != meetings.selected?.error { errorBanner(error) }
                    if let recordingID = meetings.recordingID, recordingID != meetings.selectedID { activeRecordingBanner(recordingID) }
                    if let processingID = meetings.processingID { processingBanner(processingID) }
                    if let record = meetings.selected {
                        if meetings.recordingID == record.id || (meetings.isStarting && record.status == .recording) {
                            recording(record)
                        } else {
                            meeting(record, sideBySide: geometry.size.width >= 1050)
                        }
                    } else { newMeeting }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .onAppear { refreshApps() }
        .onChange(of: meetings.selectedID) { _, _ in
            tab = "Notes"; focusSegmentID = nil; sourceSegmentID = nil; meetings.stopPlayback()
            if meetings.selectedID == nil { participantsInformed = false; title = "" }
        }
        .onChange(of: appID) { _, value in
            if let bundleID = apps.first(where: { $0.id == value })?.bundleID { captureBundleID = bundleID }
        }
        .onChange(of: meetings.processingID) { old, new in
            if new == nil, old == meetings.selectedID, meetings.selected?.status == .transcribed { tab = "Transcript" }
        }
        .alert("Delete meeting and recording?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) { if let deleting { meetings.delete(deleting.id) }; deleting = nil }
        } message: { Text("This removes the local audio, transcript and notes. Tasks already saved to Today are kept.") }
        .alert("Rename meeting", isPresented: $renaming) {
            TextField("Meeting title", text: $renameTitle)
            Button("Cancel", role: .cancel) { }
            Button("Save") { if let record = meetings.selected { meetings.rename(record.id, title: renameTitle) } }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Meetings", systemImage: "waveform").font(.headline).padding(.horizontal, 8)
            Button {
                meetings.selectedID = nil; title = ""; participantsInformed = false; meetings.errorMessage = nil
            } label: { Label("New recording", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading) }
                .buttonStyle(MeetingButtonStyle()).disabled(meetings.isBusy).accessibilityIdentifier("meetings.new")
            TextField("Search meetings", text: $search).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search meetings and transcripts")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(filtered) { record in
                        Button { meetings.selectedID = record.id } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(record.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                Text("\(record.createdAt.formatted(.dateTime.month(.abbreviated).day())) · \(record.displayStatus)")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
                                .background(meetings.selectedID == record.id ? Color.primary.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("meetings.history.\(record.id)")
                    }
                    if filtered.isEmpty { Text(search.isEmpty ? "Your meetings will appear here." : "No matching meetings.").font(.caption).foregroundStyle(.secondary).padding(8) }
                }
            }
            Label("Saved on this Mac", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
        }.padding(14).background(sidebarColor)
    }

    private var workspaceToolbar: some View {
        HStack(spacing: 12) {
            Text(meetings.selected == nil ? "New meeting" : "Meetings").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button { showingPreferences.toggle() } label: { Label("Preferences", systemImage: "slider.horizontal.3") }
                .buttonStyle(.plain).accessibilityIdentifier("meetings.preferences")
                .popover(isPresented: $showingPreferences, arrowEdge: .bottom) { preferences }
            if let record = meetings.selected {
                Menu {
                    Button("Rename…") { renameTitle = record.title; renaming = true }.disabled(meetings.isBusy)
                    Button("Copy notes and transcript") { copy(record) }
                    Button("Export Markdown…") { export(record) }
                    Button("Show audio files") { NSWorkspace.shared.open(meetings.store.folder(record.id)) }
                    if record.summary != nil {
                        Button("Regenerate meeting notes…") { tab = "Notes"; showingPreferences = true }
                    }
                    Divider()
                    Button("Delete meeting…", role: .destructive) { deleting = record }.disabled(meetings.isBusy)
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).frame(width: 26).accessibilityLabel("Meeting actions")
            }
        }.padding(.horizontal, 24).padding(.vertical, 18)
    }

    private var newMeeting: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Make room for the conversation.").font(.system(size: 28, weight: .medium))
                    Text("Let Tidy take the notes while you join the conversation.").foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    sourceButton(.call, icon: "laptopcomputer")
                    sourceButton(.inPerson, icon: "mic")
                }
                if mode == .call {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Capture", selection: $callAudioSource) {
                            ForEach(MeetingCallAudioSource.allCases) { Text($0.title).tag($0) }
                        }.accessibilityIdentifier("meetings.callAudioSource")
                        if callAudioSource == .application {
                            HStack {
                                Picker("Audio from", selection: $appID) {
                                    Text("Select an app").tag(Optional<Int32>.none)
                                    ForEach(apps) { Text($0.name).tag(Optional($0.id)) }
                                }.accessibilityIdentifier("meetings.captureApp")
                                Button { refreshApps() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh running apps")
                            }
                        }
                        Text(callAudioSource == .system
                             ? "Recommended for Google Meet: records other participants through system audio, plus your microphone. Includes sounds from other apps and tabs; mute those you don’t want recorded. Use headphones to avoid echo."
                             : "Records the selected app plus your microphone. If browser participants are missing, choose System audio. Other tabs in the selected app may be included.")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("Allow Microphone and Screen & System Audio Recording access when macOS asks. No screen video is saved.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Label("Microphone only. For Google Meet participants, choose Online call.", systemImage: "mic").foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Meeting title").font(.callout)
                    TextField("Untitled meeting (optional)", text: $title).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("meetings.title")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Take notes for me", isOn: $notetakerEnabled)
                        .toggleStyle(.checkbox).accessibilityIdentifier("meetings.notetaker")
                    Text(notetakerEnabled
                         ? "A transcript appears as audio is processed. Finish to automatically create a summary, decisions, action items, and open questions."
                         : "Save audio now. Create the transcript and notes whenever you’re ready.")
                        .font(.callout).foregroundStyle(.secondary)
                    if notetakerEnabled {
                        Text(transcriptionProvider == .localWhisper
                             ? "Transcription runs on this Mac. On finish, transcript text is sent to \(provider.title), using your provider allowance."
                             : "Audio is sent to \(transcriptionProvider.title) during the meeting. On finish, transcript text is sent to \(provider.title). Uses your provider allowance.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Notetaker preferences") { showingPreferences = true }.buttonStyle(.link)
                    }
                }
                Toggle("I’ve let everyone know I’m recording.", isOn: $participantsInformed)
                    .toggleStyle(.checkbox).accessibilityIdentifier("meetings.consent")
                Button {
                    Task { await meetings.start(title: title, mode: mode, app: mode == .call ? apps.first { $0.id == appID } : nil,
                                               provider: provider, language: language, participantsInformed: participantsInformed,
                                               transcriptionProvider: transcriptionProvider, model: summaryModel.wrappedValue,
                                               callAudioSource: callAudioSource, notetakerEnabled: notetakerEnabled) }
                } label: { Label(notetakerEnabled ? "Start notetaker" : "Start recording", systemImage: notetakerEnabled ? "sparkles" : "mic") }
                    .buttonStyle(MeetingButtonStyle(primary: true)).disabled(!participantsInformed || meetings.isBusy || (mode == .call && callAudioSource == .application && appID == nil))
                    .accessibilityIdentifier("meetings.start")
                Label("Saved locally · Stops automatically at 2 hours", systemImage: "internaldrive")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: 530, alignment: .leading).padding(36).frame(maxWidth: .infinity)
        }
    }

    private func sourceButton(_ value: MeetingMode, icon: String) -> some View {
        Button { mode = value } label: {
            Label(value.title, systemImage: icon).frame(maxWidth: .infinity).padding(.vertical, 5)
        }.buttonStyle(MeetingButtonStyle(selected: mode == value))
            .accessibilityAddTraits(mode == value ? [.isSelected] : [])
    }

    private func recording(_ record: MeetingRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label(meetings.isStarting ? "Preparing recording…" : meetings.isStopping ? "Saving audio…" : "Recording · Audio is saving locally", systemImage: "record.circle.fill")
                    .foregroundStyle(.red).font(.callout)
                Text(record.title).font(.system(size: 28, weight: .medium))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(MeetingRecord.timestamp(meetings.elapsed)).font(.system(size: 40, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("/ 2:00:00").font(.title3).foregroundStyle(.secondary)
                }
                Text(record.notetakerEnabled == true ? "Tidy is taking notes. Your transcript updates as audio is processed." : "No AI requests while you record.")
                    .foregroundStyle(.secondary)
                ForEach(record.mode == .call ? ["Call", "Microphone"] : ["Room"], id: \.self) { source in
                    HStack(spacing: 16) {
                        Label(source == "Call" ? "Call · \(record.appName ?? "Participants")" : "Your microphone", systemImage: source == "Call" ? "waveform" : "mic")
                        Spacer()
                        ProgressView(value: min(1, Double(meetings.levels[source] ?? 0) * 5))
                            .tint(.primary).frame(width: 130).accessibilityLabel("\(source) audio level")
                    }
                }
                Text("Check that both audio meters move when people speak.")
                    .font(.caption).foregroundStyle(.secondary).opacity(record.mode == .call ? 1 : 0)
                if let warning = meetings.captureWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange).accessibilityIdentifier("meetings.captureWarning")
                }
                personalNotes(record)
                if record.notetakerEnabled == true { liveTranscript(record) }
                Button { Task { await meetings.stop(andSummarize: record.notetakerEnabled == true) } } label: {
                    Label(record.notetakerEnabled == true ? "Finish & create meeting notes" : "Finish recording", systemImage: "stop.fill")
                }
                    .buttonStyle(MeetingButtonStyle(primary: true)).disabled(meetings.isStarting || meetings.isStopping)
                    .accessibilityIdentifier("meetings.finish")
                if record.notetakerEnabled == true {
                    Button("Stop & save without summary") { Task { await meetings.stop(andSummarize: false) } }
                        .buttonStyle(.link).disabled(meetings.isStarting || meetings.isStopping)
                }
                Text("Closing this window keeps recording in the menu bar. Audio stops and saves at the 2-hour limit.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: 600, alignment: .leading).padding(32).frame(maxWidth: .infinity)
        }
    }

    private func liveTranscript(_ record: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Live transcript", systemImage: "text.bubble").font(.headline)
            Text("Updates in roughly 20-second audio parts. Processing can take longer; the last part finishes after you stop.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = meetings.liveTranscriptError {
                Text(error).font(.callout).foregroundStyle(.orange)
            } else if !meetings.liveTranscriptProgress.isEmpty {
                HStack { ProgressView().controlSize(.small); Text(meetings.liveTranscriptProgress).font(.caption) }
            }
            if record.segments.isEmpty {
                Text("Waiting for the first spoken audio…").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(record.orderedSegments) { segment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(MeetingRecord.timestamp(segment.start)) · \(segment.speaker)").font(.caption).foregroundStyle(.secondary)
                                Text(segment.text).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.frame(height: 180)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("meetings.liveTranscript")
    }

    private func meeting(_ record: MeetingRecord, sideBySide: Bool) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text(record.title).font(.system(size: 26, weight: .medium)).textSelection(.enabled)
                Text("\(record.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(MeetingRecord.timestamp(record.duration)) · \(record.appName ?? record.mode.title)")
                    .font(.caption).foregroundStyle(.secondary)
                if record.recordingLimitReached == true {
                    Label("Stopped at 2 hours. Your recording is saved.", systemImage: "clock.badge.checkmark")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let error = record.error {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.chunks.isEmpty ? "Recording needs attention" : "Your saved audio is available").font(.callout.weight(.medium))
                        Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                }
                if !record.chunks.isEmpty { recordingPlayback(record) }
                HStack(spacing: 24) {
                    contentTab("Notes")
                    contentTab("Transcript", count: record.segments.count)
                    Spacer()
                }
            }.padding(.horizontal, 28).padding(.top, 26)
            Divider()
            if sideBySide {
                HStack(alignment: .top, spacing: 0) {
                    meetingContent(record)
                    if let segment = sourceSegment(record) {
                        Divider()
                        sourcePanel(segment, record: record).frame(width: 260)
                    }
                }
            } else {
                meetingContent(record)
                if let segment = sourceSegment(record) {
                    Divider()
                    sourcePanel(segment, record: record).frame(maxHeight: 240)
                }
            }
        }
    }

    private func contentTab(_ name: String, count: Int? = nil) -> some View {
        Button { tab = name; sourceSegmentID = nil } label: {
            VStack(spacing: 12) {
                Text(name + (count.map { " (\($0))" } ?? "")).foregroundStyle(tab == name ? .primary : .secondary)
                Rectangle().fill(tab == name ? Color.primary : .clear).frame(height: 2)
            }.fixedSize(horizontal: true, vertical: false)
        }.buttonStyle(.plain).accessibilityIdentifier("meetings.tab.\(name)")
            .accessibilityAddTraits(tab == name ? [.isSelected] : [])
    }

    @ViewBuilder private func meetingContent(_ record: MeetingRecord) -> some View {
        if tab == "Transcript", !record.segments.isEmpty { transcript(record) }
        else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if tab == "Notes", let summary = record.summary { summaryContent(summary, record: record) }
                    else { nextStep(record) }
                    if !(record.personalNotes ?? "").isEmpty { personalNotes(record) }
                }.frame(maxWidth: 700, alignment: .leading).padding(28).frame(maxWidth: .infinity, alignment: .top)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func nextStep(_ record: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if meetings.processingID == record.id {
                Text(meetings.processingStage == .transcription ? "Creating your transcript." : "Finding the decisions and next steps.")
                    .font(.title2.weight(.medium))
                Text("Your recording and completed transcript sections remain saved.").foregroundStyle(.secondary)
            } else if record.chunks.isEmpty && record.segments.isEmpty {
                Text("No audio was saved.").font(.title2.weight(.medium))
                Text("Start a new recording and check your microphone and call audio meters.").foregroundStyle(.secondary)
            } else if record.hasPendingTranscription {
                Text(record.segments.isEmpty ? "Your conversation is saved." : "Pick up where you left off.").font(.title2.weight(.medium))
                Text(transcriptionProvider == .localWhisper ? "Create a transcript on this Mac. No Codex tokens needed." : "Create a transcript with \(transcriptionProvider.title). Audio will be uploaded using your API quota.")
                    .foregroundStyle(.secondary)
                Button {
                    meetings.transcribeRecording(record.id, provider: transcriptionProvider)
                } label: { Label(record.chunks.contains(where: \.transcribed) ? "Resume transcription" : "Create transcript", systemImage: "waveform") }
                    .buttonStyle(MeetingButtonStyle(primary: true)).disabled(meetings.isBusy || transcriptionBlocked)
                    .accessibilityIdentifier("meetings.transcribe")
                if transcriptionBlocked { Text("Local-only AI is on. Choose Local Whisper in Preferences to transcribe here.").font(.callout).foregroundStyle(.secondary) }
                Button("Change transcription preferences") { showingPreferences = true }.buttonStyle(.link)
            } else if record.segments.isEmpty {
                Text("No speech was found.").font(.title2.weight(.medium))
                Text("Your audio is saved. Check the recording before starting another meeting.").foregroundStyle(.secondary)
                if let chunk = record.chunks.first {
                    Button("Play saved audio") { playChunk(chunk, record: record) }.buttonStyle(MeetingButtonStyle())
                }
            } else {
                Label("Transcript ready", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                Text("Ready for the useful part.").font(.title2.weight(.medium))
                Text("Pull out decisions, action items, and open questions with \(provider.title). Only transcript text is sent.").foregroundStyle(.secondary)
                createNotesButton(record)
                Text(provider == .codexCLI ? "Uses your Codex allowance. You can create notes later." : provider == .typeSafe ? "Uses your TypeSafe / Jev API quota. You can create notes later." : "Uses your OpenAI API quota. You can create notes later.")
                    .font(.caption).foregroundStyle(.secondary)
                if localOnlyAI { Text("Local-only AI is on. Your transcript remains available; cloud notes are disabled.").font(.callout).foregroundStyle(.secondary) }
            }
            if !record.chunks.isEmpty {
                HStack {
                    Label("Audio saved on this Mac", systemImage: "internaldrive").foregroundStyle(.secondary)
                    Spacer()
                    Button("Show files") { NSWorkspace.shared.open(meetings.store.folder(record.id)) }.buttonStyle(.link)
                }.font(.caption).padding(.top, 10)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 18)
    }

    private func recordingPlayback(_ record: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if meetings.playingRecordingID == record.id { meetings.stopPlayback() }
                else { meetings.playRecording(record) }
            } label: {
                Label(meetings.playingRecordingID == record.id
                      ? (meetings.isPreparingPlayback ? "Cancel loading audio" : "Stop recording playback")
                      : "Play full recording", systemImage: meetings.playingRecordingID == record.id ? "stop.fill" : "play.fill")
            }.buttonStyle(MeetingButtonStyle()).disabled(meetings.recordingID != nil || meetings.isStarting)
                .accessibilityIdentifier("meetings.playRecording")
            Text("Full playback includes call audio and your microphone when captured. Transcript play buttons play only their source track.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func createNotesButton(_ record: MeetingRecord) -> some View {
        Button {
            showingPreferences = false
            tab = "Notes"
            meetings.createNotes(record.id, provider: provider, language: language, model: summaryModel.wrappedValue)
        } label: { Label(provider == .typeSafe ? "Select transcript excerpts" : record.summary == nil ? "Create meeting notes" : "Regenerate meeting notes", systemImage: "sparkles") }
            .buttonStyle(MeetingButtonStyle(primary: true)).disabled(meetings.isBusy || localOnlyAI || !record.canCreateNotes)
            .accessibilityIdentifier("meetings.createNotes")
    }

    private func summaryContent(_ summary: MeetingSummary, record: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            if record.summaryFormat == .transcriptExcerpts {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Create a written meeting summary").font(.headline)
                    Text("Jev selected transcript excerpts. Codex can turn the full transcript into a concise summary, decisions, action items, and open questions.")
                        .foregroundStyle(.secondary)
                    Button {
                        provider = .codexCLI
                        meetings.createNotes(record.id, provider: .codexCLI, language: language, model: codexModel)
                    } label: { Label("Create summary with Codex", systemImage: "sparkles") }
                        .buttonStyle(MeetingButtonStyle(primary: true))
                        .disabled(meetings.isBusy || localOnlyAI || !record.canCreateNotes)
                        .accessibilityIdentifier("meetings.createWrittenSummary")
                    Text("Sends transcript text using your Codex allowance. Audio stays on this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            noteSection(record.summaryFormat == .transcriptExcerpts ? "Transcript highlights" : "Summary") {
                Text(summary.overview).font(.body).lineSpacing(5).textSelection(.enabled)
            }
            noteSection("Decisions") {
                if summary.decisions.isEmpty { Text("No explicit decisions recorded.").foregroundStyle(.secondary) }
                ForEach(Array(summary.decisions.enumerated()), id: \.offset) { _, point in
                    VStack(alignment: .leading, spacing: 8) { Text(point.text).textSelection(.enabled); citations(point.segmentIDs, record: record) }
                }
            }
            noteSection("Action items") {
                if summary.actions.isEmpty { Text("No explicit follow-ups recorded.").foregroundStyle(.secondary) }
                ForEach(Array(summary.actions.enumerated()), id: \.offset) { index, action in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(action.title).textSelection(.enabled)
                            if action.owner != nil || action.dueText != nil {
                                Text([action.owner, action.dueText].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                            citations(action.segmentIDs, record: record)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button { meetings.saveAction(action, from: record.id, to: appState.productivityService) } label: {
                            Label(record.savedActionIDs.contains(action.id) ? "Added" : "Today", systemImage: record.savedActionIDs.contains(action.id) ? "checkmark" : "plus")
                        }.buttonStyle(MeetingButtonStyle()).disabled(meetings.isBusy || record.savedActionIDs.contains(action.id))
                            .accessibilityLabel(record.savedActionIDs.contains(action.id) ? "Added to Today" : "Add \(action.title) to Today")
                    }
                    if index < summary.actions.count - 1 { Divider() }
                }
            }
            noteSection("Open questions") {
                if summary.questions.isEmpty { Text("No open questions recorded.").foregroundStyle(.secondary) }
                ForEach(Array(summary.questions.enumerated()), id: \.offset) { _, point in
                    VStack(alignment: .leading, spacing: 8) { Text(point.text).textSelection(.enabled); citations(point.segmentIDs, record: record) }
                }
            }
            Divider()
            HStack {
                Label("Check the source before acting", systemImage: "text.quote").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { copy(record) } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(.plain).help("Copy notes and transcript")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func noteSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) { Text(title).font(.headline); content() }
    }

    private func citations(_ ids: [String], record: MeetingRecord) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(ids.prefix(4).enumerated()), id: \.offset) { _, id in
                if let segment = record.segments.first(where: { $0.id == id }) {
                    Button { sourceSegmentID = id } label: { Text(MeetingRecord.timestamp(segment.start)).font(.caption.monospacedDigit()).padding(.horizontal, 7).padding(.vertical, 4) }
                        .buttonStyle(.plain).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
                        .accessibilityLabel("View source at \(MeetingRecord.timestamp(segment.start))")
                        .accessibilityIdentifier("meetings.citation.\(id)")
                }
            }
        }
    }

    private func sourceSegment(_ record: MeetingRecord) -> MeetingSegment? { record.segments.first { $0.id == sourceSegmentID } }

    private func sourcePanel(_ segment: MeetingSegment, record: MeetingRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Source transcript").font(.headline)
                    Spacer()
                    Button { sourceSegmentID = nil; meetings.stopPlayback() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Close source")
                }
                Text("\(MeetingRecord.timestamp(segment.start)) · \(segment.speaker)").font(.caption).foregroundStyle(.secondary)
                Text(segment.text).lineSpacing(4).textSelection(.enabled)
                Button { togglePlayback(segment, record: record) } label: {
                    Label(meetings.playingSegmentID == segment.id ? "Stop playback" : "Play source audio", systemImage: meetings.playingSegmentID == segment.id ? "stop.fill" : "play.fill")
                }.buttonStyle(MeetingButtonStyle()).disabled(meetings.recordingID != nil)
                Button("Open in transcript") { focusSegmentID = segment.id; tab = "Transcript"; sourceSegmentID = nil }
                    .buttonStyle(.link).accessibilityIdentifier("meetings.openTranscript")
                Text("Original words. Speaker labels don’t establish identity across audio parts.").font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: .infinity).background(sidebarColor).accessibilityIdentifier("meetings.sourcePanel")
    }

    private func transcript(_ record: MeetingRecord) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("Original language · \(record.transcriptionProvider == .localWhisper ? "Transcribed on this Mac" : record.transcriptionProvider?.title ?? "Saved transcript")")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    if record.summary == nil && record.canCreateNotes {
                        createNotesButton(record)
                        Text(localOnlyAI ? "Cloud notes are disabled while local-only AI is on." : "Only transcript text is sent to \(provider.title). Uses your account allowance.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if record.hasPendingTranscription { nextStep(record) }
                    ForEach(record.orderedSegments) { segment in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                Button { togglePlayback(segment, record: record) } label: {
                                    Label(MeetingRecord.timestamp(segment.start), systemImage: meetings.playingSegmentID == segment.id ? "stop.fill" : "play.fill")
                                }.buttonStyle(.plain).font(.caption.monospacedDigit()).disabled(meetings.recordingID != nil)
                                Text(segment.speaker).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(segment.text).lineSpacing(4).textSelection(.enabled)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(focusSegmentID == segment.id ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .id(segment.id)
                    }
                }.frame(maxWidth: 700, alignment: .leading).padding(28).frame(maxWidth: .infinity)
            }
            .onAppear { if let focusSegmentID { proxy.scrollTo(focusSegmentID, anchor: .top) } }
            .onChange(of: focusSegmentID) { _, value in if let value { proxy.scrollTo(value, anchor: .top) } }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func personalNotes(_ record: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your notes").font(.headline)
                Spacer()
                Text("Saved locally").font(.caption).foregroundStyle(.secondary)
            }
            TextEditor(text: Binding(get: { meetings.records.first { $0.id == record.id }?.personalNotes ?? "" },
                                     set: { meetings.updatePersonalNotes(record.id, text: $0) }))
                .font(.body).scrollContentBackground(.hidden).padding(8).frame(minHeight: 100, maxHeight: 160)
                .background(sidebarColor, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.09)))
                .disabled(meetings.processingID == record.id || meetings.isStarting || meetings.isStopping)
                .accessibilityLabel("Your meeting notes").accessibilityIdentifier("meetings.personalNotes")
        }
    }

    private var preferences: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("Meeting preferences").font(.headline); Spacer(); Button("Done") { showingPreferences = false } }
                Toggle("Suggest the notetaker when Google Meet is open", isOn: $detectGoogleMeet)
                    .toggleStyle(.checkbox).accessibilityIdentifier("meetings.detectGoogleMeet")
                Text("Checks the active browser window’s address or title using Accessibility. Suggestions never start recording automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                if detectGoogleMeet && !Permissions.isAccessibilityTrusted {
                    Button("Enable Accessibility for Meet detection") { Permissions.openAccessibilitySettings() }.buttonStyle(.link)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Transcription").font(.callout.weight(.medium))
                    Picker("Transcription", selection: $transcriptionProvider) {
                        ForEach(MeetingTranscriptionProvider.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().accessibilityIdentifier("meetings.transcriptionProvider")
                    if transcriptionProvider == .localWhisper {
                        Text("Audio stays on this Mac. No Codex tokens.").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text(whisperModelPath.isEmpty ? MeetingLocalTranscriber.defaultModelURL.lastPathComponent : URL(fileURLWithPath: whisperModelPath).lastPathComponent)
                                .font(.caption).lineLimit(2).truncationMode(.middle)
                            Spacer()
                            Button("Choose…") { chooseLocalModel() }.accessibilityIdentifier("meetings.localModel")
                        }
                        if let localSetupError { Text(localSetupError).font(.caption).foregroundStyle(.orange) }
                        else { Label("Local transcription ready", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary) }
                    } else {
                        Text("Audio is uploaded to the selected provider using your API quota. Automatic uses OpenAI, then Gemini when no OpenAI key is saved.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                Picker("Meeting notes", selection: $provider) { ForEach(MeetingSummaryProvider.allCases) { Text($0.title).tag($0) } }
                if provider == .typeSafe {
                    Text("Jev selects original transcript passages. Choose Codex CLI or OpenAI API for a written summary. Jev does not rewrite or translate excerpts. Transcripts are sent to TypeSafe; add your API key in AI settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("Notes language", selection: $language) {
                    Text("Match conversation").tag("Auto")
                    Text("English").tag("English")
                    Text("Bahasa Indonesia").tag("Bahasa Indonesia")
                }.disabled(provider == .typeSafe)
                Text(provider == .typeSafe ? "Jev keeps the original language, including mixed Indonesian and English. Review the selected passages against the full transcript." : "Transcription preserves the original language, including mixed Indonesian and English. This language setting applies to the notes.")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Advanced model settings") {
                    VStack(alignment: .leading, spacing: 12) {
                        if provider == .typeSafe {
                            Picker("Jev model", selection: $typeSafeModel) {
                                Text("Latest stable").tag("")
                                Text("jev-latest").tag("jev-latest")
                                Text("jev-preview").tag("jev-preview")
                                Text("jev-1.13.0").tag("jev-1.13.0")
                                if !["", "jev-latest", "jev-preview", "jev-1.13.0"].contains(typeSafeModel) {
                                    Text(typeSafeModel).tag(typeSafeModel)
                                }
                            }
                        }
                        TextField(provider == .codexCLI ? "Use Settings model" : provider.resolvedModel(""), text: summaryModel)
                            .textFieldStyle(.roundedBorder).accessibilityLabel("Summary model").accessibilityIdentifier("meetings.summaryModel")
                        if provider == .codexCLI {
                            Text("Codex default: \(settingsCodexModel.isEmpty ? "Account default" : settingsCodexModel). Uses your existing Codex login.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Use default model") { summaryModel.wrappedValue = "" }.disabled(summaryModel.wrappedValue.isEmpty)
                        if transcriptionProvider == .localWhisper {
                            TextField("Whisper command", text: $whisperCommand).textFieldStyle(.roundedBorder)
                            TextField("Whisper model path", text: $whisperModelPath).textFieldStyle(.roundedBorder)
                            Text("Requires whisper.cpp, ffmpeg, and a multilingual GGML .bin model. English-only .en models won’t handle Indonesian.")
                                .font(.caption).foregroundStyle(.secondary)
                            Link("Download Whisper models", destination: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/tree/main")!)
                        }
                    }.padding(.top, 12)
                }
                Button("Open AI settings") {
                    showingPreferences = false
                    UserDefaults.standard.set("Model", forKey: AppDefaults.settingsTab)
                    appState.selectedDashboardSection = .settings
                }
                if let record = meetings.selected, record.summary != nil {
                    Divider()
                    Text("Regenerating sends the transcript again and uses your provider allowance.").font(.caption).foregroundStyle(.secondary)
                    createNotesButton(record)
                }
                Label("Recordings stop and save at 2 hours", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
            }.padding(24).disabled(meetings.isBusy)
        }.frame(width: 390, height: 570)
            .onAppear { checkLocalSetup() }
            .onChange(of: whisperModelPath) { _, _ in checkLocalSetup() }
            .onChange(of: whisperCommand) { _, _ in checkLocalSetup() }
    }

    private func processingBanner(_ id: UUID) -> some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 3) {
                Text(meetings.progress.isEmpty ? "Preparing…" : meetings.progress).font(.callout)
                if meetings.processingStage == .transcription {
                    Text(meetings.records.first(where: { $0.id == id })?.transcriptionProvider == .localWhisper ? "On this Mac · No Codex tokens" : "Using your transcription provider’s API quota")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if meetings.selectedID != id { Button("View") { meetings.selectedID = id } }
            Button("Cancel") { meetings.cancelProcessing() }.buttonStyle(.plain)
        }.padding(16).background(sidebarColor)
    }

    private func activeRecordingBanner(_ id: UUID) -> some View {
        HStack {
            Label("Recording · \(MeetingRecord.timestamp(meetings.elapsed)) / 2:00:00", systemImage: "record.circle.fill").foregroundStyle(.red)
            Spacer()
            Button("View recording") { meetings.selectedID = id }
        }.font(.callout).padding(14).background(sidebarColor)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            Text(error).font(.callout).textSelection(.enabled)
            Spacer()
            Button { meetings.errorMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss error")
        }.padding(16).background(Color.orange.opacity(0.06))
    }

    private func refreshApps() {
        apps = MeetingCaptureApp.running
        if !apps.contains(where: { $0.id == appID }) { appID = apps.first { $0.bundleID == captureBundleID }?.id }
    }

    private func checkLocalSetup() {
        do { try MeetingLocalTranscriber.validateSetup(); localSetupError = nil }
        catch { localSetupError = error.localizedDescription }
    }

    private func chooseLocalModel() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Whisper model"
        panel.allowedContentTypes = [UTType(filenameExtension: "bin") ?? .data]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { whisperModelPath = url.path }
    }

    private func togglePlayback(_ segment: MeetingSegment, record: MeetingRecord) {
        if meetings.playingSegmentID == segment.id { meetings.stopPlayback() }
        else { meetings.play(segment, in: record) }
    }

    private func playChunk(_ chunk: MeetingAudioChunk, record: MeetingRecord) {
        togglePlayback(MeetingSegment(id: chunk.id.uuidString, chunkID: chunk.id, start: chunk.start, end: chunk.start + chunk.duration,
                                      speaker: chunk.source, text: ""), record: record)
    }

    private func copy(_ record: MeetingRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.markdown, forType: .string)
    }

    private func export(_ record: MeetingRecord) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Meeting-\(record.createdAt.formatted(.iso8601.year().month().day())).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try record.markdown.write(to: url, atomically: true, encoding: .utf8) }
        catch { meetings.errorMessage = error.localizedDescription }
    }
}

private struct MeetingButtonStyle: ButtonStyle {
    var primary = false
    var selected = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 10)
            .foregroundStyle(primary ? Color(NSColor.textBackgroundColor) : Color.primary)
            .background(primary ? Color.primary : Color.primary.opacity(selected ? 0.075 : 0.025), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(primary ? .clear : Color.primary.opacity(selected ? 0.25 : 0.12)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
