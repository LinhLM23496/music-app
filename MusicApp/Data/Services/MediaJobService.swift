import Foundation

enum MediaSourceType: String, Codable {
    case youtube
    case tiktok
    case facebook
}

enum JobExecutionStatus: String, Codable {
    case queued
    case processing
    case done
    case failed

    var isProcessing: Bool {
        self == .processing
    }
}

struct MediaJobStatus: Decodable {
    let id: String
    let status: JobExecutionStatus
    let progress: Int
    let error: String?
    let createdAt: String
    let updatedAt: String
}

struct MediaJobResult: Decodable {
    struct SourceMeta: Decodable {
        let title: String?
        let durationMs: Int?
        let thumbnail: String?
    }

    struct Asset: Decodable, Identifiable {
        let id: String
        let jobId: String?
        let kind: String?
        let format: String?
        let size: Int?
        let storagePath: String?
        let publicUrl: String?
        let createdAt: String?
    }

    let sourceMeta: SourceMeta?
    let assets: [Asset]
}

protocol MediaJobServicing {
    func createJob(sourceType: MediaSourceType, sourceURL: String, useCookie: Bool) async throws -> String
    func getJobStatus(jobID: String) async throws -> MediaJobStatus
    func getJobResult(jobID: String) async throws -> MediaJobResult
    func downloadJobAsset(jobID: String, onProgress: (@Sendable (Double) -> Void)?) async throws -> URL
}

struct LiveMediaJobService: MediaJobServicing {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func createJob(sourceType: MediaSourceType, sourceURL: String, useCookie: Bool) async throws -> String {
        let payload = CreateMediaJobRequest(
            sourceType: sourceType,
            sourceUrl: sourceURL,
            output: "mp3",
            mode: "store",
            videoKeep: false,
            useCookie: useCookie
        )

        let endpoint = MediaJobEndpoints.createJob(body: try JSONEncoder().encode(payload))

        let response = try await apiClient.send(endpoint, as: CreateMediaJobResponse.self)
        return response.jobID
    }

    func getJobStatus(jobID: String) async throws -> MediaJobStatus {
        let endpoint = MediaJobEndpoints.getJobStatus(jobID: jobID)
        return try await apiClient.send(endpoint, as: MediaJobStatus.self)
    }

    func getJobResult(jobID: String) async throws -> MediaJobResult {
        let endpoint = MediaJobEndpoints.getJobResult(jobID: jobID)
        return try await apiClient.send(endpoint, as: MediaJobResult.self)
    }

    func downloadJobAsset(jobID: String, onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        let endpoint = MediaJobEndpoints.getJobDownload(jobID: jobID)
        return try await apiClient.downloadFile(
            endpoint,
            preferredFileName: nil,
            onProgress: onProgress
        )
    }
}

private struct CreateMediaJobRequest: Encodable {
    let sourceType: MediaSourceType
    let sourceUrl: String
    let output: String
    let mode: String
    let videoKeep: Bool
    let useCookie: Bool
}

private struct CreateMediaJobResponse: Decodable {
    let jobID: String

    private enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
    }
}
