import Foundation

enum DownloadJobState: String, Codable, CaseIterable {
    case queued
    case processing
    case downloading
    case paused
    case completed
    case failed
    case canceled

    var isTerminal: Bool {
        self == .completed || self == .failed || self == .canceled
    }

    var isActive: Bool {
        self == .processing || self == .downloading
    }
}

struct DownloadJob: Identifiable, Codable, Hashable {
    let id: UUID
    let remoteJobID: String
    var sourceURL: String?
    var title: String
    var state: DownloadJobState

    var jobProgressPercent: Int
    var downloadProgress: Double

    var localFilePath: String?
    var errorMessage: String?
    var retryCount: Int
    var backoffUntil: Date?

    var wasInterrupted: Bool

    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        remoteJobID: String,
        sourceURL: String?,
        title: String,
        state: DownloadJobState = .queued,
        jobProgressPercent: Int = 0,
        downloadProgress: Double = 0,
        localFilePath: String? = nil,
        errorMessage: String? = nil,
        retryCount: Int = 0,
        backoffUntil: Date? = nil,
        wasInterrupted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.remoteJobID = remoteJobID
        self.sourceURL = sourceURL
        self.title = title
        self.state = state
        self.jobProgressPercent = min(max(jobProgressPercent, 0), 100)
        self.downloadProgress = min(max(downloadProgress, 0), 1)
        self.localFilePath = localFilePath
        self.errorMessage = errorMessage
        self.retryCount = retryCount
        self.backoffUntil = backoffUntil
        self.wasInterrupted = wasInterrupted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
