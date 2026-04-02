import Foundation
import Combine

struct ImportedTrackSnapshot: Codable {
    let filePath: String
    let fileName: String
    let displayName: String
    let duration: Double
    let importedAt: Date?
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
