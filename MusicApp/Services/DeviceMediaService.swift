import Foundation

struct DeviceMediaService {
    struct EnsureStorageResult {
        let folderURL: URL?
        let path: String
        let status: String
    }

    struct ImportCounts {
        let imported: Int
        let skipped: Int
        let failed: Int
    }

    private enum Storage {
        static let musicFolderName = "MusicFiles"
    }

    func storageFolderURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(Storage.musicFolderName, isDirectory: true)
    }

    func ensureStorageFolderExists(localized: (String) -> String) -> EnsureStorageResult {
        guard let folderURL = storageFolderURL() else {
            return EnsureStorageResult(
                folderURL: nil,
                path: "-",
                status: localized("storage.status.unavailable")
            )
        }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory)

        if exists, isDirectory.boolValue {
            return EnsureStorageResult(
                folderURL: folderURL,
                path: folderURL.path,
                status: localized("storage.status.ready")
            )
        }

        do {
            if exists && !isDirectory.boolValue {
                try FileManager.default.removeItem(at: folderURL)
            }

            try FileManager.default.createDirectory(
                at: folderURL,
                withIntermediateDirectories: true,
                attributes: nil
            )

            return EnsureStorageResult(
                folderURL: folderURL,
                path: folderURL.path,
                status: localized("storage.status.created")
            )
        } catch {
            return EnsureStorageResult(
                folderURL: folderURL,
                path: folderURL.path,
                status: "\(localized("storage.status.failed")): \(error.localizedDescription)"
            )
        }
    }

    func importAudioFiles(from sourceURLs: [URL], destinationFolder: URL) -> ImportCounts {
        let supportedExtensions = Set(["mp3", "m4a", "wav", "aac"])
        var imported = 0
        var skipped = 0
        var failed = 0

        for sourceURL in sourceURLs {
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
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                imported += 1
            } catch {
                failed += 1
            }
        }

        return ImportCounts(imported: imported, skipped: skipped, failed: failed)
    }

    func loadDeviceTracks(in root: URL) -> [LocalAudioTrack] {
        let allowedExtensions = Set(["mp3", "m4a", "wav", "aac"])
        let files = allAudioFiles(in: root, allowedExtensions: allowedExtensions)

        return files
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                LocalAudioTrack(
                    id: url,
                    url: url,
                    fileName: url.lastPathComponent,
                    displayName: url.deletingPathExtension().lastPathComponent,
                    duration: 180
                )
            }
    }

    func audioURL(for song: Song) -> URL? {
        if let localFilePath = song.localFilePath, FileManager.default.fileExists(atPath: localFilePath) {
            return URL(fileURLWithPath: localFilePath)
        }

        let file = song.audioFileName as NSString
        let name = file.deletingPathExtension
        let ext = file.pathExtension

        if let localURL = musicFileURL(fileName: song.audioFileName), FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        for candidateExt in ["mp3", "m4a", "wav"] {
            let candidate = "\(name).\(candidateExt)"
            if let url = musicFileURL(fileName: candidate), FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/Audio") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Audio") {
            return url
        }

        return nil
    }

    private func musicFileURL(fileName: String) -> URL? {
        storageFolderURL()?.appendingPathComponent(fileName)
    }

    private func allAudioFiles(in root: URL, allowedExtensions: Set<String>) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var result: [URL] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }
            result.append(url)
        }
        return result
    }
}
