import SwiftUI

struct DownloadListView: View {
    @EnvironmentObject private var localizationViewModel: LocalizationViewModel
    @EnvironmentObject private var downloadCenter: DownloadCenter
    @EnvironmentObject private var importViewModel: ImportViewModel

    @State private var selectedJob: DownloadJob?
    @State private var pendingCancelJob: DownloadJob?
    @State private var pendingRequeueJob: DownloadJob?
    @State private var requeueTitleDraft: String = ""
    @State private var importToastMessage: String?
    @State private var importToastWorkItem: DispatchWorkItem?

    private var inProgressJobs: [DownloadJob] {
        downloadCenter.jobs.filter {
            $0.state == .queued || $0.state == .processing || $0.state == .ready || $0.state == .downloading || $0.state == .paused
        }
    }

    private var failedJobs: [DownloadJob] {
        downloadCenter.jobs.filter { $0.state == .failed }
    }

    private var completedJobs: [DownloadJob] {
        downloadCenter.jobs.filter { $0.state == .completed }
    }

    var body: some View {
        List {
            if !inProgressJobs.isEmpty {
                section(title: localizationViewModel.t("downloads.section.active"), jobs: inProgressJobs)
            }

            if !failedJobs.isEmpty {
                section(title: localizationViewModel.t("downloads.section.failed"), jobs: failedJobs)
            }

            if !completedJobs.isEmpty {
                section(title: localizationViewModel.t("downloads.section.completed"), jobs: completedJobs)
            }

            if inProgressJobs.isEmpty && failedJobs.isEmpty && completedJobs.isEmpty {
                Text(localizationViewModel.t("downloads.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(localizationViewModel.t("downloads.title"))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button(localizationViewModel.t("downloads.action.pause.all")) { downloadCenter.pauseAll() }
                    Button(localizationViewModel.t("downloads.action.resume.all")) { downloadCenter.resumeAll() }
                    Button(localizationViewModel.t("downloads.clear.completed")) { downloadCenter.clearCompleted() }
                    Button("Thử lại lỗi") { downloadCenter.retryFailed() }
                    Button("Xóa lỗi", role: .destructive) { downloadCenter.clearFailed() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert(
            localizationViewModel.t("downloads.cancel.confirm.title"),
            isPresented: Binding(
                get: { pendingCancelJob != nil },
                set: { if !$0 { pendingCancelJob = nil } }
            ),
            presenting: pendingCancelJob
        ) { job in
            Button(localizationViewModel.t("downloads.cancel.confirm.button"), role: .destructive) {
                downloadCenter.cancel(jobID: job.id, deleteFile: false)
                pendingCancelJob = nil
            }
            Button(localizationViewModel.t("playlist.cancel"), role: .cancel) {
                pendingCancelJob = nil
            }
        } message: { _ in
            Text(localizationViewModel.t("downloads.cancel.confirm.message"))
        }
        .alert(
            "Thêm vào hàng đợi",
            isPresented: Binding(
                get: { pendingRequeueJob != nil },
                set: { if !$0 { pendingRequeueJob = nil } }
            )
        ) {
            TextField("Tên file", text: $requeueTitleDraft)
            Button(localizationViewModel.t("playlist.cancel"), role: .cancel) {
                pendingRequeueJob = nil
            }
            Button("Thêm") {
                guard let job = pendingRequeueJob else { return }
                let title = requeueTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                downloadCenter.queueReadyJobForDownload(
                    jobID: job.id,
                    title: title.isEmpty ? job.title : title
                )
                pendingRequeueJob = nil
            }
        } message: {
            Text("Bạn có thể sửa tên trước khi thêm lại hàng đợi tải.")
        }
        .sheet(item: $selectedJob) { job in
            DownloadJobDetailSheet(job: job)
                .environmentObject(localizationViewModel)
                .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .top) {
            if let importToastMessage {
                AppToastView(message: importToastMessage)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: importToastMessage != nil)
    }

    @ViewBuilder
    private func section(title: String, jobs: [DownloadJob]) -> some View {
        Section(title) {
            ForEach(jobs) { job in
                DownloadJobRow(
                    job: job,
                    onPauseResume: {
                        if job.state == .paused {
                            downloadCenter.resume(jobID: job.id)
                        } else if job.state == .downloading || job.state == .processing {
                            downloadCenter.pause(jobID: job.id)
                        } else {
                            downloadCenter.retry(jobID: job.id)
                        }
                    },
                    onCancel: {
                        pendingCancelJob = job
                    },
                    onRetry: {
                        downloadCenter.retry(jobID: job.id)
                    },
                    onRequeue: {
                        pendingRequeueJob = job
                        requeueTitleDraft = job.title
                    },
                    onImport: {
                        guard let localFilePath = job.localFilePath else { return }
                        let fileURL = URL(fileURLWithPath: localFilePath)
                        importViewModel.importAudioFiles(from: [fileURL]) { result in
                            guard result.importedCount > 0 else { return }
                            showImportToast("Đã import vào thư viện")
                        }
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture { selectedJob = job }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    private func showImportToast(_ message: String) {
        importToastWorkItem?.cancel()
        importToastMessage = message

        let workItem = DispatchWorkItem {
            importToastMessage = nil
        }
        importToastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }
}

private struct DownloadJobRow: View {
    let job: DownloadJob
    let onPauseResume: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRequeue: () -> Void
    let onImport: () -> Void

    private var progress: Double {
        switch job.state {
        case .queued:
            return 0
        case .processing, .ready:
            return Double(job.jobProgressPercent) / 100
        case .downloading, .completed:
            return job.downloadProgress
        case .paused, .failed:
            return max(job.downloadProgress, Double(job.jobProgressPercent) / 100)
        case .canceled:
            return 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(job.state.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                actions
            }

            ProgressView(value: progress)
                .tint(.green)
            Text("\(Int(progress * 100))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 12) {
            switch job.state {
            case .downloading, .processing:
                Button(action: onPauseResume) { Image(systemName: "pause.fill") }
            case .paused, .queued:
                Button(action: onPauseResume) { Image(systemName: "play.fill") }
            case .failed:
                Button(action: onRetry) { Image(systemName: "arrow.clockwise") }
            case .ready:
                Button(action: onRequeue) { Image(systemName: "plus.circle") }
            case .completed:
                Button(action: onImport) { Image(systemName: "square.and.arrow.down") }
            default:
                EmptyView()
            }

            if job.state != .canceled {
                Button(role: .destructive, action: onCancel) { Image(systemName: "xmark") }
            }
        }
        .buttonStyle(.plain)
    }

    private var icon: String {
        switch job.state {
        case .queued: return "clock.arrow.circlepath"
        case .processing: return "gearshape.2.fill"
        case .ready: return "checkmark.seal.fill"
        case .downloading: return "arrow.down.circle.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .canceled: return "xmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch job.state {
        case .ready: return .green
        case .completed: return .green
        case .failed: return .orange
        case .paused: return .yellow
        case .canceled: return .red
        default: return .white
        }
    }
}

private struct DownloadJobDetailSheet: View {
    @EnvironmentObject private var localizationViewModel: LocalizationViewModel
    let job: DownloadJob

    var body: some View {
        NavigationStack {
            List {
                row(localizationViewModel.t("downloads.detail.job_id"), value: job.remoteJobID)
                row(localizationViewModel.t("downloads.detail.state"), value: job.state.rawValue)
                row(localizationViewModel.t("downloads.detail.progress"), value: "\(Int(progress * 100))%")
                row(localizationViewModel.t("downloads.detail.retry"), value: "\(job.retryCount)")
                if let sourceURL = job.sourceURL {
                    row(localizationViewModel.t("downloads.detail.source"), value: sourceURL)
                }
                if let localFilePath = job.localFilePath {
                    row(localizationViewModel.t("downloads.detail.file"), value: localFilePath)
                }
                if let errorMessage = job.errorMessage {
                    row(localizationViewModel.t("downloads.detail.error"), value: errorMessage)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(localizationViewModel.t("downloads.detail.title"))
        }
    }

    private var progress: Double {
        switch job.state {
        case .downloading, .completed:
            return job.downloadProgress
        default:
            return Double(job.jobProgressPercent) / 100
        }
    }

    private func row(_ key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
        .listRowBackground(Color.clear)
    }
}
