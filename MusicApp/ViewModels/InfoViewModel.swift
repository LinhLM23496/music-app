import Foundation
import Combine

@MainActor
final class InfoViewModel: ObservableObject {
    let source: any InfoFeatureControlling
    let settingsStore: AppSettingsStore
    private var cancellables = Set<AnyCancellable>()

    init(source: any InfoFeatureControlling, settingsStore: AppSettingsStore) {
        self.source = source
        self.settingsStore = settingsStore

        source.changePublisher
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

    var user: AppUser { source.user }
    var musicStorageFolderStatus: String { source.musicStorageFolderStatus }
    var musicStorageFolderPath: String { source.musicStorageFolderPath }

    func localized(_ key: String) -> String { source.localized(key) }
    func refreshDeviceTracks() { source.refreshDeviceTracks() }
    func musicStorageURL() -> URL? { source.musicStorageURL() }
}
