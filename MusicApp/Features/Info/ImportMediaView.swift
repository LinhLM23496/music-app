import SwiftUI
import Combine

@MainActor
final class ImportMediaViewModel: ObservableObject {
    @Published var sourceText: String = ""
    @Published var jobIDText: String = ""
    @Published var useCookie = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var createdJobID: String?
    @Published private(set) var errorMessage: String?

    private let service: MediaJobServicing

    init(service: MediaJobServicing) {
        self.service = service
    }

    func setSourceText(from pastedItems: [String]) {
        guard let first = pastedItems.first else { return }
        sourceText = first
    }

    func setJobIDText(from pastedItems: [String]) {
        guard let first = pastedItems.first else { return }
        jobIDText = first
    }

    func submit() async {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              URL(string: trimmed) != nil else {
            errorMessage = "import.media.error.invalid.url"
            createdJobID = nil
            return
        }

        isSubmitting = true
        errorMessage = nil
        createdJobID = nil

        defer {
            isSubmitting = false
        }

        do {
            let sourceType = detectSourceType(from: trimmed)
            let jobID = try await service.createJob(
                sourceType: sourceType,
                sourceURL: trimmed,
                useCookie: useCookie
            )
            createdJobID = jobID
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func detectSourceType(from sourceURL: String) -> MediaSourceType {
        guard let host = URL(string: sourceURL)?.host?.lowercased() else {
            return .youtube
        }

        if host.contains("tiktok") {
            return .tiktok
        }

        if host.contains("facebook") || host.contains("fb.watch") {
            return .facebook
        }

        return .youtube
    }
}

struct ImportMediaView: View {
    @EnvironmentObject private var localizationViewModel: LocalizationViewModel
    @StateObject private var viewModel: ImportMediaViewModel
    private let service: MediaJobServicing

    init(service: MediaJobServicing) {
        self.service = service
        _viewModel = StateObject(wrappedValue: ImportMediaViewModel(service: service))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(localizationViewModel.t("import.media.description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Text(localizationViewModel.t("import.media.input.label"))
                        .font(.subheadline.weight(.semibold))

                    TextEditor(text: $viewModel.sourceText)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    Toggle(localizationViewModel.t("import.media.use.cookie"), isOn: $viewModel.useCookie)

                    HStack {
                        PasteButton(payloadType: String.self) { strings in
                            viewModel.setSourceText(from: strings)
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button {
                            Task {
                                await viewModel.submit()
                            }
                        } label: {
                            if viewModel.isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(localizationViewModel.t("import.media.submit"))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(viewModel.isSubmitting)
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text(localizationViewModel.t("import.media.jobid.label"))
                        .font(.subheadline.weight(.semibold))

                    TextField(localizationViewModel.t("import.media.jobid.placeholder"), text: $viewModel.jobIDText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .padding(10)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    HStack {
                        PasteButton(payloadType: String.self) { strings in
                            viewModel.setJobIDText(from: strings)
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        NavigationLink {
                            JobTrackingView(
                                jobID: viewModel.jobIDText.trimmingCharacters(in: .whitespacesAndNewlines),
                                service: service
                            )
                            .environmentObject(localizationViewModel)
                        } label: {
                            Text(localizationViewModel.t("import.media.track.job"))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(viewModel.jobIDText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let jobID = viewModel.createdJobID {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(localizationViewModel.t("import.media.success"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                        Text("job_id: \(jobID)")
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)

                        NavigationLink {
                            JobTrackingView(jobID: jobID, service: service)
                                .environmentObject(localizationViewModel)
                        } label: {
                            Text(localizationViewModel.t("import.media.track.job"))
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if let errorMessage = viewModel.errorMessage {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(localizationViewModel.t("import.media.error.title"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                        Text(localizedErrorMessage(errorMessage))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(16)
            .padding(.bottom, 59)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(localizationViewModel.t("import.media.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func localizedErrorMessage(_ message: String) -> String {
        if message == "import.media.error.invalid.url" {
            return localizationViewModel.t(message)
        }

        return message
    }
}
