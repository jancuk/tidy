import Foundation

enum TidyGoal: String, CaseIterable, Identifiable, Codable {
    case writing
    case clipboard
    case cleanup
    case dailyWork
    case developerDesk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .writing: "Improve writing"
        case .clipboard: "Manage clipboard"
        case .cleanup: "Clean files safely"
        case .dailyWork: "Organize daily work"
        case .developerDesk: "Use developer tools"
        }
    }

    var detail: String {
        switch self {
        case .writing: "Grammar fixes, suggestions, and Ask AI"
        case .clipboard: "Searchable history and quick paste"
        case .cleanup: "Preview-first cleanup with undo"
        case .dailyWork: "Briefings, Jira, Asana, and workflows"
        case .developerDesk: "Terminal, JSON, JWT, diff, and converters"
        }
    }

    var systemImage: String {
        switch self {
        case .writing: "textformat"
        case .clipboard: "doc.on.clipboard"
        case .cleanup: "folder.badge.gearshape"
        case .dailyWork: "sun.max"
        case .developerDesk: "hammer"
        }
    }

    var dashboardSections: Set<DashboardSection> {
        switch self {
        case .writing:
            [.correctionLog, .aiRequestLog]
        case .clipboard:
            [.clipboard]
        case .cleanup:
            [.fileTidy]
        case .dailyWork:
            [.workflows, .data, .notifications, .jira, .asana]
        case .developerDesk:
            [.data, .terminal, .developerTools, .aiRequestLog]
        }
    }

    static func decode(_ rawValue: String) -> Set<TidyGoal> {
        Set(
            rawValue
                .split(separator: ",")
                .compactMap { TidyGoal(rawValue: String($0)) }
        )
    }

    static func encode(_ goals: Set<TidyGoal>) -> String {
        goals.map(\.rawValue).sorted().joined(separator: ",")
    }
}

enum DeveloperWorkflowID: String, CaseIterable, Identifiable {
    case startDay
    case meetingPrep
    case cleanProject
    case shareContext
    case wrapUp

    var id: String { rawValue }
}

struct DeveloperWorkflowDefinition: Identifiable, Equatable {
    let id: DeveloperWorkflowID
    let title: String
    let detail: String
    let systemImage: String
    let actionTitle: String
    let requiredSections: Set<DashboardSection>
}

enum DeveloperWorkflowRegistry {
    static let all: [DeveloperWorkflowDefinition] = [
        DeveloperWorkflowDefinition(
            id: .startDay,
            title: "Start My Day",
            detail: "Build a briefing from Slack, Gmail, and Calendar, then focus on the actions that need attention.",
            systemImage: "sun.max.fill",
            actionTitle: "Build briefing",
            requiredSections: [.notifications]
        ),
        DeveloperWorkflowDefinition(
            id: .meetingPrep,
            title: "Prepare for Meeting",
            detail: "Refresh communication and calendar context before the next meeting.",
            systemImage: "person.2.wave.2.fill",
            actionTitle: "Prepare context",
            requiredSections: [.notifications]
        ),
        DeveloperWorkflowDefinition(
            id: .cleanProject,
            title: "Clean This Project",
            detail: "Inspect generated files, stale artifacts, duplicates, and safe moves with a complete preview.",
            systemImage: "folder.badge.gearshape",
            actionTitle: "Choose project",
            requiredSections: [.fileTidy]
        ),
        DeveloperWorkflowDefinition(
            id: .shareContext,
            title: "Share Context",
            detail: "Open Ask AI to turn selected notes, code, or project context into a concise update.",
            systemImage: "square.and.arrow.up",
            actionTitle: "Open Ask AI",
            requiredSections: []
        ),
        DeveloperWorkflowDefinition(
            id: .wrapUp,
            title: "Wrap Up My Day",
            detail: "Open the Jira stand-up workspace to capture progress, blockers, and next steps.",
            systemImage: "moon.stars.fill",
            actionTitle: "Draft update",
            requiredSections: [.jira]
        )
    ]
}
