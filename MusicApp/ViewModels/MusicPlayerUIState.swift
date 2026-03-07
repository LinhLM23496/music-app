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
    @Published var sleepTimerText: String?

    let playbackProgress: PlaybackProgressState

    private var cancellables = Set<AnyCancellable>()
    private var isBound = false

    init(song: Song, source: PlayerViewModel) {
        displaySong = source.currentSong ?? song
        language = source.language
        isPlaying = source.isPlaying
        isShuffleOn = source.isShuffleOn
        repeatMode = source.repeatMode
        playbackSpeed = source.playbackSpeed
        queueSongs = source.queueSongs
        queueIndex = source.queueIndex
        sleepTimerText = source.sleepTimerText
        playbackProgress = source.playbackProgress
    }

    func bind(to source: PlayerViewModel) {
        guard !isBound else { return }
        isBound = true

        source.languagePublisher
            .removeDuplicates()
            .assign(to: &$language)

        source.$isPlaying
            .removeDuplicates()
            .assign(to: &$isPlaying)

        source.$isShuffleOn
            .removeDuplicates()
            .assign(to: &$isShuffleOn)

        source.$repeatMode
            .removeDuplicates()
            .assign(to: &$repeatMode)

        source.$playbackSpeed
            .removeDuplicates()
            .assign(to: &$playbackSpeed)

        source.$queueSongs
            .sink { [weak self] queue in
                self?.queueSongs = queue
                self?.syncDisplaySongFromQueue()
            }
            .store(in: &cancellables)

        source.$queueIndex
            .removeDuplicates()
            .sink { [weak self] index in
                self?.queueIndex = index
                self?.syncDisplaySongFromQueue()
            }
            .store(in: &cancellables)

        source.$sleepTimerText
            .removeDuplicates()
            .assign(to: &$sleepTimerText)
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
