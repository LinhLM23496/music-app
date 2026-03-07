import Foundation
import Combine

@MainActor
final class InfoViewModel: ObservableObject {
    let appVM: MusicLibraryViewModel
    let settingsStore: AppSettingsStore
    private var cancellables = Set<AnyCancellable>()

    init(appVM: MusicLibraryViewModel, settingsStore: AppSettingsStore) {
        self.appVM = appVM
        self.settingsStore = settingsStore

        appVM.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        settingsStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var user: AppUser { appVM.user }
    var musicStorageFolderStatus: String { appVM.musicStorageFolderStatus }
    var musicStorageFolderPath: String { appVM.musicStorageFolderPath }

    func localized(_ key: String) -> String { appVM.localized(key) }
    func refreshDeviceTracks() { appVM.refreshDeviceTracks() }
    func musicStorageURL() -> URL? { appVM.musicStorageURL() }
}
