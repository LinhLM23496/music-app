//
//  DefaultTrackResolver.swift
//  MusicApp
//
//  Created by Linh Le on 15/3/26.
//

import Foundation

@MainActor
final class DefaultTrackResolver: TrackResolver {
    private enum Storage {
        static let musicFolderName = "MusicFiles"
    }

    private let librarySongsProvider: () -> [Song]
    private let importedSongsProvider: () -> [Song]

    init(
        librarySongsProvider: @escaping () -> [Song],
        importedSongsProvider: @escaping () -> [Song]
    ) {
        self.librarySongsProvider = librarySongsProvider
        self.importedSongsProvider = importedSongsProvider
    }

    func song(for id: UUID) -> Song? {
        allSongs.first(where: { $0.id == id })
    }

    func audioURL(for id: UUID) -> URL? {
        guard let song = song(for: id) else { return nil }
        return resolveAudioURL(for: song)
    }

    private var allSongs: [Song] {
        let librarySongs = librarySongsProvider()
        let importedSongs = importedSongsProvider()

        var combined = librarySongs
        let existingIDs = Set(combined.map(\.id))
        combined.append(contentsOf: importedSongs.filter { !existingIDs.contains($0.id) })
        return combined
    }

    private func resolveAudioURL(for song: Song) -> URL? {
        if let localFilePath = song.localFilePath,
           FileManager.default.fileExists(atPath: localFilePath) {
            return URL(fileURLWithPath: localFilePath)
        }

        let file = song.audioFileName as NSString
        let name = file.deletingPathExtension
        let ext = file.pathExtension

        if let localURL = musicFileURL(fileName: song.audioFileName),
           FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        for candidateExt in ["mp3", "m4a", "wav", "aac"] {
            let candidate = "\(name).\(candidateExt)"
            if let url = musicFileURL(fileName: candidate),
               FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/Audio") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/MockAudio") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Audio") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "MockAudio") {
            return url
        }

        return nil
    }

    private func musicStorageFolderURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(Storage.musicFolderName, isDirectory: true)
    }

    private func musicFileURL(fileName: String) -> URL? {
        musicStorageFolderURL()?
            .appendingPathComponent(fileName)
    }
}
