import Foundation
import Combine

@MainActor
final class DownloadCenter: ObservableObject {
    private enum Constants {
        static let maxAutoRetry = 3
        static let pollIntervalNs: UInt64 = 2_000_000_000
    }

    @Published private(set) var jobs: [DownloadJob] = []
    @Published var showResumePrompt = false

    private let service: MediaJobServicing
    private let store: DownloadJobStoring
    private let settingsStore: AppSettingsStore
    private let pathObserver: NetworkPathObserver
    private let maxConcurrent: Int

    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var retryWakeTask: Task<Void, Never>?

    init(
        service: MediaJobServicing,
        settingsStore: AppSettingsStore,
        pathObserver: NetworkPathObserver? = nil,
        store: DownloadJobStoring? = nil,
        maxConcurrent: Int = 2
    ) {
        self.service = service
        self.settingsStore = settingsStore
        self.pathObserver = pathObserver ?? NetworkPathObserver()
        self.store = store ?? UserDefaultsDownloadJobStore()
        self.maxConcurrent = maxConcurrent

        jobs = self.store.loadJobs().sorted { $0.createdAt > $1.createdAt }
        restoreInterruptedJobsIfNeeded()
        scheduleIfNeeded()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePowerModeChanged),
            name: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        retryWakeTask?.cancel()
    }

    var activeJobs: [DownloadJob] {
        jobs.filter { [.queued, .processing, .downloading, .paused].contains($0.state) }
    }

    var failedJobs: [DownloadJob] {
        jobs.filter { $0.state == .failed }
    }

    var completedJobs: [DownloadJob] {
        jobs.filter { $0.state == .completed }
    }

    var shouldPauseForPolicy: Bool {
        if settingsStore.pauseDownloadsOnLowPowerMode, ProcessInfo.processInfo.isLowPowerModeEnabled {
            return true
        }
        if !settingsStore.allowCellularDownloads, pathObserver.isCellular {
            return true
        }
        return false
    }

    func enqueue(jobID: String, sourceURL: String?, title: String) {
        if let existing = jobs.first(where: { $0.remoteJobID == jobID && $0.state != .canceled }) {
            if existing.state == .failed || existing.state == .paused {
                retry(jobID: existing.id)
            }
            return
        }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let job = DownloadJob(
            remoteJobID: jobID,
            sourceURL: sourceURL,
            title: normalizedTitle.isEmpty ? "job-\(jobID.prefix(8))" : normalizedTitle,
            state: .queued
        )
        jobs.insert(job, at: 0)
        persist()
        scheduleIfNeeded()
    }

    func pause(jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].state = .paused
        jobs[index].updatedAt = Date()
        activeTasks[jobID]?.cancel()
        activeTasks[jobID] = nil
        persist()
        scheduleIfNeeded()
    }

    func resume(jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].state = .queued
        jobs[index].errorMessage = nil
        jobs[index].backoffUntil = nil
        jobs[index].wasInterrupted = false
        jobs[index].updatedAt = Date()
        persist()
        scheduleIfNeeded()
    }

    func cancel(jobID: UUID, deleteFile: Bool) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        activeTasks[jobID]?.cancel()
        activeTasks[jobID] = nil

        if deleteFile, let localFilePath = jobs[index].localFilePath {
            try? FileManager.default.removeItem(atPath: localFilePath)
        }

        jobs[index].state = .canceled
        jobs[index].errorMessage = nil
        jobs[index].updatedAt = Date()
        persist()
        scheduleIfNeeded()
    }

    func retry(jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].state = .queued
        jobs[index].errorMessage = nil
        jobs[index].jobProgressPercent = 0
        jobs[index].downloadProgress = 0
        jobs[index].localFilePath = nil
        jobs[index].retryCount = 0
        jobs[index].backoffUntil = nil
        jobs[index].wasInterrupted = false
        jobs[index].updatedAt = Date()
        persist()
        scheduleIfNeeded()
    }

    func pauseAll() {
        for job in activeJobs where job.state != .paused {
            pause(jobID: job.id)
        }
    }

    func resumeAll() {
        for job in activeJobs where job.state == .paused {
            resume(jobID: job.id)
        }
    }

    func clearCompleted() {
        jobs.removeAll { $0.state == .completed }
        persist()
    }

    func resumeInterruptedJobs() {
        var changed = false
        for index in jobs.indices {
            if jobs[index].wasInterrupted, jobs[index].state == .paused {
                jobs[index].state = .queued
                jobs[index].wasInterrupted = false
                jobs[index].backoffUntil = nil
                jobs[index].updatedAt = Date()
                changed = true
            }
        }
        showResumePrompt = false
        if changed {
            persist()
            scheduleIfNeeded()
        }
    }

    func dismissResumePrompt() {
        showResumePrompt = false
    }

    private func scheduleIfNeeded() {
        guard !shouldPauseForPolicy else {
            return
        }

        let now = Date()
        let candidates = jobs.filter {
            $0.state == .queued && ($0.backoffUntil == nil || $0.backoffUntil! <= now)
        }

        let availableSlots = maxConcurrent - activeTasks.count
        guard availableSlots > 0 else {
            scheduleRetryWakeIfNeeded()
            return
        }

        for job in candidates.prefix(availableSlots) {
            start(jobID: job.id)
        }

        scheduleRetryWakeIfNeeded()
    }

    private func start(jobID: UUID) {
        guard activeTasks[jobID] == nil,
              let snapshot = jobs.first(where: { $0.id == jobID }),
              !shouldPauseForPolicy
        else {
            return
        }

        if let index = jobs.firstIndex(where: { $0.id == jobID }) {
            jobs[index].state = .processing
            jobs[index].updatedAt = Date()
            persist()
        }

        activeTasks[jobID] = Task { [weak self] in
            guard let self else { return }
            await self.run(jobSnapshot: snapshot)
        }
    }

    private func run(jobSnapshot: DownloadJob) async {
        defer {
            activeTasks[jobSnapshot.id] = nil
            scheduleIfNeeded()
        }

        do {
            while true {
                try Task.checkCancellation()
                if shouldPauseForPolicy {
                    await MainActor.run {
                        pause(jobID: jobSnapshot.id)
                    }
                    return
                }

                let status = try await service.getJobStatus(jobID: jobSnapshot.remoteJobID)

                await MainActor.run {
                    guard let idx = jobs.firstIndex(where: { $0.id == jobSnapshot.id }) else { return }
                    jobs[idx].jobProgressPercent = status.progress
                    jobs[idx].updatedAt = Date()
                    persist()
                }

                if status.status == .done { break }

                if status.status == .failed {
                    await MainActor.run {
                        if let idx = jobs.firstIndex(where: { $0.id == jobSnapshot.id }) {
                            jobs[idx].state = .failed
                            jobs[idx].errorMessage = status.error ?? "Remote processing failed"
                            jobs[idx].updatedAt = Date()
                            persist()
                        }
                    }
                    return
                }

                try await Task.sleep(nanoseconds: Constants.pollIntervalNs)
            }

            await MainActor.run {
                if let idx = jobs.firstIndex(where: { $0.id == jobSnapshot.id }) {
                    jobs[idx].state = .downloading
                    jobs[idx].downloadProgress = 0
                    jobs[idx].updatedAt = Date()
                    persist()
                }
            }

            let fileURL = try await service.downloadJobAsset(
                jobID: jobSnapshot.remoteJobID,
                preferredFileName: sanitizedTitleForFilename(jobSnapshot.title),
                onProgress: { [weak self] progress in
                    guard let self else { return }
                    Task { @MainActor in
                        guard let idx = self.jobs.firstIndex(where: { $0.id == jobSnapshot.id }) else { return }
                        self.jobs[idx].downloadProgress = progress
                        self.jobs[idx].updatedAt = Date()
                        self.persist()
                    }
                }
            )

            await MainActor.run {
                if let idx = jobs.firstIndex(where: { $0.id == jobSnapshot.id }) {
                    jobs[idx].state = .completed
                    jobs[idx].downloadProgress = 1
                    jobs[idx].localFilePath = fileURL.path
                    jobs[idx].errorMessage = nil
                    jobs[idx].backoffUntil = nil
                    jobs[idx].updatedAt = Date()
                    persist()
                }
            }
        } catch is CancellationError {
            // user action
        } catch {
            await MainActor.run {
                guard let idx = jobs.firstIndex(where: { $0.id == jobSnapshot.id }) else { return }
                if jobs[idx].state == .paused || jobs[idx].state == .canceled { return }

                if isTransient(error), jobs[idx].retryCount < Constants.maxAutoRetry {
                    let nextRetryCount = jobs[idx].retryCount + 1
                    let delay = pow(2.0, Double(nextRetryCount))
                    jobs[idx].retryCount = nextRetryCount
                    jobs[idx].state = .queued
                    jobs[idx].errorMessage = error.localizedDescription
                    jobs[idx].backoffUntil = Date().addingTimeInterval(delay)
                    jobs[idx].updatedAt = Date()
                    persist()
                    scheduleRetryWakeIfNeeded()
                    return
                }

                jobs[idx].state = .failed
                jobs[idx].errorMessage = error.localizedDescription
                jobs[idx].updatedAt = Date()
                persist()
            }
        }
    }

    private func scheduleRetryWakeIfNeeded() {
        retryWakeTask?.cancel()

        let now = Date()
        guard let earliest = jobs
            .filter({ $0.state == .queued && $0.backoffUntil != nil && $0.backoffUntil! > now })
            .compactMap(\.backoffUntil)
            .min()
        else {
            return
        }

        let delay = max(earliest.timeIntervalSinceNow, 0.2)
        retryWakeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                self?.scheduleIfNeeded()
            }
        }
    }

    private func restoreInterruptedJobsIfNeeded() {
        var hasInterrupted = false
        for index in jobs.indices {
            if jobs[index].state == .processing || jobs[index].state == .downloading {
                jobs[index].state = .paused
                jobs[index].wasInterrupted = true
                jobs[index].updatedAt = Date()
                hasInterrupted = true
            }
        }

        guard hasInterrupted else { return }

        if settingsStore.autoResumeDownloads && !shouldPauseForPolicy {
            for index in jobs.indices where jobs[index].wasInterrupted && jobs[index].state == .paused {
                jobs[index].state = .queued
                jobs[index].wasInterrupted = false
                jobs[index].backoffUntil = nil
            }
            showResumePrompt = false
        } else {
            showResumePrompt = true
        }
        persist()
    }

    private func sanitizedTitleForFilename(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "download" : String(trimmed.prefix(80))
        if URL(fileURLWithPath: base).pathExtension.isEmpty {
            return "\(base).mp3"
        }
        return base
    }

    private func isTransient(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                 .notConnectedToInternet, .dnsLookupFailed, .internationalRoamingOff:
                return true
            default:
                break
            }
        }

        if let apiError = error as? APIClientError {
            if case let .requestFailed(statusCode) = apiError {
                return statusCode >= 500
            }
            if case let .server(_, _, statusCode) = apiError {
                return statusCode >= 500
            }
        }

        return false
    }

    @objc
    private func handlePowerModeChanged() {
        if shouldPauseForPolicy {
            pauseAll()
        } else {
            scheduleIfNeeded()
        }
    }

    private func persist() {
        store.saveJobs(jobs)
    }
}
