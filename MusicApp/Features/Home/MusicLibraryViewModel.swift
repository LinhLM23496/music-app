import SwiftUI
import Combine
import CryptoKit

struct ImportResult {
    let importedCount: Int
    let skippedCount: Int
    let failedCount: Int
}

@MainActor
final class ImportViewModel: ObservableObject {
    private enum Storage {
        static let musicFolderName = "MusicFiles"
    }

    @Published var importedTracks: [LocalAudioTrack] {
        didSet {
            guard shouldPersistImportedTracks else { return }
            persistImportedTracks()
        }
    }

    var importedSongs: [Song] {
        importedTracks.map(songForImportedTrack)
    }

    private let settingsStore: AppSettingsStore
    private let ioQueue = DispatchQueue(label: "com.musicapp.audio-io", qos: .userInitiated)
    private var shouldPersistImportedTracks = false

    init(settingsStore: AppSettingsStore) {
        self.settingsStore = settingsStore
        importedTracks = []

        ensureMusicStorageFolderExists()
        restoreImportedTracks()
        shouldPersistImportedTracks = true
        persistImportedTracks()
    }

    func localized(_ key: String) -> String {
        Localizer.string(key, language: settingsStore.language)
    }

    func importAudioFiles(from urls: [URL], completion: @escaping (ImportResult) -> Void) {
        ensureMusicStorageFolderExists()

        guard let destinationFolder = musicStorageFolderURL() else {
            completion(ImportResult(importedCount: 0, skippedCount: 0, failedCount: urls.count))
            return
        }

        ioQueue.async {
            let supportedExtensions = Set(["mp3", "m4a", "wav", "aac"])
            var imported = 0
            var skipped = 0
            var failed = 0
            var importedResults: [LocalAudioTrack] = []

            for sourceURL in urls {
                let accessed = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }

                let ext = sourceURL.pathExtension.lowercased()
                guard supportedExtensions.contains(ext) else {
                    skipped += 1
                    continue
                }

                let destinationURL = destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)

                do {
                    let isSamePath = sourceURL.standardizedFileURL.path == destinationURL.standardizedFileURL.path

                    if !isSamePath, FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    if !isSamePath {
                        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    }

                    imported += 1
                    importedResults.append(
                        LocalAudioTrack(
                            id: destinationURL,
                            url: destinationURL,
                            fileName: destinationURL.lastPathComponent,
                            displayName: destinationURL.deletingPathExtension().lastPathComponent,
                            duration: 180
                        )
                    )
                } catch {
                    failed += 1
                }
            }

            let result = ImportResult(importedCount: imported, skippedCount: skipped, failedCount: failed)
            let finalizedImportedResults = importedResults

