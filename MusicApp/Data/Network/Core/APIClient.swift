import Foundation

struct APIErrorResponse: Decodable {
    let code: String
    let message: String
}

enum APIClientError: LocalizedError {
    case invalidResponse
    case invalidURL
    case server(code: String, message: String, statusCode: Int)
    case requestFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case .invalidURL:
            return "Invalid URL."
        case let .server(code, message, _):
            return "\(code): \(message)"
        case let .requestFailed(statusCode):
            return "Request failed with status \(statusCode)."
        }
    }
}

protocol APIClient {
    func send<T: Decodable>(_ endpoint: APIEndpoint, as type: T.Type) async throws -> T
}

struct URLSessionAPIClient: APIClient {
    private let baseURL: URL
    private let timeout: TimeInterval
    private let session: URLSession

    init(
        baseURL: URL,
        timeout: TimeInterval = APIConstants.requestTimeout,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.session = session
    }

    func send<T: Decodable>(_ endpoint: APIEndpoint, as type: T.Type) async throws -> T {
        let request: URLRequest

        do {
            request = try endpoint.makeURLRequest(baseURL: baseURL, timeout: timeout)
        } catch {
            throw APIClientError.invalidURL
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw APIClientError.server(
                    code: apiError.code,
                    message: apiError.message,
                    statusCode: httpResponse.statusCode
                )
            }

            throw APIClientError.requestFailed(statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIClientError.invalidResponse
        }
    }
}
