import SwiftUI

struct InfoTabView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var vm: MusicLibraryViewModel
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @State private var showOpenFilesError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        Image(systemName: vm.user.avatarSymbol)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 88, height: 88)
                            .foregroundStyle(.green)

                        Text(vm.user.username)
                            .font(.title2.bold())
                        Text("\(vm.localized("info.version")): \(vm.user.appVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(vm.localized("info.language"))
                                .font(.subheadline.weight(.semibold))
                            Picker(vm.localized("info.language"), selection: $settingsStore.language) {
                                ForEach(AppLanguage.allCases) { language in
                                    Text(language.displayName).tag(language)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Toggle(vm.localized("info.push.notifications"), isOn: $settingsStore.pushNotificationsEnabled)
                        Toggle(vm.localized("info.auto.play"), isOn: $settingsStore.autoPlayEnabled)

                        Button {
                        } label: {
                            settingsRow(vm.localized("info.account"), icon: "person.crop.circle")
                        }

                        Button {
                        } label: {
                            settingsRow(vm.localized("info.privacy"), icon: "lock.shield")
                        }

                        Button {
                        } label: {
                            settingsRow(vm.localized("info.help"), icon: "questionmark.circle")
                        }
                    }
                    .tint(.green)
                    .padding(16)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        Text(vm.localized("info.storage"))
                            .font(.subheadline.weight(.semibold))

                        Text("\(vm.localized("info.storage.status")): \(vm.musicStorageFolderStatus)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text(vm.musicStorageFolderPath)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        HStack(spacing: 12) {
                            Button(vm.localized("info.storage.check")) {
                                vm.refreshDeviceTracks()
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)

                            Button(vm.localized("info.storage.open.files")) {
                                openMusicFolderInFiles()
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)

                            Button(vm.localized("common.refresh")) {
                                vm.refreshDeviceTracks()
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(vm.localized("info.title"))
        }
        .alert(vm.localized("info.storage.open.files.failed"), isPresented: $showOpenFilesError) {
            Button(vm.localized("common.done"), role: .cancel) {}
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

    private func openMusicFolderInFiles() {
        guard let folderURL = vm.musicStorageURL() else {
            showOpenFilesError = true
            return
        }

        openURL(folderURL) { accepted in
            if !accepted {
                showOpenFilesError = true
            }
        }
    }
}
