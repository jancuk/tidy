import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppDefaults.grammarProvider) private var grammarProvider = GrammarProviderID.gemini.rawValue
    @AppStorage(AppDefaults.grammarHotkey) private var grammarHotkey = Hotkey.grammarDefault.displayValue
    @AppStorage(AppDefaults.clipboardHotkey) private var clipboardHotkey = Hotkey.clipboardDefault.displayValue
    @AppStorage(AppDefaults.clipboardMaxEntries) private var maxEntries = 200
    @AppStorage(AppDefaults.clipboardMaxAgeDays) private var maxAgeDays = 7
    @AppStorage(AppDefaults.openCodeModel) private var openCodeModel = "deepseek-v4-flash-free"
    @AppStorage(AppDefaults.ollamaBaseURL) private var ollamaBaseURL = "http://localhost:11434"
    @AppStorage(AppDefaults.ollamaModel) private var ollamaModel = "gnokit/improve-grammar"

    @State private var launchAtLogin = false
    @State private var keyValues: [String: String] = [:]
    @State private var statusMessage = ""

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            grammarTab
                .tabItem { Label("Grammar", systemImage: "textformat") }
            clipboardTab
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
            hotkeysTab
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 640, height: 430)
        .padding(20)
        .onAppear {
            launchAtLogin = appState.launchAtLoginEnabled
            loadKeychainValues()
        }
    }

    private var generalTab: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, value in
                    do {
                        try appState.setLaunchAtLogin(value)
                    } catch {
                        statusMessage = error.localizedDescription
                        launchAtLogin = appState.launchAtLoginEnabled
                    }
                }

            HStack {
                Label(Permissions.isAccessibilityTrusted ? "Accessibility allowed" : "Accessibility permission needed", systemImage: Permissions.isAccessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(Permissions.isAccessibilityTrusted ? .green : .orange)
                Spacer()
                Button("Open Settings") {
                    Permissions.openAccessibilitySettings()
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var grammarTab: some View {
        Form {
            Picker("Provider", selection: $grammarProvider) {
                ForEach(GrammarProviderID.allCases) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }

            ForEach(GrammarProviderID.allCases) { provider in
                if provider.requiresAPIKey {
                    SecureField("\(provider.displayName) API key", text: binding(for: provider.rawValue))
                        .textFieldStyle(.roundedBorder)
                }
            }

            if grammarProvider == GrammarProviderID.openCode.rawValue {
                TextField("OpenCode model", text: $openCodeModel, prompt: Text("e.g. deepseek-v4-flash-free, minimax-m2.5-free"))
                    .textFieldStyle(.roundedBorder)
                Text("Sent as the 'model' field to https://opencode.ai/zen/v1/chat/completions")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if grammarProvider == GrammarProviderID.ollama.rawValue {
                TextField("Ollama base URL", text: $ollamaBaseURL, prompt: Text("http://localhost:11434"))
                    .textFieldStyle(.roundedBorder)
                TextField("Ollama model", text: $ollamaModel, prompt: Text("e.g. gnokit/improve-grammar, llama3.1"))
                    .textFieldStyle(.roundedBorder)
                Text("Runs locally — no API key required. Posts to {baseURL}/api/chat.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("Gemini Flash uses VITE_GEMINI_API_KEY from the app environment first, then this saved key.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button("Save API Keys") {
                    saveKeychainValues()
                }
                Button("Clear Correction Log") {
                    appState.correctionLogStore.clear()
                }
                Spacer()
                Text("\(appState.correctionLogStore.entries.count) logged corrections")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var clipboardTab: some View {
        Form {
            Stepper("Maximum entries: \(maxEntries)", value: $maxEntries, in: 10...1000, step: 10)
                .onChange(of: maxEntries) { _, _ in applyRetention() }
            Stepper("Maximum age: \(maxAgeDays) days", value: $maxAgeDays, in: 1...90)
                .onChange(of: maxAgeDays) { _, _ in applyRetention() }

            HStack {
                Button("Open Palette") {
                    appState.openPalette()
                }
                Button("Clear Clipboard History", role: .destructive) {
                    appState.clipboardService.clear()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var hotkeysTab: some View {
        Form {
            TextField("Grammar correction", text: $grammarHotkey)
                .onSubmit { appState.registerHotkeys() }
            TextField("Clipboard palette", text: $clipboardHotkey)
                .onSubmit { appState.registerHotkeys() }
            Text("Use forms like control+option+g or command+shift+v.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Apply Hotkeys") {
                appState.registerHotkeys()
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tidy")
                .font(.largeTitle.weight(.semibold))
            Text("Tidy your text.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Divider()
            Text("Grammar correction: \(Hotkey.grammarDefault.displayValue)")
            Text("Clipboard palette: \(Hotkey.clipboardDefault.displayValue)")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { keyValues[key, default: ""] },
            set: { keyValues[key] = $0 }
        )
    }

    private func loadKeychainValues() {
        for provider in GrammarProviderID.allCases {
            keyValues[provider.rawValue] = KeychainStore.read(key: provider.rawValue) ?? ""
        }
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
