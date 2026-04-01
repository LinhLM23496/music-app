import SwiftUI
import UIKit
import Combine

@MainActor
final class JobTrackingViewModel: ObservableObject {
    private enum Limits {
        static let maxTitleLength = 50
    }

    @Published private(set) var status: MediaJobStatus?
    @Published private(set) var result: MediaJobResult?
    @Published private(set) var isLoading = false
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var downloadedFileURL: URL?
    @Published private(set) var editedSourceTitle: String = ""

    let jobID: String

    private let service: MediaJobServicing
    private var pollingTask: Task<Void, Never>?
    private var hasUserEditedTitle = false

    init(jobID: String, service: MediaJobServicing) {
        self.jobID = jobID
        self.service = service
    }

    deinit {
        pollingTask?.cancel()
    }

    func startTracking() {
        guard pollingTask == nil else { return }

        pollingTask = Task { [weak self] in
            guard let self else { return }
            await refreshLoop()
        }
    }

    func stopTracking() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func refreshLoop() async {
        await fetchStatusAndMaybeResult(initialLoad: true)

        while !Task.isCancelled, status?.status.isProcessing == true {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { break }
            await fetchStatusAndMaybeResult(initialLoad: false)
        }

        pollingTask = nil
    }

    private func fetchStatusAndMaybeResult(initialLoad: Bool) async {
        if initialLoad {
            isLoading = true
        }
        errorMessage = nil

        do {
            let jobStatus = try await service.getJobStatus(jobID: jobID)
            status = jobStatus

            if !jobStatus.status.isProcessing {
                let jobResult = try await service.getJobResult(jobID: jobID)
                result = jobResult

                let title = normalizedTitle(jobResult.sourceMeta?.title)
                if !hasUserEditedTitle, !title.isEmpty {
                    editedSourceTitle = title
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        if initialLoad {
            isLoading = false
        }
    }

    func setEditedSourceTitle(_ title: String) {
        editedSourceTitle = normalizedTitle(title)
        hasUserEditedTitle = true
    }

    var displaySourceTitle: String? {
        if !editedSourceTitle.isEmpty {
            return editedSourceTitle
        }
        return normalizedTitle(result?.sourceMeta?.title)
    }

    func downloadAsset() async {
        guard status?.status == .done else { return }

        isDownloading = true
        downloadProgress = 0
        errorMessage = nil

        defer {
            isDownloading = false
        }

        do {
            downloadedFileURL = try await service.downloadJobAsset(
                jobID: jobID,
                preferredFileName: editedSourceTitle.isEmpty ? nil : editedSourceTitle,
                onProgress: { [weak self] progress in
                    guard let self else { return }
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                }
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func normalizedTitle(_ title: String?) -> String {
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return String(trimmed.prefix(Limits.maxTitleLength))
    }
}

struct JobTrackingView: View {
    @EnvironmentObject private var localizationViewModel: LocalizationViewModel
    @StateObject private var viewModel: JobTrackingViewModel
    @State private var showCopiedToast = false
    @State private var showEditTitlePopup = false
    @State private var editedTitleDraft = ""
    @State private var toastWorkItem: DispatchWorkItem?

    init(jobID: String, service: MediaJobServicing) {
        _viewModel = StateObject(
            wrappedValue: JobTrackingViewModel(jobID: jobID, service: service)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(localizationViewModel.t("job.tracking.description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                JobStatusCardView(
                    title: localizationViewModel.t("job.tracking.card.title"),
                    progress: progressValue
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("job_id: \(viewModel.jobID)")
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)

                        Text("\(localizationViewModel.t("job.tracking.status")): \(statusText)")
                            .font(.subheadline)

                        if let status = viewModel.status {
                            Text("\(localizationViewModel.t("job.tracking.progress")): \(status.progress)%")
                                .font(.subheadline)

                            if !status.status.isProcessing {
                                if let sourceTitle = viewModel.displaySourceTitle, !sourceTitle.isEmpty {
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(localizationViewModel.t("job.tracking.source.title")): \(sourceTitle)")
                                            .font(.subheadline)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .fixedSize(horizontal: false, vertical: true)

                                        Button {
                                            editedTitleDraft = sourceTitle
                                            showEditTitlePopup = true
                                        } label: {
                                            Image(systemName: "square.and.pencil")
                                                .foregroundStyle(.green)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(localizationViewModel.t("job.tracking.source.title.edit"))
                                    }
                                }

                                let assetCount = viewModel.result?.assets.count ?? 0
                                Text("\(localizationViewModel.t("job.tracking.assets.count")): \(assetCount)")
                                    .font(.subheadline)

                                if let jobError = status.error, !jobError.isEmpty {
                                    Text(jobError)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                }

                                if status.status == .done {
                                    Button {
                                        Task {
                                            await viewModel.downloadAsset()
                                        }
                                    } label: {
                                        if viewModel.isDownloading {
                                            Text(
                                                "\(localizationViewModel.t("job.tracking.download.progress")): \(Int(viewModel.downloadProgress * 100))%"
                                            )
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                        } else {
                                            Text(localizationViewModel.t("job.tracking.download"))
                                                .font(.subheadline.weight(.semibold))
                                                .frame(maxWidth: .infinity)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                    .disabled(viewModel.isDownloading)

                                    if viewModel.isDownloading {
                                        ProgressView(value: viewModel.downloadProgress)
                                            .tint(.green)

                                        Text(
                                            "\(localizationViewModel.t("job.tracking.download.progress")): \(Int(viewModel.downloadProgress * 100))%"
                                        )
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } else if viewModel.isLoading {
                            ProgressView()
                                .tint(.green)
                        }

                        if let downloadedURL = viewModel.downloadedFileURL {
                            Text("\(localizationViewModel.t("job.tracking.downloaded.path")): \(downloadedURL.path)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 59)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(localizationViewModel.t("job.tracking.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = viewModel.jobID
                    showCopyToast()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
            }
        }
        .overlay(alignment: .top) {
            if showCopiedToast {
                AppToastView(message: localizationViewModel.t("job.tracking.copy.success"))
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showCopiedToast)
        .alert(localizationViewModel.t("job.tracking.source.title.edit"), isPresented: $showEditTitlePopup) {
            TextField(localizationViewModel.t("job.tracking.source.title.placeholder"), text: $editedTitleDraft)
            Button(localizationViewModel.t("job.tracking.source.title.clear")) {
                editedTitleDraft = ""
                viewModel.setEditedSourceTitle("")
            }
            Button(localizationViewModel.t("playlist.cancel"), role: .cancel) {}
            Button(localizationViewModel.t("common.done")) {
                let normalized = String(
                    editedTitleDraft
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .prefix(50)
                )
                viewModel.setEditedSourceTitle(normalized)
            }
        } message: {
            Text(localizationViewModel.t("job.tracking.source.title.limit"))
        }
        .onChange(of: editedTitleDraft) { _, newValue in
            if newValue.count > 50 {
                editedTitleDraft = String(newValue.prefix(50))
            }
        }
        .onAppear {
            viewModel.startTracking()
        }
        .onDisappear {
            viewModel.stopTracking()
        }
    }

    private var progressValue: Double {
        guard let progress = viewModel.status?.progress else { return 0 }
        return Double(min(max(progress, 0), 100)) / 100
    }

    private var statusText: String {
        guard let status = viewModel.status?.status else {
            return localizationViewModel.t("job.tracking.status.unknown")
        }
        return status.rawValue
    }

    private func showCopyToast() {
        toastWorkItem?.cancel()
        showCopiedToast = true

        let workItem = DispatchWorkItem {
            showCopiedToast = false
        }
        toastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: workItem)
    }
}
