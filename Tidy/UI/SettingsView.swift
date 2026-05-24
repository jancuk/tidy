import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var correctionLogStore: CorrectionLogStore
    @AppStorage(AppDefaults.grammarProvider)     private var grammarProvider    = GrammarProviderID.gemini.rawValue
    @AppStorage(AppDefaults.grammarHotkey)       private var grammarHotkey      = Hotkey.grammarDefault.displayValue
    @AppStorage(AppDefaults.clipboardHotkey)     private var clipboardHotkey    = Hotkey.clipboardDefault.displayValue
    @AppStorage(AppDefaults.clipboardMaxEntries) private var maxEntries         = 200
    @AppStorage(AppDefaults.clipboardMaxAgeDays) private var maxAgeDays         = 7
    @AppStorage(AppDefaults.openCodeModel)       private var openCodeModel      = "deepseek-v4-flash-free"
    @AppStorage(AppDefaults.ollamaBaseURL)       private var ollamaBaseURL      = "http://localhost:11434"
    @AppStorage(AppDefaults.ollamaModel)         private var ollamaModel        = "gnokit/improve-grammar"
    @AppStorage(AppDefaults.appearanceMode)      private var appearanceMode     = "system"

    @State private var launchAtLogin   = false
    @State private var keyValues: [String: String] = [:]
    @State private var statusMessage   = ""
    @State private var selectedTab     = SettingsTab.general

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider()
            content
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            launchAtLogin = appState.launchAtLoginEnabled
            loadKeychainValues()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(NSColor.labelColor))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: Tab Bar

    enum SettingsTab: String, CaseIterable {
        case general  = "General"
        case grammar  = "Grammar"
        case clipboard = "Clipboard"
        case hotkeys  = "Hotkeys"
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab
                            ? Color(NSColor.labelColor)
                            : Color(NSColor.secondaryLabelColor))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if selectedTab == tab {
                                Rectangle()
                                    .fill(Color(NSColor.labelColor).opacity(0.8))
                                    .frame(height: 2)
                                    .offset(y: 0.5)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch selectedTab {
                case .general:   generalContent
                case .grammar:   grammarContent
                case .clipboard: clipboardContent
                case .hotkeys:   hotkeysContent
                }
            }
            .padding(20)
        }
    }

    // MARK: General

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection(title: "App") {
                settingsGroup {
                    settingsToggleRow(
                        label: "Launch at login",
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
                settingsGroup {
                    HStack {
                        Text("Color scheme")
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
                settingsGroup {
                    HStack {
                        Label(
                            Permissions.isAccessibilityTrusted ? "Accessibility allowed" : "Accessibility needed",
                            systemImage: Permissions.isAccessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
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

    // MARK: Grammar

    private var grammarContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection(title: "Provider") {
                settingsGroup {
                    HStack {
                        Text("Provider")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(NSColor.labelColor))
                        Spacer()
                        Picker("", selection: $grammarProvider) {
                            ForEach(GrammarProviderID.allCases) { p in
                                Text(p.displayName).tag(p.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 160)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            settingsSection(title: "API Keys") {
                settingsGroup {
                    ForEach(GrammarProviderID.allCases.filter(\.requiresAPIKey)) { provider in
                        VStack(alignment: .leading, spacing: 0) {
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
                            Divider().opacity(0.5)
                        }
                    }
                    HStack {
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            if grammarProvider == GrammarProviderID.openCode.rawValue {
                settingsSection(title: "OpenCode") {
                    settingsGroup {
                        settingsTextRow(label: "Model", binding: $openCodeModel, prompt: "e.g. deepseek-v4-flash-free")
                    }
                }
            }

            if grammarProvider == GrammarProviderID.ollama.rawValue {
                settingsSection(title: "Ollama") {
                    settingsGroup {
                        settingsTextRow(label: "Base URL", binding: $ollamaBaseURL, prompt: "http://localhost:11434")
                        Divider().opacity(0.5)
                        settingsTextRow(label: "Model", binding: $ollamaModel, prompt: "e.g. gnokit/improve-grammar")
                    }
                    Text("Runs locally — no API key required.")
                        .font(.footnote)
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
            }
        }
    }

    // MARK: Clipboard

    private var clipboardContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection(title: "Retention") {
                settingsGroup {
                    HStack {
                        Text("Maximum entries")
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
                        Text("Maximum age")
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
                HStack {
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

    // MARK: Hotkeys

    private var hotkeysContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection(title: "Shortcuts") {
                settingsGroup {
                    settingsTextRow(label: "Tidy selected text", binding: $grammarHotkey, prompt: "control+option+g")
                    Divider().opacity(0.5)
                    settingsTextRow(label: "Clipboard palette", binding: $clipboardHotkey, prompt: "control+option+v")
                }
                Text("Format: control+option+g or command+shift+v")
                    .font(.footnote)
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                Button("Apply Hotkeys") { appState.registerHotkeys() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    // MARK: Reusable row helpers

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
    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 0.5)
        )
    }

    private func settingsToggleRow(label: String, isOn: Binding<Bool>, onChange: ((Bool) -> Void)? = nil) -> some View {
        HStack {
            Text(label)
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

    private func settingsTextRow(label: String, binding: Binding<String>, prompt: String) -> some View {
        HStack {
            Text(label)
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

    // MARK: Keychain helpers

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
