import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english
    case vietnamese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .vietnamese:
            return "Tiếng Việt"
        }
    }

    var code: String {
        switch self {
        case .english:
            return "en"
        case .vietnamese:
            return "vi"
        }
    }
}

struct Song: Identifiable, Hashable {
    let id: UUID
    let titleEN: String
    let titleVI: String
    let artist: String
    let album: String
    let coverSymbol: String
    let audioFileName: String
    let localFilePath: String?
    let duration: Double
    let accent: Color
}

struct Playlist: Identifiable {
    let id: UUID
    var nameEN: String
    var nameVI: String
    var coverSymbol: String
    var songIDs: [UUID]
}

struct LocalAudioTrack: Identifiable, Hashable {
    let id: URL
    let url: URL
    let fileName: String
    let displayName: String
    let duration: Double
}

enum RepeatMode: String, CaseIterable {
    case off
    case all
    case one

    var icon: String {
        switch self {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    var localizationKey: String {
        switch self {
        case .off:
            return "repeat.off"
        case .all:
            return "repeat.all"
        case .one:
            return "repeat.one"
        }
    }
}

extension Song {
    func localizedTitle(for language: AppLanguage) -> String {
        language == .english ? titleEN : titleVI
    }
}

extension Playlist {
    func localizedName(for language: AppLanguage) -> String {
        language == .english ? nameEN : nameVI
    }
}
