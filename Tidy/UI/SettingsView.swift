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
    @AppStorage(AppDefaults.deepSeekModel)       private var deepSeekModel      = "deepseek-v4-flash"
    @AppStorage(AppDefaults.ollamaBaseURL)       private var ollamaBaseURL      = "http://localhost:11434"
    @AppStorage(AppDefaults.ollamaModel)         private var ollamaModel        = "gnokit/improve-grammar"
    @AppStorage(AppDefaults.codexCLIPath)        private var codexCLIPath       = "codex"
    @AppStorage(AppDefaults.codexCLIModel)       private var codexCLIModel      = ""
    @AppStorage(AppDefaults.claudeCLIPath)       private var claudeCLIPath      = "claude"
    @AppStorage(AppDefaults.appearanceMode)      private var appearanceMode     = "system"
    @AppStorage(AppDefaults.jiraSiteURL)         private var jiraSiteURL        = ""
    @AppStorage(AppDefaults.jiraEmail)           private var jiraEmail          = ""
    @AppStorage(AppDefaults.asanaWorkspaceGID)   private var asanaWorkspaceGID  = ""
    @AppStorage(AppDefaults.mcpServerURL)         private var mcpServerURL       = ""
    @AppStorage(AppDefaults.mcpAPIKeyHeader)      private var mcpAPIKeyHeader    = "x-api-key"
    @AppStorage(AppDefaults.mcpAutoRefreshEnabled) private var mcpAutoRefresh    = false
    @AppStorage(AppDefaults.mcpRefreshMinutes)    private var mcpRefreshMinutes  = 15
    @AppStorage(AppDefaults.slackNotificationChannels) private var slackFocusChannels = ""
    @AppStorage(AppDefaults.slackNotificationGroups) private var slackMentionGroups = "@channel, @here, @everyone"
    @AppStorage(AppDefaults.slackIncludeGroupMentions) private var slackIncludeGroupMentions = false
    @AppStorage(AppDefaults.slackNotificationTopicLimit) private var slackTopicLimit = 10
    @AppStorage(AppDefaults.settingsTab)          private var storedSettingsTab  = SettingsTab.general.rawValue

    @State private var launchAtLogin   = false
    @State private var keyValues: [String: String] = [:]
    @State private var statusMessage   = ""
    @State private var selectedTab     = SettingsTab.general
    @State private var claudeAuthCode  = ""
    @State private var jiraAPIToken    = ""
    @State private var jiraStatus      = ""
    @State private var isTestingJira   = false
    @State private var asanaClientID     = ""
    @State private var asanaClientSecret = ""
    @State private var asanaAuthCode     = ""
    @State private var asanaStatus     = ""
    @State private var isTestingAsana  = false
    @State private var mcpAPIKey        = ""
    @State private var mcpStatus        = ""
    @State private var isTestingMCP     = false
    @State private var mcpMappings: [MCPIntegrationSource: String] = [:]
    @State private var mcpToolCount     = 0
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
            selectedTab = SettingsTab(rawValue: storedSettingsTab) ?? .general
            loadKeychainValues()
            codexLogin.refreshStatus(command: codexCLIPath)
            claudeLogin.refreshStatus(command: claudeCLIPath)
            jiraAPIToken = KeychainStore.read(key: JiraConfiguration.tokenKey) ?? ""
            asanaClientID = KeychainStore.read(key: AsanaConfiguration.clientIDKey) ?? ""
            asanaClientSecret = KeychainStore.read(key: AsanaConfiguration.clientSecretKey) ?? ""
            mcpAPIKey = KeychainStore.read(key: MCPServerConfiguration.apiKeyKeychainKey) ?? ""
            appState.asanaService.configurationDidChange()
        }
        .onChange(of: selectedTab) { _, tab in
            storedSettingsTab = tab.rawValue
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
        case jira      = "Jira"
        case asana     = "Asana"
        case mcp       = "MCP"

        var systemImage: String {
            switch self {
            case .general:   "gear"
            case .model:     "cpu"
            case .clipboard: "doc.on.clipboard"
            case .hotkeys:   "keyboard"
            case .jira:      "shippingbox"
            case .asana:     "checklist"
            case .mcp:       "point.3.connected.trianglepath.dotted"
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
                case .jira:      jiraContent
                case .asana:     asanaContent
                case .mcp:       mcpContent
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

            if grammarProvider == GrammarProviderID.deepSeek.rawValue {
                settingsSection(title: "DeepSeek") {
                    settingsCard {
                        settingsTextRow(label: "Model", systemImage: "cpu", binding: $deepSeekModel, prompt: "e.g. deepseek-v4-flash")
                    }
                    Text("Uses DeepSeek's Anthropic-compatible Messages API.")
                        .font(.footnote)
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
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
                            onReauthenticate: { codexLogin.reauthenticate(command: codexCLIPath) },
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
        onReauthenticate: (() -> Void)? = nil,
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
                } else if let onReauthenticate {
                    Button("Sign In Again") { onReauthenticate() }
                        .buttonStyle(.bordered)
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

    // MARK: - Jira tab

    private var jiraContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsSection(title: "Jira Cloud Connection") {
                settingsCard {
                    settingsTextRow(
                        label: "Site URL",
                        systemImage: "globe",
                        binding: $jiraSiteURL,
                        prompt: "https://company.atlassian.net"
                    )
                    Divider().opacity(0.5)
                    settingsTextRow(
                        label: "Account email",
                        systemImage: "envelope",
                        binding: $jiraEmail,
                        prompt: "you@company.com"
                    )
                    Divider().opacity(0.5)
                    HStack {
                        Label("API token", systemImage: "key")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(NSColor.labelColor))
                        Spacer()
                        SecureField("Atlassian API token", text: $jiraAPIToken)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                HStack(spacing: 8) {
                    Button("Save Connection") { saveJiraConnection() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                    Button {
                        testJiraConnection()
                    } label: {
                        if isTestingJira {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Testing…")
                            }
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isTestingJira || jiraSiteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || jiraAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Link(
                        "Create API Token",
                        destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!
                    )
                    .font(.system(size: 11))

                    Spacer()
                }
            }

            settingsSection(title: "Security") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(Color.green)
                    Text("Your API token is stored in macOS Keychain. Tidy uses your email and token only to talk directly to the Jira Cloud site you enter.")
                        .font(.footnote)
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
            }

            if !jiraStatus.isEmpty {
                Text(jiraStatus)
                    .font(.footnote)
                    .foregroundStyle(jiraStatus.hasPrefix("Connected") || jiraStatus.hasPrefix("Saved") ? Color.green : Color.red)
            }
        }
    }

    // MARK: - Asana tab

    private var asanaContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsSection(title: "Required Asana setup") {
                settingsCard {
                    HStack(spacing: 12) {
                        Label("Redirect URL", systemImage: "arrow.turn.down.right")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(NSColor.labelColor))
                        Spacer()
                        Text(AsanaOAuthClient.redirectURI)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                            .textSelection(.enabled)
                        Button("Copy") {
                            copyAsanaValue(
                                AsanaOAuthClient.redirectURI,
                                status: "Copied redirect URL."
                            )
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider().opacity(0.5)

                    HStack(spacing: 12) {
                        Label("Permission scopes", systemImage: "checklist")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(NSColor.labelColor))
                        Spacer()
                        Text(AsanaOAuthClient.requiredScopes.joined(separator: " "))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                        Button("Copy") {
                            copyAsanaValue(
                                AsanaOAuthClient.requiredScopes.joined(separator: " "),
                                status: "Copied permission scopes."
                            )
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                HStack(spacing: 8) {
                    Text("Add this exact redirect URL and these scopes under OAuth in your Asana app before connecting.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))

                    Link(
                        "Open Asana developer console",
                        destination: URL(string: "https://app.asana.com/0/my-apps")!
                    )
                    .font(.system(size: 11))

                    Spacer()
                }
            }

            settingsSection(title: "App credentials") {
                settingsCard {
                    HStack {
                        Label("Client ID", systemImage: "person.text.rectangle")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(NSColor.labelColor))
                        Spacer()
                        TextField("Asana Client ID", text: $asanaClientID)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider().opacity(0.5)

                    HStack {
                        Label("Client secret", systemImage: "key")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(NSColor.labelColor))
                        Spacer()
                        SecureField("Asana Client secret", text: $asanaClientSecret)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                HStack(spacing: 8) {
                    Button("Connect with Asana") {
                        startAsanaAuthorization()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(
                        isTestingAsana
                            || asanaClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || asanaClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    Link(
                        "Asana OAuth documentation",
                        destination: URL(string: "https://developers.asana.com/docs/oauth")!
                    )
                    .font(.system(size: 11))

                    Spacer()
                }
            }

            if appState.asanaService.isAuthorizationInProgress {
                settingsSection(title: "Finish authorization") {
                    settingsCard {
                        HStack {
                            Label("Authorization code", systemImage: "number")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(NSColor.labelColor))
                            Spacer()
                            TextField("Paste the code from Asana", text: $asanaAuthCode)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 260)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }

                    Button {
                        completeAsanaAuthorization()
                    } label: {
                        if isTestingAsana {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Connecting…")
                            }
                        } else {
                            Text("Complete Connection")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(
                        isTestingAsana
                            || asanaAuthCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }

            settingsSection(title: "Workspace") {
                settingsCard {
                    HStack {
                        Label("Workspace", systemImage: "building.2")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(NSColor.labelColor))
                        Spacer()
                        if appState.asanaService.workspaces.isEmpty {
                            Text(asanaWorkspaceGID.isEmpty ? "Test connection to load" : asanaWorkspaceGID)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(width: 260, alignment: .trailing)
                        } else {
                            Picker("", selection: $asanaWorkspaceGID) {
                                ForEach(appState.asanaService.workspaces) { workspace in
                                    Text(workspace.name).tag(workspace.gid)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 260)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                HStack(spacing: 8) {
                    Button {
                        testAsanaConnection()
                    } label: {
                        if isTestingAsana {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Testing…")
                            }
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(
                        isTestingAsana
                            || !appState.asanaService.isConfigured
                    )

                    Spacer()
                }
            }

            settingsSection(title: "Security") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(Color.green)
                    Text("Your Client ID, Client Secret, access token, and refresh token are stored in macOS Keychain. Tidy opens Asana for your approval, exchanges the authorization code directly with Asana, and refreshes expired access tokens automatically.")
                        .font(.footnote)
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
            }

            if !asanaStatus.isEmpty {
                Text(asanaStatus)
                    .font(.footnote)
                    .foregroundStyle(
                        asanaStatus.hasPrefix("Connected")
                            || asanaStatus.hasPrefix("Saved")
                            || asanaStatus.hasPrefix("Copied")
                            || asanaStatus.hasPrefix("Authorize")
                            ? Color.green
                            : Color.red
                    )
            }
        }
    }

    // MARK: - MCP tab

    private var mcpContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsSection(title: "MCP Connection") {
                settingsCard {
                    settingsTextRow(
                        label: "Server URL",
                        systemImage: "network",
                        binding: $mcpServerURL,
                        prompt: "https://mcp.example.com/api"
                    )
                    Divider().opacity(0.5)
                    settingsTextRow(
                        label: "API key header",
                        systemImage: "tag",
                        binding: $mcpAPIKeyHeader,
                        prompt: "x-api-key"
                    )
                    Divider().opacity(0.5)
                    HStack {
                        Label("API key", systemImage: "key")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(NSColor.labelColor))
                        Spacer()
                        SecureField("MCP API key", text: $mcpAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 300)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                HStack(spacing: 8) {
                    Button("Save Connection") { saveMCPConnection() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                    Button {
                        testMCPConnection()
                    } label: {
                        if isTestingMCP {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Testing…")
                            }
                        } else {
                            Text("Test & Discover Tools")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(
                        isTestingMCP
                            || mcpServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || mcpAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    Spacer()
                }
            }

            settingsSection(title: "Slack Focus") {
                settingsCard {
                    HStack {
                        Label("Topic limit", systemImage: "list.number")
                            .font(.system(size: 13))
                        Spacer()
                        Picker("Topic limit", selection: $slackTopicLimit) {
                            Text("5").tag(5)
                            Text("10").tag(10)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                        .onChange(of: slackTopicLimit) { _, _ in
                            appState.unifiedNotificationService.configurationDidChange()
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    Divider().opacity(0.5)
                    settingsTextRow(
                        label: "Whitelisted channels",
                        systemImage: "number",
                        binding: $slackFocusChannels,
                        prompt: "#channel-one, #channel-two"
                    )
                    .onChange(of: slackFocusChannels) { _, _ in
                        appState.unifiedNotificationService.configurationDidChange()
                    }
                    Divider().opacity(0.5)
                    settingsToggleRow(
                        label: "Include group mentions",
                        systemImage: "person.3",
                        isOn: $slackIncludeGroupMentions,
                        onChange: { _ in
                            appState.unifiedNotificationService.configurationDidChange()
                        }
                    )
                    Divider().opacity(0.5)
                    settingsTextRow(
                        label: "Group mentions",
                        systemImage: "person.3",
                        binding: $slackMentionGroups,
                        prompt: "@channel, @here, @everyone, @your-team"
                    )
                    .onChange(of: slackMentionGroups) { _, _ in
                        appState.unifiedNotificationService.configurationDidChange()
                    }
                    .disabled(!slackIncludeGroupMentions)
                    .opacity(slackIncludeGroupMentions ? 1 : 0.5)
                }
                Text("Slack shows 5 or 10 distinct threads/topics containing an incoming direct mention of your signed-in Slack user. Older matches are backfilled when the recent window has too few topics. Group mentions are optional. Results are limited to the whitelisted channels; leave channels blank to search all accessible channels.")
                    .font(.footnote)
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }

            settingsSection(title: "Notification Refresh") {
                settingsCard {
                    settingsToggleRow(
                        label: "Refresh summaries automatically",
                        systemImage: "arrow.clockwise",
                        isOn: $mcpAutoRefresh,
                        onChange: { _ in
                            appState.unifiedNotificationService.configurationDidChange()
                        }
                    )
                    Divider().opacity(0.5)
                    HStack {
                        Label("Refresh interval", systemImage: "timer")
                            .font(.system(size: 13))
                        Spacer()
                        Stepper(
                            "\(mcpRefreshMinutes) minutes",
                            value: $mcpRefreshMinutes,
                            in: 5...120,
                            step: 5
                        )
                        .onChange(of: mcpRefreshMinutes) { _, _ in
                            appState.unifiedNotificationService.configurationDidChange()
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                Text("Automatic refresh is off by default because each source summary can use your selected AI provider.")
                    .font(.footnote)
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }

            if !mcpMappings.isEmpty {
                settingsSection(title: "Discovered Read-only Tools") {
                    settingsCard {
                        ForEach(Array(MCPIntegrationSource.allCases.enumerated()), id: \.element.id) { index, source in
                            HStack {
                                Label(source.title, systemImage: source.notificationSystemImage)
                                    .font(.system(size: 13))
                                Spacer()
                                Text(mcpMappings[source, default: "Not detected"])
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(
                                        mcpMappings[source] == "Not detected"
                                            ? Color.orange
                                            : Color(NSColor.secondaryLabelColor)
                                    )
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            if index < MCPIntegrationSource.allCases.count - 1 {
                                Divider().opacity(0.5)
                            }
                        }
                    }
                    Text("\(mcpToolCount) MCP entry tools advertised. Dynamic catalog tools are resolved per source; Tidy only calls safe read operations.")
                        .font(.footnote)
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
            }

            settingsSection(title: "Security") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(Color.green)
                    Text("The MCP API key is stored in macOS Keychain and is sent only to the HTTPS server URL above. To create summaries, bounded tool output is sent to your selected AI provider; choose Ollama for local summarization. Tool results are treated as untrusted data, and Tidy will not automatically invoke mutating tools.")
                        .font(.footnote)
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
            }

            if !mcpStatus.isEmpty {
                Text(mcpStatus)
                    .font(.footnote)
                    .foregroundStyle(
                        mcpStatus.hasPrefix("Connected") || mcpStatus.hasPrefix("Saved")
                            ? Color.green
                            : Color.red
                    )
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

    private func saveJiraConnection() {
        jiraSiteURL = jiraSiteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        jiraEmail = jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = jiraAPIToken.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if token.isEmpty {
                KeychainStore.delete(key: JiraConfiguration.tokenKey)
            } else {
                try KeychainStore.save(token, key: JiraConfiguration.tokenKey)
            }
            appState.jiraService.configurationDidChange()
            jiraStatus = "Saved Jira connection securely."
        } catch {
            jiraStatus = error.localizedDescription
        }
    }

    private func testJiraConnection() {
        saveJiraConnection()
        isTestingJira = true
        Task {
            defer { isTestingJira = false }
            do {
                let user = try await appState.jiraService.testConnection()
                jiraStatus = "Connected as \(user.displayName). Account ID: \(user.accountId)"
            } catch {
                jiraStatus = error.localizedDescription
            }
        }
    }

    @discardableResult
    private func saveAsanaCredentials() -> Bool {
        let clientID = asanaClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = asanaClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let existing = AsanaConfiguration.current
            let credentialsChanged = existing.clientID != clientID
                || existing.clientSecret != clientSecret
            try KeychainStore.save(clientID, key: AsanaConfiguration.clientIDKey)
            try KeychainStore.save(clientSecret, key: AsanaConfiguration.clientSecretKey)
            if credentialsChanged {
                KeychainStore.delete(key: AsanaConfiguration.accessTokenKey)
                KeychainStore.delete(key: AsanaConfiguration.refreshTokenKey)
                UserDefaults.standard.set(0.0, forKey: AppDefaults.asanaTokenExpiresAt)
                asanaWorkspaceGID = ""
            }
            appState.asanaService.configurationDidChange()
            return true
        } catch {
            asanaStatus = error.localizedDescription
            return false
        }
    }

    private func startAsanaAuthorization() {
        guard saveAsanaCredentials() else { return }
        do {
            let url = try appState.asanaService.startAuthorization(clientID: asanaClientID)
            guard NSWorkspace.shared.open(url) else {
                asanaStatus = "Could not open Asana in your browser."
                return
            }
            asanaAuthCode = ""
            asanaStatus = "Authorize Tidy in Asana, then paste the code shown there."
        } catch {
            asanaStatus = error.localizedDescription
        }
    }

    private func copyAsanaValue(_ value: String, status: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        asanaStatus = status
    }

    private func completeAsanaAuthorization() {
        guard saveAsanaCredentials() else { return }
        isTestingAsana = true
        Task {
            defer { isTestingAsana = false }
            do {
                let (user, workspaces) = try await appState.asanaService.completeAuthorization(
                    code: asanaAuthCode,
                    clientID: asanaClientID,
                    clientSecret: asanaClientSecret
                )
                if asanaWorkspaceGID.isEmpty
                    || !workspaces.contains(where: { $0.gid == asanaWorkspaceGID }) {
                    asanaWorkspaceGID = workspaces.first?.gid ?? ""
                }
                appState.asanaService.configurationDidChange()
                let workspaceName = workspaces.first(where: { $0.gid == asanaWorkspaceGID })?.name
                    ?? "no workspace"
                asanaStatus = user.map { "Connected as \($0.name) · \(workspaceName)." }
                    ?? "Connected to \(workspaceName)."
                asanaAuthCode = ""
            } catch {
                asanaStatus = error.localizedDescription
            }
        }
    }

    private func testAsanaConnection() {
        isTestingAsana = true
        Task {
            defer { isTestingAsana = false }
            do {
                let (user, workspaces) = try await appState.asanaService.testConnection()
                if asanaWorkspaceGID.isEmpty
                    || !workspaces.contains(where: { $0.gid == asanaWorkspaceGID }) {
                    asanaWorkspaceGID = workspaces.first?.gid ?? ""
                }
                appState.asanaService.configurationDidChange()
                let workspaceName = workspaces.first(where: { $0.gid == asanaWorkspaceGID })?.name
                    ?? "no workspace"
                asanaStatus = user.map { "Connected as \($0.name) · \(workspaceName)." }
                    ?? "Connected to \(workspaceName)."
            } catch {
                asanaStatus = error.localizedDescription
            }
        }
    }

    @discardableResult
    private func saveMCPConnection() -> MCPServerConfiguration? {
        do {
            let configuration = try MCPServerConfiguration(
                endpointText: mcpServerURL,
                apiKeyHeaderName: mcpAPIKeyHeader,
                apiKey: mcpAPIKey
            )
            mcpServerURL = configuration.endpoint.absoluteString
            mcpAPIKeyHeader = configuration.apiKeyHeaderName
            try KeychainStore.save(
                configuration.apiKey,
                key: MCPServerConfiguration.apiKeyKeychainKey
            )
            appState.unifiedNotificationService.configurationDidChange()
            mcpStatus = "Saved MCP connection securely."
            return configuration
        } catch {
            mcpStatus = error.localizedDescription
            return nil
        }
    }

    private func testMCPConnection() {
        guard let configuration = saveMCPConnection() else { return }
        isTestingMCP = true
        Task {
            defer { isTestingMCP = false }
            do {
                let result = try await appState.unifiedNotificationService.testConnection(
                    configuration: configuration
                )
                mcpMappings = result.mappings
                mcpToolCount = result.tools.count
                mcpStatus = "Connected to \(result.serverName). Discovered \(result.tools.count) tools."
            } catch {
                mcpMappings = [:]
                mcpToolCount = 0
                mcpStatus = error.localizedDescription
            }
        }
    }
}
