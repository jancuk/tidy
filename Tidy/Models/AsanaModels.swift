import Foundation

struct AsanaWorkspace: Decodable, Identifiable, Equatable {
    let gid: String
    let name: String

    var id: String { gid }
}

struct AsanaUser: Decodable, Identifiable, Equatable {
    let gid: String
    let name: String
    let email: String?

    var id: String { gid }
}

struct AsanaNamedResource: Decodable, Identifiable, Equatable {
    let gid: String
    let name: String

    var id: String { gid }
}

struct AsanaMembership: Decodable, Equatable {
    let project: AsanaNamedResource?
    let section: AsanaNamedResource?
}

struct AsanaTask: Decodable, Identifiable, Equatable {
    let gid: String
    let name: String
    let completed: Bool
    let dueOn: String?
    let dueAt: String?
    let permalinkURL: String?
    let notes: String?
    let assignee: AsanaUser?
    let projects: [AsanaNamedResource]
    let memberships: [AsanaMembership]

    enum CodingKeys: String, CodingKey {
        case gid
        case name
        case completed
        case dueOn = "due_on"
        case dueAt = "due_at"
        case permalinkURL = "permalink_url"
        case notes
        case assignee
        case projects
        case memberships
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gid = try container.decode(String.self, forKey: .gid)
        name = try container.decode(String.self, forKey: .name)
        completed = try container.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        dueOn = try container.decodeIfPresent(String.self, forKey: .dueOn)
        dueAt = try container.decodeIfPresent(String.self, forKey: .dueAt)
        permalinkURL = try container.decodeIfPresent(String.self, forKey: .permalinkURL)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        assignee = try container.decodeIfPresent(AsanaUser.self, forKey: .assignee)
        projects = try container.decodeIfPresent(
            [AsanaNamedResource].self,
            forKey: .projects
        ) ?? []
        memberships = try container.decodeIfPresent(
            [AsanaMembership].self,
            forKey: .memberships
        ) ?? []
    }

    var id: String { gid }

    var dueDate: Date? {
        if let dueAt {
            return ISO8601DateFormatter().date(from: dueAt)
        }
        guard let dueOn else { return nil }
        return AsanaDateParser.day.date(from: dueOn)
    }

    var projectNames: [String] {
        let direct = projects.map(\.name)
        let membershipProjects = memberships.compactMap(\.project?.name)
        return Array(Set(direct + membershipProjects)).sorted()
    }

    var sectionNames: [String] {
        Array(Set(memberships.compactMap(\.section?.name))).sorted()
    }
}

enum AsanaTaskFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case overdue = "Overdue"
    case today = "Today"
    case upcoming = "Upcoming"
    case noDueDate = "No due date"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all: "list.bullet"
        case .overdue: "exclamationmark.circle.fill"
        case .today: "calendar"
        case .upcoming: "calendar.badge.clock"
        case .noDueDate: "calendar.badge.minus"
        }
    }

    func includes(_ task: AsanaTask, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let dueDate = task.dueDate else {
            return self == .all || self == .noDueDate
        }

        switch self {
        case .all:
            return true
        case .overdue:
            return dueDate < calendar.startOfDay(for: now)
        case .today:
            return calendar.isDate(dueDate, inSameDayAs: now)
        case .upcoming:
            return dueDate >= calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        case .noDueDate:
            return false
        }
    }
}

enum AsanaDateParser {
    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct AsanaConfiguration {
    static let clientIDKey = "asana.clientID"
    static let clientSecretKey = "asana.clientSecret"
    static let accessTokenKey = "asana.accessToken"
    static let refreshTokenKey = "asana.refreshToken"
    static let legacyTokenKey = "asana.personalAccessToken"

    let clientID: String
    let clientSecret: String
    let accessToken: String
    let refreshToken: String
    let workspaceGID: String

    var hasAppCredentials: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isAuthorized: Bool {
        !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isComplete: Bool {
        hasAppCredentials
            && isAuthorized
            && !workspaceGID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static var current: AsanaConfiguration {
        AsanaConfiguration(
            clientID: KeychainStore.read(key: clientIDKey) ?? "",
            clientSecret: KeychainStore.read(key: clientSecretKey) ?? "",
            accessToken: KeychainStore.read(key: accessTokenKey) ?? "",
            refreshToken: KeychainStore.read(key: refreshTokenKey) ?? "",
            workspaceGID: UserDefaults.standard.string(forKey: AppDefaults.asanaWorkspaceGID) ?? ""
        )
    }
}

struct AsanaOAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval
    let user: AsanaUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user = "data"
    }
}

struct AsanaOAuthErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

struct AsanaResponse<Value: Decodable>: Decodable {
    let data: Value
    let nextPage: AsanaNextPage?

    enum CodingKeys: String, CodingKey {
        case data
        case nextPage = "next_page"
    }
}

struct AsanaNextPage: Decodable {
    let offset: String?
}

struct AsanaErrorEnvelope: Decodable {
    struct Item: Decodable {
        let message: String
    }

    let errors: [Item]
}
