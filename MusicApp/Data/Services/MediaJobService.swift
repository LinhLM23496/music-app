import Foundation

enum MediaSourceType: String, Codable {
    case youtube
    case tiktok
    case facebook
}

protocol MediaJobServicing {
    func createJob(sourceType: MediaSourceType, sourceURL: String) async throws -> String
}

struct LiveMediaJobService: MediaJobServicing {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func createJob(sourceType: MediaSourceType, sourceURL: String) async throws -> String {
        let payload = CreateMediaJobRequest(
            sourceType: sourceType,
            sourceUrl: sourceURL,
            output: "mp3",
            mode: "store",
            videoKeep: false
        )

        let endpoint = MediaJobEndpoints.createJob(body: try JSONEncoder().encode(payload))

        let response = try await apiClient.send(endpoint, as: CreateMediaJobResponse.self)
        return response.jobID
    }
}

private struct CreateMediaJobRequest: Encodable {
    let sourceType: MediaSourceType
    let sourceUrl: String
    let output: String
    let mode: String
    let videoKeep: Bool
}

private struct CreateMediaJobResponse: Decodable {
    let jobID: String

    private enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
    }
}
