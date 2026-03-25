import Foundation

enum MediaJobEndpoints {
    static func createJob(body: Data) -> APIEndpoint {
        APIEndpoint(
            path: APIPathConstants.jobs,
            method: .post,
            body: body
        )
    }
}
