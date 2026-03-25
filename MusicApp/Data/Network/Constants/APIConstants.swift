import Foundation

enum APIConstants {
    static let baseURLString = "https://kristian-inexistent-marquetta.ngrok-free.dev"
    static let requestTimeout: TimeInterval = 30

    static var baseURL: URL {
        guard let url = URL(string: baseURLString) else {
            fatalError("Invalid API base URL configuration")
        }
        return url
    }
}
