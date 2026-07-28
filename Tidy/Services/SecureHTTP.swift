import Foundation

enum SecureHTTPError: LocalizedError, Equatable {
    case invalidRequestURL
    case responseTooLarge(limit: Int)

    var errorDescription: String? {
        switch self {
        case .invalidRequestURL:
            "The request URL is invalid."
        case .responseTooLarge(let limit):
            "The server response exceeded the \(limit / 1_048_576) MB safety limit."
        }
    }
}

private final class SameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let origin: URL

    init(origin: URL) {
        self.origin = origin
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let destination = request.url,
              SecureHTTP.isSameOrigin(origin, destination) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

enum SecureHTTP {
    static let defaultMaximumResponseBytes = 8 * 1_048_576

    static func data(
        for request: URLRequest,
        session: URLSession = .shared,
        maximumResponseBytes: Int = defaultMaximumResponseBytes
    ) async throws -> (Data, URLResponse) {
        guard let origin = request.url else {
            throw SecureHTTPError.invalidRequestURL
        }

        let delegate = SameOriginRedirectDelegate(origin: origin)
        let (data, response) = try await session.data(for: request, delegate: delegate)
        guard data.count <= maximumResponseBytes else {
            throw SecureHTTPError.responseTooLarge(limit: maximumResponseBytes)
        }
        return (data, response)
    }

    static func isSameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let leftScheme = lhs.scheme?.lowercased(),
              let rightScheme = rhs.scheme?.lowercased(),
              let leftHost = lhs.host?.lowercased(),
              let rightHost = rhs.host?.lowercased() else {
            return false
        }
        return leftScheme == rightScheme
            && leftHost == rightHost
            && effectivePort(for: lhs) == effectivePort(for: rhs)
    }

    static func isSafeWebURL(_ url: URL, allowedHosts: Set<String>? = nil) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(),
              !host.isEmpty,
              url.user == nil,
              url.password == nil else {
            return false
        }
        guard let allowedHosts else { return true }
        return allowedHosts.map { $0.lowercased() }.contains(host)
    }

    private static func effectivePort(for url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}
