import Foundation

struct AIRequestLogEntry: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    let providerName: String
    let requestPreview: String
    let statusCode: Int?
    let errorMessage: String?
    let durationMs: Int
    let source: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        providerName: String,
        requestPreview: String,
        statusCode: Int? = nil,
        errorMessage: String? = nil,
        durationMs: Int,
        source: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.providerName = providerName
        self.requestPreview = requestPreview
        self.statusCode = statusCode
        self.errorMessage = errorMessage
        self.durationMs = durationMs
        self.source = source
    }
}
