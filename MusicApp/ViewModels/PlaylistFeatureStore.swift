import Foundation
import Combine

@MainActor
final class PlaylistFeatureStore: ObservableObject, PlaylistFeatureControlling {
    private let settingsStore: AppSettingsStore
    private let libraryStore: LibraryStore
    private let playlistStore: PlaylistStore
    private let playlistUseCases = PlaylistUseCases()

    init(
        settingsStore: AppSettingsStore,
        libraryStore: LibraryStore,
        playlistStore: PlaylistStore
    ) {
        self.settingsStore = settingsStore
        self.libraryStore = libraryStore
        self.playlistStore = playlistStore
    }

    var changePublisher: AnyPublisher<Void, Never> {
        objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }

    var playlists: [Playlist] { playlistStore.playlists }
    var songs: [Song] { libraryStore.songs }
    var favoriteSongIDs: Set<UUID> { libraryStore.favoriteSongIDs }

    func localized(_ key: String) -> String {
        Localizer.string(key, language: settingsStore.language)
    }

    func localizedSongTitle(_ song: Song) -> String {
        song.localizedTitle(for: settingsStore.language)
    }

    func localizedPlaylistName(_ playlist: Playlist) -> String {
        playlist.localizedName(for: settingsStore.language)
    }

    func songsCountText(_ count: Int) -> String {
        String(format: localized("songs.count"), count)
    }

    func songs(in playlist: Playlist) -> [Song] {
        playlistUseCases.songs(in: playlist, allSongs: songs)
    }

    func createPlaylist(name: String) {
        playlistStore.playlists = playlistUseCases.createPlaylist(name: name, in: playlists)
    }

    func deletePlaylist(at offsets: IndexSet) {
        playlistStore.playlists = playlistUseCases.deletePlaylists(at: offsets, in: playlists)
    }

    func addSong(_ song: Song, to playlistID: UUID) {
        playlistStore.playlists = playlistUseCases.addSong(song, to: playlistID, in: playlists)
    }
}
