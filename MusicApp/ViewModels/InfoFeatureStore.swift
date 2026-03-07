import Foundation
import Combine

@MainActor
final class InfoFeatureStore: ObservableObject, InfoFeatureControlling {
    private let settingsStore: AppSettingsStore
    private let userInfoStore: UserInfoStore
    private let deviceMediaStore: DeviceMediaStore
    private let deviceMediaService: DeviceMediaService
    private let ioQueue = DispatchQueue(label: "com.musicapp.info.audio-io", qos: .userInitiated)

    init(
        settingsStore: AppSettingsStore,
        userInfoStore: UserInfoStore,
        deviceMediaStore: DeviceMediaStore,
        deviceMediaService: DeviceMediaService
    ) {
        self.settingsStore = settingsStore
        self.userInfoStore = userInfoStore
        self.deviceMediaStore = deviceMediaStore
        self.deviceMediaService = deviceMediaService
    }

    var changePublisher: AnyPublisher<Void, Never> {
        objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }

    var user: AppUser { userInfoStore.user }
    var musicStorageFolderStatus: String { deviceMediaStore.musicStorageFolderStatus }
    var musicStorageFolderPath: String { deviceMediaStore.musicStorageFolderPath }

    func localized(_ key: String) -> String {
        Localizer.string(key, language: settingsStore.language)
    }

    func refreshDeviceTracks() {
        let ensureResult = deviceMediaService.ensureStorageFolderExists(localized: localized)
        deviceMediaStore.musicStorageFolderPath = ensureResult.path
        deviceMediaStore.musicStorageFolderStatus = ensureResult.status

        guard let folderURL = ensureResult.folderURL else {
            deviceMediaStore.deviceTracks = []
            return
        }

        ioQueue.async { [weak self] in
            guard let self else { return }
            let tracks = self.deviceMediaService.loadDeviceTracks(in: folderURL)
            Task { @MainActor [weak self] in
                self?.deviceMediaStore.deviceTracks = tracks
            }
        }
    }

    func musicStorageURL() -> URL? {
        deviceMediaService.storageFolderURL()
    }
}
