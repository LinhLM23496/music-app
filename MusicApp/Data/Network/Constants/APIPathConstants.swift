import Foundation

enum APIPathConstants {
    static let jobs = "v1/jobs"

    static func jobStatus(id: String) -> String {
        "\(jobs)/\(id)"
    }

    static func jobResult(id: String) -> String {
        "\(jobs)/\(id)/result"
    }

    static func jobDownload(id: String) -> String {
        "\(jobs)/\(id)/download"
    }
}
