import Carbon
import Foundation

struct Hotkey: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var displayValue: String

    static let grammarDefault = Hotkey(keyCode: UInt32(kVK_ANSI_G), carbonModifiers: UInt32(controlKey | optionKey), displayValue: "control+option+g")
    static let clipboardDefault = Hotkey(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(controlKey | optionKey), displayValue: "control+option+v")
    static let askAIDefault = Hotkey(keyCode: UInt32(kVK_ANSI_J), carbonModifiers: UInt32(controlKey | optionKey), displayValue: "control+option+j")

    static func parse(_ rawValue: String, fallback: Hotkey) -> Hotkey {
        let pieces = rawValue
            .lowercased()
            .replacingOccurrences(of: "⌃", with: "control+")
            .replacingOccurrences(of: "⌥", with: "option+")
            .replacingOccurrences(of: "⌘", with: "command+")
            .replacingOccurrences(of: "⇧", with: "shift+")
            .split(whereSeparator: { ["+", "-", " "].contains(String($0)) })
            .map(String.init)

        var modifiers: UInt32 = 0
        var keyCode: UInt32?

        for piece in pieces {
            switch piece {
            case "ctrl", "control":
                modifiers |= UInt32(controlKey)
            case "opt", "option", "alt":
                modifiers |= UInt32(optionKey)
            case "cmd", "command":
                modifiers |= UInt32(cmdKey)
            case "shift":
                modifiers |= UInt32(shiftKey)
            default:
                keyCode = keyCodeForKey(piece)
            }
        }

        guard let keyCode else { return fallback }
        return Hotkey(keyCode: keyCode, carbonModifiers: modifiers, displayValue: normalizedDisplayValue(for: rawValue, fallback: fallback.displayValue))
    }

    private static func normalizedDisplayValue(for rawValue: String, fallback: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func keyCodeForKey(_ key: String) -> UInt32? {
        switch key {
        case "a": UInt32(kVK_ANSI_A)
        case "b": UInt32(kVK_ANSI_B)
        case "c": UInt32(kVK_ANSI_C)
        case "d": UInt32(kVK_ANSI_D)
        case "e": UInt32(kVK_ANSI_E)
        case "f": UInt32(kVK_ANSI_F)
        case "g": UInt32(kVK_ANSI_G)
        case "h": UInt32(kVK_ANSI_H)
        case "i": UInt32(kVK_ANSI_I)
        case "j": UInt32(kVK_ANSI_J)
        case "k": UInt32(kVK_ANSI_K)
        case "l": UInt32(kVK_ANSI_L)
        case "m": UInt32(kVK_ANSI_M)
        case "n": UInt32(kVK_ANSI_N)
        case "o": UInt32(kVK_ANSI_O)
        case "p": UInt32(kVK_ANSI_P)
        case "q": UInt32(kVK_ANSI_Q)
        case "r": UInt32(kVK_ANSI_R)
        case "s": UInt32(kVK_ANSI_S)
        case "t": UInt32(kVK_ANSI_T)
        case "u": UInt32(kVK_ANSI_U)
        case "v": UInt32(kVK_ANSI_V)
        case "w": UInt32(kVK_ANSI_W)
        case "x": UInt32(kVK_ANSI_X)
        case "y": UInt32(kVK_ANSI_Y)
        case "z": UInt32(kVK_ANSI_Z)
        case "0": UInt32(kVK_ANSI_0)
        case "1": UInt32(kVK_ANSI_1)
        case "2": UInt32(kVK_ANSI_2)
        case "3": UInt32(kVK_ANSI_3)
        case "4": UInt32(kVK_ANSI_4)
        case "5": UInt32(kVK_ANSI_5)
        case "6": UInt32(kVK_ANSI_6)
        case "7": UInt32(kVK_ANSI_7)
        case "8": UInt32(kVK_ANSI_8)
        case "9": UInt32(kVK_ANSI_9)
        case "space": UInt32(kVK_Space)
        case "return", "enter": UInt32(kVK_Return)
        default: nil
        }
    }
}

