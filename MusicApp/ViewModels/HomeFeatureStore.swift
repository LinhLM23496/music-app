import Foundation
import Combine
import CryptoKit
import SwiftUI

@MainActor
final class HomeFeatureStore: ObservableObject, HomeFeatureControlling {
    private let settingsStore: AppSettingsStore
    private let libraryStore: LibraryStore
    private let deviceMediaStore: DeviceMediaStore
    private let deviceMediaService: DeviceMediaService
    private weak var playerStore: PlayerFeatureStore?
    private let libraryUseCases = LibraryUseCases()
    private let ioQueue = DispatchQueue(label: "com.musicapp.home.audio-io", qos: .userInitiated)

    init(
        settingsStore: AppSettingsStore,
        libraryStore: LibraryStore,
        deviceMediaStore: DeviceMediaStore,
        deviceMediaService: DeviceMediaService,
        playerStore: PlayerFeatureStore? = nil
    ) {
        self.settingsStore = settingsStore
        self.libraryStore = libraryStore
        self.deviceMediaStore = deviceMediaStore
        self.deviceMediaService = deviceMediaService
        self.playerStore = playerStore
    }

    func attach(playerStore: PlayerFeatureStore) {
        self.playerStore = playerStore
    }

    var changePublisher: AnyPublisher<Void, Never> {
        objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }

    var featuredSongs: [Song] {
        libraryUseCases.featuredSongs(
            songs: libraryStore.songs,
            featuredSongIDs: libraryStore.featuredSongIDs
        )
    }

    var favoriteSongs: [Song] {
        libraryUseCases.favoriteSongs(
            songs: libraryStore.songs,
            favoriteSongIDs: libraryStore.favoriteSongIDs
        )
    }

    var deviceTracks: [LocalAudioTrack] {
        deviceMediaStore.deviceTracks
    }

    func localized(_ key: String) -> String {
        Localizer.string(key, language: settingsStore.language)
    }

    func localizedSongTitle(_ song: Song) -> String {
        song.localizedTitle(for: settingsStore.language)
    }

    func play(song: Song) {
        playerStore?.play(song: song)
    }

    func presentPlayer(for song: Song) {
        playerStore?.presentPlayer(for: song)
    }

    func refreshDeviceTracks() {
        let ensureResult = deviceMediaService.ensureStorageFolderExists(localized: localized)
        deviceMediaStore.musicStorageFolderPath = ensureResult.path
        deviceMediaStore.musicStorageFolderStatus = ensureResult.status

        guard let musicFolderURL = ensureResult.folderURL else {
            deviceMediaStore.deviceTracks = []
            return
        }

        ioQueue.async { [weak self] in
            guard let self else { return }
            let tracks = self.deviceMediaService.loadDeviceTracks(in: musicFolderURL)
            Task { @MainActor [weak self] in
                self?.deviceMediaStore.deviceTracks = tracks
            }
        }
    }

    func importAudioFiles(from urls: [URL], completion: @escaping (HomeImportResult) -> Void) {
        let ensureResult = deviceMediaService.ensureStorageFolderExists(localized: localized)
        deviceMediaStore.musicStorageFolderPath = ensureResult.path
        deviceMediaStore.musicStorageFolderStatus = ensureResult.status

        guard let destinationFolder = ensureResult.folderURL else {
            completion(HomeImportResult(importedCount: 0, skippedCount: 0, failedCount: urls.count))
            return
        }

        ioQueue.async { [weak self] in
            guard let self else { return }

            let counts = self.deviceMediaService.importAudioFiles(
                from: urls,
                destinationFolder: destinationFolder
            )

            let result = HomeImportResult(
                importedCount: counts.imported,
                skippedCount: counts.skipped,
                failedCount: counts.failed
            )
            let tracks = self.deviceMediaService.loadDeviceTracks(in: destinationFolder)

            Task { @MainActor [weak self] in
                self?.deviceMediaStore.deviceTracks = tracks
                completion(result)
            }
        }
    }

    func importSummaryText(_ result: HomeImportResult) -> String {
        String(
            format: localized("home.device.music.import.result"),
            result.importedCount,
            result.skippedCount,
            result.failedCount
        )
    }

    func songForDeviceTrack(_ track: LocalAudioTrack) -> Song {
        Song(
            id: stableSongID(forLocalPath: track.url.path),
            titleEN: track.displayName,
            titleVI: track.displayName,
            artist: localized("device.artist"),
            album: localized("home.device.music"),
            coverSymbol: "iphone.gen3",
            audioFileName: track.fileName,
            localFilePath: track.url.path,
            duration: track.duration,
            accent: .green
        )
    }

    private func stableSongID(forLocalPath path: String) -> UUID {
        let digest = SHA256.hash(data: Data(path.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let uuid = uuid_t(bytes[0], bytes[1], bytes[2], bytes[3],
                          bytes[4], bytes[5], bytes[6], bytes[7],
                          bytes[8], bytes[9], bytes[10], bytes[11],
                          bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: uuid)
    }
}
