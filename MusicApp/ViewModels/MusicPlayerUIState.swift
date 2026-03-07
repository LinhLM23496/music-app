import Foundation
import Combine

final class MusicPlayerUIState: ObservableObject {
    @Published var displaySong: Song
    @Published var language: AppLanguage
    @Published var isPlaying: Bool
    @Published var isShuffleOn: Bool
    @Published var repeatMode: RepeatMode
    @Published var playbackSpeed: Double
    @Published var queueSongs: [Song]
    @Published var queueIndex: Int
    @Published var favoriteSongIDs: Set<UUID>
    @Published var sleepTimerText: String?

    let playbackProgress: PlaybackProgressState

    private var cancellables = Set<AnyCancellable>()
    private var isBound = false

    init(song: Song, source: any PlayerFeatureControlling) {
        displaySong = source.currentSong ?? song
        language = source.language
        isPlaying = source.isPlaying
        isShuffleOn = source.isShuffleOn
        repeatMode = source.repeatMode
        playbackSpeed = source.playbackSpeed
        queueSongs = source.queueSongs
        queueIndex = source.queueIndex
        favoriteSongIDs = source.favoriteSongIDs
        sleepTimerText = source.sleepTimerText
        playbackProgress = source.playbackProgress
    }

    func bind(to source: any PlayerFeatureControlling) {
        guard !isBound else { return }
        isBound = true

        source.languagePublisher
            .removeDuplicates()
            .assign(to: &$language)

        source.changePublisher
            .sink { [weak self] _ in
                guard let self else { return }
                self.isPlaying = source.isPlaying
                self.isShuffleOn = source.isShuffleOn
                self.repeatMode = source.repeatMode
                self.playbackSpeed = source.playbackSpeed
                self.queueSongs = source.queueSongs
                self.queueIndex = source.queueIndex
                self.sleepTimerText = source.sleepTimerText
                self.syncDisplaySongFromQueue()
            }
            .store(in: &cancellables)

        source.favoriteSongIDsPublisher
            .removeDuplicates()
            .assign(to: &$favoriteSongIDs)
    }

    private func syncDisplaySongFromQueue() {
        guard queueSongs.indices.contains(queueIndex) else { return }
        let newSong = queueSongs[queueIndex]
        if !isSameSong(displaySong, newSong) {
            displaySong = newSong
        }
    }

    private func isSameSong(_ lhs: Song, _ rhs: Song) -> Bool {
        if let lhsPath = lhs.localFilePath, let rhsPath = rhs.localFilePath {
            return lhsPath == rhsPath
        }
        return lhs.id == rhs.id
    }
}
