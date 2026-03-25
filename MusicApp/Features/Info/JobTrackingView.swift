import SwiftUI

struct JobTrackingView: View {
    let jobID: String

    @EnvironmentObject private var localizationViewModel: LocalizationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(localizationViewModel.t("job.tracking.description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("job_id: \(jobID)")
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(16)
            .padding(.bottom, 59)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(localizationViewModel.t("job.tracking.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