enum AppDefaults {
    static let grammarHotkey = "grammarHotkey"
    static let clipboardHotkey = "clipboardHotkey"
    static let askAIHotkey = "askAIHotkey"
    static let grammarProvider = "grammarProvider"
    static let clipboardMaxEntries = "clipboardMaxEntries"
    static let clipboardMaxAgeDays = "clipboardMaxAgeDays"
    static let didCompleteFirstRun = "didCompleteFirstRun"
    static let autoSuggestEnabled = "autoSuggestEnabled"
    static let openCodeModel = "openCodeModel"
    static let deepSeekModel = "deepSeekModel"
    static let ollamaBaseURL = "ollamaBaseURL"
    static let ollamaModel = "ollamaModel"
    static let codexCLIPath = "codexCLIPath"
    static let codexCLIModel = "codexCLIModel"
    static let claudeCLIPath = "claudeCLIPath"
    static let appearanceMode = "appearanceMode"
    static let jiraSiteURL = "jiraSiteURL"
    static let jiraEmail = "jiraEmail"
    static let jiraProjectKey = "jiraProjectKey"
    static let jiraAssigneeAccountID = "jiraAssigneeAccountID"
    static let jiraNotificationsLastSeenAt = "jiraNotificationsLastSeenAt"
    static let dashboardSection = "dashboardSection"
    static let jiraWorkspaceMode = "jiraWorkspaceMode"
    static let asanaWorkspaceGID = "asanaWorkspaceGID"
    static let asanaTokenExpiresAt = "asanaTokenExpiresAt"
    static let terminalWorkingDirectory = "terminalWorkingDirectory"
    static let sidebarCollapsed = "sidebarCollapsed"
    static let mcpServerURL = "mcpServerURL"
    static let mcpAPIKeyHeader = "mcpAPIKeyHeader"
    static let mcpAutoRefreshEnabled = "mcpAutoRefreshEnabled"
    static let mcpRefreshMinutes = "mcpRefreshMinutes"
    static let slackNotificationChannels = "slackNotificationChannels"
    static let slackNotificationGroups = "slackNotificationGroups"
    static let slackIncludeGroupMentions = "slackIncludeGroupMentions"
    static let slackNotificationTopicLimit = "slackNotificationTopicLimit"
    static let settingsTab = "settingsTab"
}

extension UserDefaults {
    func registerTidyDefaults() {
        register(defaults: [
            AppDefaults.grammarHotkey: Hotkey.grammarDefault.displayValue,
            AppDefaults.clipboardHotkey: Hotkey.clipboardDefault.displayValue,
            AppDefaults.askAIHotkey: Hotkey.askAIDefault.displayValue,
            AppDefaults.grammarProvider: GrammarProviderID.gemini.rawValue,
            AppDefaults.clipboardMaxEntries: 200,
            AppDefaults.clipboardMaxAgeDays: 7,
            AppDefaults.didCompleteFirstRun: false,
            AppDefaults.autoSuggestEnabled: true,
            AppDefaults.openCodeModel: "deepseek-v4-flash-free",
            AppDefaults.deepSeekModel: "deepseek-v4-flash",
            AppDefaults.ollamaBaseURL: "http://localhost:11434",
            AppDefaults.ollamaModel: "gnokit/improve-grammar",
            AppDefaults.codexCLIPath: "codex",
            AppDefaults.codexCLIModel: "",
            AppDefaults.claudeCLIPath: "claude",
            AppDefaults.appearanceMode: "system",
            AppDefaults.jiraSiteURL: "",
            AppDefaults.jiraEmail: "",
            AppDefaults.jiraProjectKey: "",
            AppDefaults.jiraAssigneeAccountID: "",
            AppDefaults.dashboardSection: DashboardSection.home.rawValue,
            AppDefaults.jiraWorkspaceMode: "issues",
            AppDefaults.asanaWorkspaceGID: "",
            AppDefaults.asanaTokenExpiresAt: 0.0,
            AppDefaults.terminalWorkingDirectory: "",
            AppDefaults.sidebarCollapsed: false,
            AppDefaults.mcpServerURL: "",
            AppDefaults.mcpAPIKeyHeader: "x-api-key",
            AppDefaults.mcpAutoRefreshEnabled: false,
            AppDefaults.mcpRefreshMinutes: 15,
            AppDefaults.slackNotificationChannels: "",
            AppDefaults.slackNotificationGroups: "@channel, @here, @everyone",
            AppDefaults.slackIncludeGroupMentions: false,
            AppDefaults.slackNotificationTopicLimit: 10,
            AppDefaults.settingsTab: "General"
        ])
    }
}
