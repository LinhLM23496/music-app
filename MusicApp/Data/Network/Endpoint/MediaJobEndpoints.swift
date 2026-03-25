import Foundation

enum MediaJobEndpoints {
    static func createJob(body: Data) -> APIEndpoint {
        APIEndpoint(
            path: APIPathConstants.jobs,
            method: .post,
            body: body
        )
    }

    static func getJobStatus(jobID: String) -> APIEndpoint {
        APIEndpoint(
            path: APIPathConstants.jobStatus(id: jobID),
            method: .get
        )
    }

    static func getJobResult(jobID: String) -> APIEndpoint {
        APIEndpoint(
            path: APIPathConstants.jobResult(id: jobID),
            method: .get
        )
    }

    static func getJobDownload(jobID: String) -> APIEndpoint {
        APIEndpoint(
            path: APIPathConstants.jobDownload(id: jobID),
            method: .get
        )
    }
}
