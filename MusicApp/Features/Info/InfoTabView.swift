import SwiftUI

struct InfoTabView: View {
    @EnvironmentObject private var localizationViewModel: LocalizationViewModel
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        Image(systemName: authViewModel.activeUser.avatarSymbol)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 88, height: 88)
                            .foregroundStyle(.green)

                        Text(authViewModel.currentUser?.displayName ?? localizationViewModel.t("auth.guest"))
                            .font(.title2.bold())
                        Text("\(localizationViewModel.t("info.version")): \(authViewModel.activeUser.appVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(localizationViewModel.t("info.language"))
                                .font(.subheadline.weight(.semibold))
                            Picker(localizationViewModel.t("info.language"), selection: $settingsStore.language) {
                                ForEach(AppLanguage.allCases) { language in
                                    Text(language.displayName).tag(language)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Toggle(localizationViewModel.t("info.push.notifications"), isOn: $settingsStore.pushNotificationsEnabled)
                        Toggle(localizationViewModel.t("info.auto.play"), isOn: $settingsStore.autoPlayEnabled)
                        Toggle(localizationViewModel.t("downloads.settings.cellular"), isOn: $settingsStore.allowCellularDownloads)
                        Toggle(localizationViewModel.t("downloads.settings.low.power"), isOn: $settingsStore.pauseDownloadsOnLowPowerMode)
                        Toggle(localizationViewModel.t("downloads.settings.auto.resume"), isOn: $settingsStore.autoResumeDownloads)

                        NavigationLink {
                            DownloadListView()
                                .environmentObject(localizationViewModel)
                        } label: {
                            settingsRow(localizationViewModel.t("info.download.list"), icon: "arrow.down.circle")
                        }

                        NavigationLink {
                            ImportMediaView(service: AppContainer.shared.mediaJobService)
                                .environmentObject(localizationViewModel)
                        } label: {
                            settingsRow(localizationViewModel.t("info.import.media"), icon: "square.and.arrow.down")
                        }

                        Button {
                        } label: {
                            settingsRow(localizationViewModel.t("info.account"), icon: "person.crop.circle")
                        }

                        Button {
                        } label: {
                            settingsRow(localizationViewModel.t("info.privacy"), icon: "lock.shield")
                        }

                        Button {
                        } label: {
                            settingsRow(localizationViewModel.t("info.help"), icon: "questionmark.circle")
                        }

                        Button {
                            if authViewModel.isLoggedIn {
                                authViewModel.signOut()
                            } else {
                                authViewModel.signInDemo()
                            }
                        } label: {
                            settingsRow(
                                authViewModel.isLoggedIn ? localizationViewModel.t("auth.signout") : localizationViewModel.t("auth.signin.demo"),
                                icon: authViewModel.isLoggedIn ? "rectangle.portrait.and.arrow.right" : "person.crop.circle.badge.plus"
                            )
                        }
                    }
                    .tint(.green)
                    .padding(16)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(16)
                .padding(.bottom, 59)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(localizationViewModel.t("info.title"))
        }
    }

    private func settingsRow(_ text: String, icon: String) -> some View {
        HStack {
            Label(text, systemImage: icon)
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
