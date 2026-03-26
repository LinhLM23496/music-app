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
    case fileSaveFailed

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
        case .fileSaveFailed:
            return "Failed to save downloaded file."
        }
    }
}

protocol APIClient {
    func send<T: Decodable>(_ endpoint: APIEndpoint, as type: T.Type) async throws -> T
    func downloadFile(
        _ endpoint: APIEndpoint,
        preferredFileName: String?,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> URL
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

    func downloadFile(
        _ endpoint: APIEndpoint,
        preferredFileName: String? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let request: URLRequest

        do {
            request = try endpoint.makeURLRequest(baseURL: baseURL, timeout: timeout)
        } catch {
            throw APIClientError.invalidURL
        }

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let data = try? await collectData(from: bytes),
               let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw APIClientError.server(
                    code: apiError.code,
                    message: apiError.message,
                    statusCode: httpResponse.statusCode
                )
            }

            throw APIClientError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let filename = preferredFileName
            ?? extractFilename(from: httpResponse)
            ?? "job-download-\(UUID().uuidString).bin"

        let destinationFolder = try makeDownloadDirectoryIfNeeded()
        let destinationURL = destinationFolder.appendingPathComponent(filename)
        let expectedBytes = max(httpResponse.expectedContentLength, 0)
        var downloadedBytes: Int64 = 0

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
            let fileHandle = try FileHandle(forWritingTo: destinationURL)
            defer {
                try? fileHandle.close()
            }

            onProgress?(0)

            var buffer = Data()
            buffer.reserveCapacity(64 * 1024)

            for try await byte in bytes {
                buffer.append(byte)
                downloadedBytes += 1

                if buffer.count >= 64 * 1024 {
                    try fileHandle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }

                if expectedBytes > 0 {
                    let progress = min(max(Double(downloadedBytes) / Double(expectedBytes), 0), 1)
                    onProgress?(progress)
                }
            }

            if !buffer.isEmpty {
                try fileHandle.write(contentsOf: buffer)
            }

            onProgress?(1)
            return destinationURL
        } catch {
            throw APIClientError.fileSaveFailed
        }
    }

    private func makeDownloadDirectoryIfNeeded() throws -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let directory = (documentsURL ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Downloads", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }

    private func extractFilename(from response: HTTPURLResponse) -> String? {
        guard let contentDisposition = response.value(forHTTPHeaderField: "Content-Disposition") else {
            return nil
        }

        for part in contentDisposition.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("filename=") {
                let name = String(trimmed.dropFirst("filename=".count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                return name.isEmpty ? nil : name
            }
        }

        return nil
    }

    private func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }
}
