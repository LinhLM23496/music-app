import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

enum APIEndpointError: Error {
    case invalidURL
}

struct APIEndpoint {
    private enum DefaultHeader {
        static let contentType = "Content-Type"
        static let json = "application/json"
    }

    let path: String
    let method: HTTPMethod
    var queryItems: [URLQueryItem] = []
    var headers: [String: String] = [:]
    var body: Data? = nil

    func makeURLRequest(baseURL: URL, timeout: TimeInterval) throws -> URLRequest {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var components = URLComponents(url: baseURL.appendingPathComponent(normalizedPath), resolvingAgainstBaseURL: false)

        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw APIEndpointError.invalidURL
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        request.httpBody = body

        if body != nil, headers[DefaultHeader.contentType] == nil {
            request.setValue(DefaultHeader.json, forHTTPHeaderField: DefaultHeader.contentType)
        }

        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        return request
    }
}
