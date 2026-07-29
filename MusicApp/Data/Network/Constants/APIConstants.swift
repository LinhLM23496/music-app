import Foundation

enum APIConstants {
    static let baseURLString = "https://media-service-api.lmlgroup.io.vn"
    static let requestTimeout: TimeInterval = 30

    static var baseURL: URL {
        guard let url = URL(string: baseURLString) else {
            fatalError("Invalid API base URL configuration")
        }
        return url
    }
}
