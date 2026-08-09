import Foundation

enum ConnectorCapability: String, CaseIterable, Codable, Sendable {
    case readMessages
    case readMail
    case readCalendar
    case readIssues
    case writeIssueComments
    case readTasks
    case updateTasks
    case readServiceHealth
}

enum ConnectorDataRetention: String, Codable, Sendable {
    case memoryOnly
    case summaryCache
}

struct ConnectorPrivacyDisclosure: Equatable, Codable, Sendable {
    let dataRead: String
    let dataSentToAI: String?
    let retention: ConnectorDataRetention
}

struct TidyConnectorDescriptor: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let title: String
    let systemImage: String
    let capabilities: Set<ConnectorCapability>
    let isReadOnlyByDefault: Bool
    let privacy: ConnectorPrivacyDisclosure
}

protocol TidyConnector: Sendable {
    var descriptor: TidyConnectorDescriptor { get }
}

struct MCPSourceConnector: TidyConnector, Equatable, Sendable {
    let source: MCPIntegrationSource

    var descriptor: TidyConnectorDescriptor {
        source.connectorDescriptor
    }
}
enum ConnectorRegistry {
    static let notificationConnectors: [MCPSourceConnector] = [
        MCPSourceConnector(source: .slack),
        MCPSourceConnector(source: .gmail),
        MCPSourceConnector(source: .googleCalendar)
    ]

    static let builtInDescriptors: [TidyConnectorDescriptor] = [
        TidyConnectorDescriptor(
            id: "jira-native",
            title: "Jira",
            systemImage: "shippingbox.fill",
            capabilities: [.readIssues, .writeIssueComments],
            isReadOnlyByDefault: false,
            privacy: ConnectorPrivacyDisclosure(
                dataRead: "Issues, comments, transitions, and sprint metadata",
                dataSentToAI: nil,
                retention: .memoryOnly
            )
        ),
        TidyConnectorDescriptor(
            id: "asana-native",
            title: "Asana",
            systemImage: "checklist.checked",
            capabilities: [.readTasks, .updateTasks],
            isReadOnlyByDefault: false,
            privacy: ConnectorPrivacyDisclosure(
                dataRead: "Assigned tasks, projects, sections, and due dates",
                dataSentToAI: nil,
                retention: .memoryOnly
            )
        )
    ] + notificationConnectors.map(\.descriptor)
}

extension MCPIntegrationSource {
    var connectorDescriptor: TidyConnectorDescriptor {
        TidyConnectorDescriptor(
            id: "mcp-\(rawValue)",
            title: title,
            systemImage: notificationSystemImage,
            capabilities: connectorCapabilities,
            isReadOnlyByDefault: true,
            privacy: ConnectorPrivacyDisclosure(
                dataRead: connectorDataRead,
                dataSentToAI: "A bounded portion is summarized by the selected provider unless local-only AI is enabled.",
                retention: .summaryCache
            )
        )
    }

    private var connectorCapabilities: Set<ConnectorCapability> {
        switch self {
        case .slack: [.readMessages]
        case .gmail: [.readMail]
        case .googleCalendar: [.readCalendar]
        case .newRelic: [.readServiceHealth]
        case .jira: [.readIssues]
        }
    }

    private var connectorDataRead: String {
        switch self {
        case .slack: "Messages matching configured mention searches"
        case .gmail: "Unread message metadata and content returned by the MCP tool"
        case .googleCalendar: "Upcoming calendar events returned by the MCP tool"
        case .newRelic: "Service health and incident data returned by the MCP tool"
        case .jira: "Issue data returned by the MCP tool"
        }
    }
}
