import Foundation
import Combine

enum Localizer {
    static func string(_ key: String, language: AppLanguage) -> String {
        let code = language.code
        guard
            let path = Bundle.main.path(forResource: code, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return NSLocalizedString(key, comment: "")
        }

        return NSLocalizedString(key, tableName: nil, bundle: bundle, value: key, comment: "")
    }
}

protocol LocalizationProviding {
    func string(_ key: String, language: AppLanguage) -> String
}

struct BundleLocalizationService: LocalizationProviding {
    func string(_ key: String, language: AppLanguage) -> String {
        Localizer.string(key, language: language)
    }
}

@MainActor
final class LocalizationViewModel: ObservableObject {
    @Published private(set) var language: AppLanguage

    private let settingsStore: AppSettingsStore
    private let service: LocalizationProviding
    private var cancellables = Set<AnyCancellable>()

    init(
        settingsStore: AppSettingsStore,
        service: LocalizationProviding
    ) {
        self.settingsStore = settingsStore
        self.service = service
        language = settingsStore.language
        bindLanguage()
    }

    func t(_ key: String) -> String {
        service.string(key, language: language)
    }

    func songTitle(_ song: Song) -> String {
        song.localizedTitle(for: language)
    }

    func playlistName(_ playlist: Playlist) -> String {
        playlist.localizedName(for: language)
    }

    func songsCountText(_ count: Int) -> String {
        String(format: t("songs.count"), count)
    }

    private func bindLanguage() {
        settingsStore.$language
            .removeDuplicates()
            .assign(to: &$language)
    }
}
