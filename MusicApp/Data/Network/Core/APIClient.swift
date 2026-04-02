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
    case fileSaveFailedUnderlying(String)

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
        case let .fileSaveFailedUnderlying(message):
            return "Failed to save downloaded file: \(message)"
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

        onProgress?(0)

        let delegate = DownloadTaskDelegate(onProgress: onProgress)
        let downloadSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = downloadSession.downloadTask(with: request)
        defer { downloadSession.finishTasksAndInvalidate() }

        let (tempURL, response): (URL, URLResponse)
        do {
            (tempURL, response) = try await withTaskCancellationHandler {
                try await delegate.result(for: task)
            } onCancel: {
                task.cancel()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIClientError.fileSaveFailedUnderlying(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let data = try? Data(contentsOf: tempURL),
               let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw APIClientError.server(
                    code: apiError.code,
                    message: apiError.message,
                    statusCode: httpResponse.statusCode
                )
            }
            throw APIClientError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let filename = sanitizedFileName(
            preferredFileName
            ?? extractFilename(from: httpResponse)
            ?? "job-download-\(UUID().uuidString).bin"
        )
        let destinationFolder = try makeDownloadDirectoryIfNeeded()
        let destinationURL = destinationFolder.appendingPathComponent(filename)

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            onProgress?(1)
            return destinationURL
        } catch {
            throw APIClientError.fileSaveFailedUnderlying(error.localizedDescription)
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

    private func sanitizedFileName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = String(name.unicodeScalars.map { forbidden.contains($0) ? "_" : Character($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? "job-download-\(UUID().uuidString).bin" : cleaned
    }

}

private final class DownloadTaskDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: (@Sendable (Double) -> Void)?
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var tempFileURL: URL?
    private var persistedTempError: Error?
    private var finished = false

    init(onProgress: (@Sendable (Double) -> Void)?) {
        self.onProgress = onProgress
    }

    func result(for task: URLSessionDownloadTask) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0), 1)
        onProgress?(progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let persistedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("download-\(UUID().uuidString).tmp")

        do {
            if FileManager.default.fileExists(atPath: persistedURL.path) {
                try FileManager.default.removeItem(at: persistedURL)
            }
            try FileManager.default.moveItem(at: location, to: persistedURL)
            tempFileURL = persistedURL
            persistedTempError = nil
        } catch {
            tempFileURL = nil
            persistedTempError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        finished = true

        if let error {
            if (error as NSError).code == NSURLErrorCancelled {
                continuation?.resume(throwing: CancellationError())
            } else {
                continuation?.resume(throwing: error)
            }
            continuation = nil
            return
        }

        guard let tempFileURL, let response = task.response else {
            if let persistedTempError {
                continuation?.resume(throwing: persistedTempError)
            } else {
                continuation?.resume(throwing: APIClientError.invalidResponse)
            }
            continuation = nil
            return
        }

        continuation?.resume(returning: (tempFileURL, response))
        continuation = nil
    }
}
