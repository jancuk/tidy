import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var correctionLogStore: CorrectionLogStore
    @AppStorage(AppDefaults.grammarProvider)     private var grammarProvider    = GrammarProviderID.gemini.rawValue
    @AppStorage(AppDefaults.grammarHotkey)       private var grammarHotkey      = Hotkey.grammarDefault.displayValue
    @AppStorage(AppDefaults.clipboardHotkey)     private var clipboardHotkey    = Hotkey.clipboardDefault.displayValue
    @AppStorage(AppDefaults.askAIHotkey)         private var askAIHotkey        = Hotkey.askAIDefault.displayValue
    @AppStorage(AppDefaults.clipboardMaxEntries) private var maxEntries         = 200
    @AppStorage(AppDefaults.clipboardMaxAgeDays) private var maxAgeDays         = 7
    @AppStorage(AppDefaults.openCodeModel)       private var openCodeModel      = "deepseek-v4-flash-free"
    @AppStorage(AppDefaults.ollamaBaseURL)       private var ollamaBaseURL      = "http://localhost:11434"
    @AppStorage(AppDefaults.ollamaModel)         private var ollamaModel        = "gnokit/improve-grammar"
    @AppStorage(AppDefaults.codexCLIPath)        private var codexCLIPath       = "codex"
    @AppStorage(AppDefaults.codexCLIModel)       private var codexCLIModel      = ""
    @AppStorage(AppDefaults.claudeCLIPath)       private var claudeCLIPath      = "claude"
    @AppStorage(AppDefaults.appearanceMode)      private var appearanceMode     = "system"

    @State private var launchAtLogin   = false
    @State private var keyValues: [String: String] = [:]
    @State private var statusMessage   = ""
    @State private var selectedTab     = SettingsTab.general
    @State private var claudeAuthCode  = ""
    @StateObject private var codexLogin  = CodexLoginController()
    @StateObject private var claudeLogin = ClaudeLoginController()

    var body: some View {
        VStack(spacing: 0) {
            pageHeader
            tabBar
            Divider().opacity(0.5)
            contentArea
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            launchAtLogin = appState.launchAtLoginEnabled
            loadKeychainValues()
            codexLogin.refreshStatus(command: codexCLIPath)
            claudeLogin.refreshStatus(command: claudeCLIPath)
        }
    }

    // MARK: - Header

    private var pageHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(NSColor.labelColor))
                Text("Configure providers, hotkeys, and preferences")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    // MARK: - Tab bar

    enum SettingsTab: String, CaseIterable {
        case general   = "General"
        case model     = "Model"
        case clipboard = "Clipboard"
        case hotkeys   = "Hotkeys"

        var systemImage: String {
            switch self {
            case .general:   "gear"
            case .model:     "cpu"
            case .clipboard: "doc.on.clipboard"
            case .hotkeys:   "keyboard"
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                    }
                    .foregroundStyle(
                        selectedTab == tab
                            ? Color.white
                            : Color(NSColor.secondaryLabelColor)
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        selectedTab == tab ? Color.accentColor : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch selectedTab {
                case .general:   generalContent
                case .model:     modelContent
                case .clipboard: clipboardContent
                case .hotkeys:   hotkeysContent
                }
            }
            .padding(20)
        }
    }

    // MARK: - General tab

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsSection(title: "App") {
                settingsCard {
                    settingsToggleRow(
                        label: "Launch at login",
                        systemImage: "power",
                        isOn: $launchAtLogin,
                        onChange: { value in
                            do { try appState.setLaunchAtLogin(value) }
                            catch {
                                statusMessage = error.localizedDescription
                                launchAtLogin = appState.launchAtLoginEnabled
                            }
                        }
                    )
                }
            }

            settingsSection(title: "Appearance") {
                settingsCard {
                    HStack {
                        Label("Color scheme", systemImage: "circle.lefthalf.filled")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(NSColor.labelColor))
                        Spacer()
                        Picker("", selection: $appearanceMode) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            settingsSection(title: "Permissions") {
                settingsCard {
                    HStack {
                        Label(
                            Permissions.isAccessibilityTrusted ? "Accessibility allowed" : "Accessibility needed",
                            systemImage: Permissions.isAccessibilityTrusted
                                ? "checkmark.shield.fill"
                                : "exclamationmark.shield.fill"
                        )
                        .font(.system(size: 13))
                        .foregroundStyle(Permissions.isAccessibilityTrusted ? Color.green : Color.orange)
                        Spacer()
                        if !Permissions.isAccessibilityTrusted {
                            Button("Open Settings") { Permissions.openAccessibilitySettings() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }
        }
    }

    // MARK: - Model tab

    private var modelContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsSection(title: "Provider") {
                settingsCard {
                    HStack {
                        Label("AI provider", systemImage: "cpu")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(NSColor.labelColor))
                        Spacer()
                        Picker("", selection: $grammarProvider) {
                            ForEach(GrammarProviderID.allCases) { p in
                                Text(p.displayName).tag(p.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 170)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            settingsSection(title: "API Keys") {
                settingsCard {
                    ForEach(Array(GrammarProviderID.allCases.filter(\.requiresAPIKey).enumerated()), id: \.element.id) { index, provider in
                        HStack {
                            Text(provider.displayName)
                                .font(.system(size: 13))
                                .foregroundStyle(Color(NSColor.labelColor))
                            Spacer()
                            SecureField("API key", text: binding(for: provider.rawValue))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        if index < GrammarProviderID.allCases.filter(\.requiresAPIKey).count - 1 {
                            Divider().opacity(0.5)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button("Save API Keys") { saveKeychainValues() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Clear Correction Log") { correctionLogStore.clear() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Spacer()
                    Text("\(correctionLogStore.entries.count) corrections logged")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
            }

            if grammarProvider == GrammarProviderID.openCode.rawValue {
                settingsSection(title: "OpenCode") {
                    settingsCard {
                        settingsTextRow(label: "Model", systemImage: "cpu", binding: $openCodeModel, prompt: "e.g. deepseek-v4-flash-free")
                    }
                }
            }

            if grammarProvider == GrammarProviderID.ollama.rawValue {
                settingsSection(title: "Ollama") {
                    settingsCard {
                        settingsTextRow(label: "Base URL", systemImage: "network", binding: $ollamaBaseURL, prompt: "http://localhost:11434")
                        Divider().opacity(0.5)
                        settingsTextRow(label: "Model", systemImage: "cpu", binding: $ollamaModel, prompt: "e.g. gnokit/improve-grammar")
                    }
                    Text("Runs locally — no API key required.")
                        .font(.footnote)
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
            }

            if grammarProvider == GrammarProviderID.codexCLI.rawValue {
                settingsSection(title: "Codex CLI") {
                    settingsCard {
                        settingsTextRow(label: "Command", systemImage: "terminal", binding: $codexCLIPath, prompt: "codex or /path/to/codex")
                        Divider().opacity(0.5)
                        settingsTextRow(label: "Model", systemImage: "cpu", binding: $codexCLIModel, prompt: "optional, e.g. gpt-5.1-codex")
                        Divider().opacity(0.5)
                        cliLoginSection(
                            name: "OpenAI Codex",
                            status: codexLogin.status,
                            output: codexLogin.output,
                            authURL: codexLogin.authURL,
                            isSigningIn: codexLogin.isSigningIn,
                            isSignedIn: codexLogin.isSignedIn,
                            onRefresh: { codexLogin.refreshStatus(command: codexCLIPath) },
                            onSignIn: { codexLogin.start(command: codexCLIPath) },
                            onCancel: { codexLogin.cancel() },
                            onOpenURL: { codexLogin.openAuthURL() }
                        )
                    }
                    Text("Uses your existing Codex CLI login. Ask AI runs Codex in read-only mode.")
                        .font(.footnote)
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
            }

            if grammarProvider == GrammarProviderID.claudeCLI.rawValue {
                settingsSection(title: "Claude Code CLI") {
                    settingsCard {
                        settingsTextRow(label: "Command", systemImage: "terminal", binding: $claudeCLIPath, prompt: "claude or /path/to/claude")
                        Divider().opacity(0.5)
                        cliLoginSection(
                            name: "Claude (Pro/Max)",
                            status: claudeLogin.status,
                            output: claudeLogin.output,
                            authURL: nil,
                            isSigningIn: claudeLogin.isSigningIn,
                            isSignedIn: claudeLogin.isLoggedIn,
                            onRefresh: { claudeLogin.refreshStatus(command: claudeCLIPath) },
                            onSignIn: { claudeLogin.start(command: claudeCLIPath) },
                            onCancel: { claudeLogin.cancel() },
                            onOpenURL: {}
                        )

                        if claudeLogin.awaitingCode {
                            Divider().opacity(0.5)
                            HStack(spacing: 8) {
                                TextField("Paste authentication code", text: $claudeAuthCode)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        claudeLogin.submitAuthCode(claudeAuthCode)
                                        claudeAuthCode = ""
                                    }
                                Button("Submit") {
                                    claudeLogin.submitAuthCode(claudeAuthCode)
                                    claudeAuthCode = ""
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(claudeAuthCode.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                    Text("Uses your Claude.ai Pro/Max subscription via Claude Code CLI. No API key required.")
                        .font(.footnote)
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
            }
        }
    }

    @ViewBuilder
    private func cliLoginSection(
        name: String,
        status: String,
        output: String,
        authURL: URL?,
        isSigningIn: Bool,
        isSignedIn: Bool,
        onRefresh: @escaping () -> Void,
        onSignIn: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onOpenURL: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(NSColor.labelColor))
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
                Spacer()
                Button("Refresh") { onRefresh() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                if isSigningIn {
                    Button("Cancel") { onCancel() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else if !isSignedIn {
                    Button("Sign In") { onSignIn() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }

            if !output.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if authURL != nil {
                        Button("Open Auth URL") { onOpenURL() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Text(output)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(Color(NSColor.labelColor))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color(NSColor.textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
                        )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Clipboard tab

    private var clipboardContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsSection(title: "Retention") {
                settingsCard {
                    HStack {
                        Label("Maximum entries", systemImage: "list.number")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(NSColor.labelColor))
                        Spacer()
                        Stepper("\(maxEntries)", value: $maxEntries, in: 10...1000, step: 10)
                            .onChange(of: maxEntries) { _, _ in applyRetention() }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    Divider().opacity(0.5)
                    HStack {
                        Label("Maximum age", systemImage: "calendar")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(NSColor.labelColor))
                        Spacer()
                        Stepper("\(maxAgeDays) days", value: $maxAgeDays, in: 1...90)
                            .onChange(of: maxAgeDays) { _, _ in applyRetention() }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            settingsSection(title: "Actions") {
                HStack(spacing: 8) {
                    Button("Open Palette") { appState.openPalette() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Clear History", role: .destructive) { appState.clipboardService.clear() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Hotkeys tab

    private var hotkeysContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsSection(title: "Shortcuts") {
                settingsCard {
                    settingsTextRow(label: "Tidy selected text", systemImage: "sparkles", binding: $grammarHotkey, prompt: "control+option+g")
                    Divider().opacity(0.5)
                    settingsTextRow(label: "Clipboard palette", systemImage: "doc.on.clipboard", binding: $clipboardHotkey, prompt: "control+option+v")
                    Divider().opacity(0.5)
                    settingsTextRow(label: "Ask AI anything", systemImage: "bubble.left.and.bubble.right", binding: $askAIHotkey, prompt: "control+option+j")
                }
                Text("Format: control+option+j  ·  command+shift+v")
                    .font(.footnote)
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                Button("Apply Hotkeys") { appState.registerHotkeys() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Reusable components

    @ViewBuilder
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                .textCase(.uppercase)
                .kerning(0.5)
            content()
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }

    private func settingsToggleRow(label: String, systemImage: String, isOn: Binding<Bool>, onChange: ((Bool) -> Void)? = nil) -> some View {
        HStack {
            Label(label, systemImage: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(Color(NSColor.labelColor))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .onChange(of: isOn.wrappedValue) { _, v in onChange?(v) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func settingsTextRow(label: String, systemImage: String, binding: Binding<String>, prompt: String) -> some View {
        HStack {
            Label(label, systemImage: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(Color(NSColor.labelColor))
            Spacer()
            TextField(prompt, text: binding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { appState.registerHotkeys() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Keychain helpers

    private func binding(for key: String) -> Binding<String> {
        Binding(get: { keyValues[key, default: ""] }, set: { keyValues[key] = $0 })
    }

    private func loadKeychainValues() {
        for p in GrammarProviderID.allCases { keyValues[p.rawValue] = KeychainStore.read(key: p.rawValue) ?? "" }
    }

    private func saveKeychainValues() {
        for (key, value) in keyValues {
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                KeychainStore.delete(key: key)
            } else {
                try? KeychainStore.save(value, key: key)
            }
        }
    }

    private func applyRetention() {
        appState.clipboardService.applyRetention(maxEntries: maxEntries, maxAgeDays: maxAgeDays)
    }
}