            Task { @MainActor [weak self] in
                guard let self else {
                    completion(result)
                    return
                }

                var mergedByPath = Dictionary(uniqueKeysWithValues: self.importedTracks.map { ($0.url.path, $0) })
                for track in finalizedImportedResults {
                    mergedByPath[track.url.path] = track
                }
                self.importedTracks = mergedByPath.values.sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                completion(result)
            }
        }
    }

    func importSummaryText(_ result: ImportResult) -> String {
        String(
            format: localized("home.device.music.import.result"),
            result.importedCount,
            result.skippedCount,
            result.failedCount
        )
    }

    func songForImportedTrack(_ track: LocalAudioTrack) -> Song {
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

    private func musicStorageFolderURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(Storage.musicFolderName, isDirectory: true)
    }

    private func ensureMusicStorageFolderExists() {
        guard let folderURL = musicStorageFolderURL() else { return }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory)

        if exists, isDirectory.boolValue { return }

        do {
            if exists, !isDirectory.boolValue {
                try FileManager.default.removeItem(at: folderURL)
            }

            try FileManager.default.createDirectory(
                at: folderURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            // Ignore storage setup errors here; import flow reports failures per file.
        }
    }

    private func restoreImportedTracks() {
        let storageFolder = musicStorageFolderURL()
        let restored = settingsStore.loadImportedTracks()
            .compactMap { snapshot -> LocalAudioTrack? in
                let preferredURL = storageFolder?.appendingPathComponent(snapshot.fileName)
                let resolvedURL: URL?

                if let preferredURL, FileManager.default.fileExists(atPath: preferredURL.path) {
                    resolvedURL = preferredURL
                } else {
                    let legacyURL = URL(fileURLWithPath: snapshot.filePath)
                    resolvedURL = FileManager.default.fileExists(atPath: legacyURL.path) ? legacyURL : nil
                }

                guard let resolvedURL else { return nil }
                return LocalAudioTrack(
                    id: resolvedURL,
                    url: resolvedURL,
                    fileName: snapshot.fileName,
                    displayName: snapshot.displayName,
                    duration: snapshot.duration
                )
            }

        importedTracks = restored.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func persistImportedTracks() {
        let snapshots = importedTracks.map {
            ImportedTrackSnapshot(
                filePath: $0.url.path,
                fileName: $0.fileName,
                displayName: $0.displayName,
                duration: $0.duration
            )
        }
        settingsStore.saveImportedTracks(snapshots)
    }

    private func stableSongID(forLocalPath path: String) -> UUID {
        let digest = SHA256.hash(data: Data(path.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let uuid = uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }
}

@MainActor
final class PlaylistViewModel: ObservableObject {
    @Published var playlists: [Playlist]

    private let playlistRepository: PlaylistRepository
    private let playlistUseCases = PlaylistUseCases()

    init(playlistRepository: PlaylistRepository) {
        self.playlistRepository = playlistRepository
        playlists = playlistRepository.loadPlaylists()
    }

    func createPlaylist(name: String) {
        playlists = playlistUseCases.createPlaylist(name: name, in: playlists)
        playlistRepository.savePlaylists(playlists)
    }

    func deletePlaylist(at offsets: IndexSet) {
        playlists = playlistUseCases.deletePlaylists(at: offsets, in: playlists)
        playlistRepository.savePlaylists(playlists)
    }

    func renamePlaylist(id: UUID, name: String) {
        playlists = playlistUseCases.renamePlaylist(id: id, name: name, in: playlists)
        playlistRepository.savePlaylists(playlists)
    }

    func addSong(_ song: Song, to playlistID: UUID) {
        playlists = playlistUseCases.addSong(song, to: playlistID, in: playlists)
        playlistRepository.savePlaylists(playlists)
    }

    func toggleSong(_ song: Song, in playlistID: UUID) -> Bool {
        if containsSong(song.id, in: playlistID) {
            playlists = playlistUseCases.removeSong(song, from: playlistID, in: playlists)
            playlistRepository.savePlaylists(playlists)
            return false
        }

        playlists = playlistUseCases.addSong(song, to: playlistID, in: playlists)
        playlistRepository.savePlaylists(playlists)
        return true
    }

    func containsSong(_ songID: UUID, in playlistID: UUID) -> Bool {
        guard let playlist = playlists.first(where: { $0.id == playlistID }) else { return false }
        return playlist.songIDs.contains(songID)
    }

    func removeSong(_ song: Song, from playlistID: UUID) {
        playlists = playlistUseCases.removeSong(song, from: playlistID, in: playlists)
        playlistRepository.savePlaylists(playlists)
    }

    func moveSongs(in playlistID: UUID, from offsets: IndexSet, to destination: Int) {
        playlists = playlistUseCases.moveSongs(in: playlistID, from: offsets, to: destination, in: playlists)
        playlistRepository.savePlaylists(playlists)
    }

    func playlist(id: UUID) -> Playlist? {
        playlists.first(where: { $0.id == id })
    }

    func songs(in playlist: Playlist, allSongs: [Song]) -> [Song] {
        playlistUseCases.songs(in: playlist, allSongs: allSongs)
    }
}
