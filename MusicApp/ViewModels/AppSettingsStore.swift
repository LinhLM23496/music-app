import Foundation
import Combine

struct PlaybackSnapshot: Codable {
    let audioFileName: String
    let titleEN: String
    let localFilePath: String?
    let positionSeconds: Double
    let playlistID: UUID?

    private enum CodingKeys: String, CodingKey {
        case audioFileName
        case titleEN
        case localFilePath
        case positionSeconds
        case playlistID
    }

    init(
        audioFileName: String,
        titleEN: String,
        localFilePath: String?,
        positionSeconds: Double,
        playlistID: UUID?
    ) {
        self.audioFileName = audioFileName
        self.titleEN = titleEN
        self.localFilePath = localFilePath
        self.positionSeconds = positionSeconds
        self.playlistID = playlistID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName) ?? ""
        titleEN = try container.decodeIfPresent(String.self, forKey: .titleEN) ?? ""
        localFilePath = try container.decodeIfPresent(String.self, forKey: .localFilePath)
        positionSeconds = try container.decodeIfPresent(Double.self, forKey: .positionSeconds) ?? 0
        playlistID = try container.decodeIfPresent(UUID.self, forKey: .playlistID)
    }
}

struct ImportedTrackSnapshot: Codable {
    let filePath: String
    let fileName: String
    let displayName: String
    let duration: Double
}

final class AppSettingsStore: ObservableObject {
    static let shared = AppSettingsStore()

    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
        }
    }

    @Published var pushNotificationsEnabled: Bool {
        didSet {
            defaults.set(pushNotificationsEnabled, forKey: Keys.pushNotifications)
        }
    }

    @Published var autoPlayEnabled: Bool {
        didSet {
            defaults.set(autoPlayEnabled, forKey: Keys.autoPlay)
        }
    }

    @Published var shuffleEnabled: Bool {
        didSet {
            defaults.set(shuffleEnabled, forKey: Keys.shuffle)
        }
    }

    @Published var repeatMode: RepeatMode {
        didSet {
            defaults.set(repeatMode.rawValue, forKey: Keys.repeatMode)
        }
    }

    @Published var didRunInitialMusicScan: Bool {
        didSet {
            defaults.set(didRunInitialMusicScan, forKey: Keys.didRunInitialMusicScan)
        }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let language = "settings.language"
        static let pushNotifications = "settings.push_notifications"
        static let autoPlay = "settings.auto_play"
        static let shuffle = "settings.shuffle"
        static let repeatMode = "settings.repeat_mode"
        static let didRunInitialMusicScan = "settings.did_run_initial_music_scan"
        static let playbackSnapshot = "settings.playback_snapshot"
        static let importedTracks = "settings.imported_tracks"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if
            let rawLanguage = defaults.string(forKey: Keys.language),
            let savedLanguage = AppLanguage(rawValue: rawLanguage)
        {
            language = savedLanguage
        } else {
            language = .vietnamese
        }

        pushNotificationsEnabled = defaults.object(forKey: Keys.pushNotifications) as? Bool ?? true
        autoPlayEnabled = defaults.object(forKey: Keys.autoPlay) as? Bool ?? true
        shuffleEnabled = defaults.object(forKey: Keys.shuffle) as? Bool ?? false

        if
            let rawRepeat = defaults.string(forKey: Keys.repeatMode),
            let savedRepeat = RepeatMode(rawValue: rawRepeat)
        {
            repeatMode = savedRepeat
        } else {
            repeatMode = .all
        }

        didRunInitialMusicScan = defaults.object(forKey: Keys.didRunInitialMusicScan) as? Bool ?? false
    }

    func savePlaybackSnapshot(_ snapshot: PlaybackSnapshot?) {
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Keys.playbackSnapshot)
        } else {
            defaults.removeObject(forKey: Keys.playbackSnapshot)
        }
    }

    func loadPlaybackSnapshot() -> PlaybackSnapshot? {
        guard
            let data = defaults.data(forKey: Keys.playbackSnapshot),
            let snapshot = try? JSONDecoder().decode(PlaybackSnapshot.self, from: data)
        else {
            return nil
        }
        return snapshot
    }

    func saveImportedTracks(_ tracks: [ImportedTrackSnapshot]) {
        if let data = try? JSONEncoder().encode(tracks) {
            defaults.set(data, forKey: Keys.importedTracks)
        } else {
            defaults.removeObject(forKey: Keys.importedTracks)
        }
    }

    func loadImportedTracks() -> [ImportedTrackSnapshot] {
        guard
            let data = defaults.data(forKey: Keys.importedTracks),
            let tracks = try? JSONDecoder().decode([ImportedTrackSnapshot].self, from: data)
        else {
            return []
        }
        return tracks
    }
}
