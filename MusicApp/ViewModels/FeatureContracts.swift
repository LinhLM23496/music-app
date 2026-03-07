import Foundation
import Combine

@MainActor
protocol FeatureControlling: AnyObject {
    var changePublisher: AnyPublisher<Void, Never> { get }
}

@MainActor
protocol HomeFeatureControlling: FeatureControlling {
    var featuredSongs: [Song] { get }
    var favoriteSongs: [Song] { get }
    var deviceTracks: [LocalAudioTrack] { get }
    func localized(_ key: String) -> String
    func localizedSongTitle(_ song: Song) -> String
    func play(song: Song)
    func presentPlayer(for song: Song)
    func refreshDeviceTracks()
    func songForDeviceTrack(_ track: LocalAudioTrack) -> Song
    func importAudioFiles(from urls: [URL], completion: @escaping (MusicLibraryViewModel.ImportResult) -> Void)
    func importSummaryText(_ result: MusicLibraryViewModel.ImportResult) -> String
}

@MainActor
protocol PlaylistFeatureControlling: FeatureControlling {
    var playlists: [Playlist] { get }
    var songs: [Song] { get }
    var favoriteSongIDs: Set<UUID> { get }
    func localized(_ key: String) -> String
    func localizedSongTitle(_ song: Song) -> String
    func localizedPlaylistName(_ playlist: Playlist) -> String
    func songsCountText(_ count: Int) -> String
    func songs(in playlist: Playlist) -> [Song]
    func createPlaylist(name: String)
    func deletePlaylist(at offsets: IndexSet)
    func addSong(_ song: Song, to playlistID: UUID)
}

@MainActor
protocol InfoFeatureControlling: FeatureControlling {
    var user: AppUser { get }
    var musicStorageFolderStatus: String { get }
    var musicStorageFolderPath: String { get }
    func localized(_ key: String) -> String
    func refreshDeviceTracks()
    func musicStorageURL() -> URL?
}

@MainActor
protocol PlayerFeatureControlling: FeatureControlling {
    var currentSong: Song? { get }
    var shouldShowMiniPlayer: Bool { get }
    var isPlaying: Bool { get }
    var playbackProgress: PlaybackProgressState { get }
    var playerSheetSong: Song? { get set }
    func localized(_ key: String) -> String
    func localizedSongTitle(_ song: Song) -> String
    func togglePlayPause()
    func nextSong()
    func hideMiniPlayer()
    func stopAndResetPlayback()
    func presentPlayer(for song: Song)

    // Player screen actions.
    var language: AppLanguage { get }
    var favoriteSongIDs: Set<UUID> { get }
    var isShuffleOn: Bool { get set }
    var repeatMode: RepeatMode { get }
    var playbackSpeed: Double { get }
    var queueSongs: [Song] { get }
    var queueIndex: Int { get }
    var sleepTimerRemaining: Double? { get }
    var languagePublisher: AnyPublisher<AppLanguage, Never> { get }
    var favoriteSongIDsPublisher: AnyPublisher<Set<UUID>, Never> { get }
    func isCurrentSong(_ song: Song) -> Bool
    func playFromQueue(index: Int)
    func play(song: Song)
    func previousSong()
    func cycleRepeatMode()
    func setPlaybackSpeed(_ speed: Double)
    func pauseLiveProgressUpdates(seconds: Double)
    func resumeLiveProgressUpdates()
    func cancelSleepTimer()
    func setSleepTimer(minutes: Double?)
    func seek(to normalizedProgress: Double)
    var sleepTimerText: String? { get }
    func toggleFavorite(for song: Song)
}
