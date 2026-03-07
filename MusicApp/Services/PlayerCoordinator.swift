import Foundation

@MainActor
final class PlayerCoordinator {
    private let queueStore: QueueStore
    private let playbackController: PlaybackController
    private let snapshotStore: PlaybackSnapshotStore
    private let isSameTrack: (Song?, Song?) -> Bool
    private let suggestedQueue: (Song) -> [Song]
    private let audioURLForSong: (Song) -> URL?

    private(set) var activeSong: Song?
    private(set) var hasPlaybackSession = false
    private(set) var isMiniPlayerHidden = false
    private var lastPersistedSnapshotSecond: Int = -1

    init(
        queueStore: QueueStore,
        playbackController: PlaybackController,
        snapshotStore: PlaybackSnapshotStore,
        isSameTrack: @escaping (Song?, Song?) -> Bool,
        suggestedQueue: @escaping (Song) -> [Song],
        audioURLForSong: @escaping (Song) -> URL?
    ) {
        self.queueStore = queueStore
        self.playbackController = playbackController
        self.snapshotStore = snapshotStore
        self.isSameTrack = isSameTrack
        self.suggestedQueue = suggestedQueue
        self.audioURLForSong = audioURLForSong
        self.activeSong = queueStore.currentSong
    }

    var currentSongID: UUID? {
        activeSong?.id
    }

    var currentSong: Song? {
        activeSong
    }

    func play(song: Song, playbackSpeed: Double) {
        if resumeIfCurrentSong(song, playbackSpeed: playbackSpeed) {
            return
        }
        play(song: song, in: suggestedQueue(song), playbackSpeed: playbackSpeed)
    }

    func play(song: Song, in queue: [Song], playbackSpeed: Double) {
        if resumeIfCurrentSong(song, playbackSpeed: playbackSpeed) {
            return
        }

        let selectedSong = queueStore.setQueue(current: song, in: queue, isSameTrack: { [isSameTrack] lhs, rhs in
            isSameTrack(lhs, rhs)
        })
        activeSong = selectedSong
        hasPlaybackSession = true
        isMiniPlayerHidden = false
        loadAndPlay(song: selectedSong, playbackSpeed: playbackSpeed)
        persistPlaybackSnapshotForCurrentTrack(position: 0)
    }

    func playFromQueue(index: Int, playbackSpeed: Double) {
        guard let song = queueStore.song(at: index) else { return }
        play(song: song, in: queueStore.queueSongs, playbackSpeed: playbackSpeed)
    }

    func togglePlayPause(playbackSpeed: Double) {
        if !playbackController.hasLoadedItem {
            if let song = currentSong {
                loadAndPlay(song: song, playbackSpeed: playbackSpeed)
            }
            return
        }

        if playbackController.isPlaying {
            playbackController.pause()
        } else {
            playbackController.resume(rate: playbackSpeed)
        }
        persistPlaybackSnapshotForCurrentTrack()
    }

    func stopAndResetPlayback(fallbackDuration: Double) {
        playbackController.stopAndReset(fallbackDuration: fallbackDuration)
        persistPlaybackSnapshotForCurrentTrack(position: 0)
    }

    func stopPlaybackAndHideMiniPlayer() {
        playbackController.stopAndClear()
        activeSong = nil
        hasPlaybackSession = false
        isMiniPlayerHidden = false
        queueStore.reset()
        snapshotStore.clear()
    }

    func seek(to normalizedProgress: Double, fallbackDuration: Double) {
        let duration = playbackController.progress.duration > 0 ? playbackController.progress.duration : fallbackDuration
        let clamped = min(max(normalizedProgress, 0), 1)
        let seconds = duration * clamped
        playbackController.seek(to: seconds)
        persistPlaybackSnapshotForCurrentTrack(position: seconds)
    }

    func previousSong(playbackSpeed: Double) {
        switch queueStore.previousAction(currentTime: playbackController.currentTime) {
        case .seekToStart:
            seek(to: 0, fallbackDuration: currentSong?.duration ?? 1)
        case .play(let song):
            play(song: song, in: queueStore.queueSongs, playbackSpeed: playbackSpeed)
        case .none:
            break
        }
    }

    func nextSong(playbackSpeed: Double, autoTriggered: Bool) {
        switch queueStore.nextAction(autoTriggered: autoTriggered) {
        case .play(let song):
            play(song: song, in: queueStore.queueSongs, playbackSpeed: playbackSpeed)
        case .stopAtEnd:
            playbackController.stopAtEnd()
        }
    }

    func handleSongDidFinish(repeatMode: RepeatMode, playbackSpeed: Double) {
        if repeatMode == .one {
            playbackController.seek(to: 0)
            playbackController.resume(rate: playbackSpeed)
            return
        }

        nextSong(playbackSpeed: playbackSpeed, autoTriggered: true)
    }

    func updatePlaybackSpeed(_ speed: Double) {
        playbackController.setRateIfPlaying(speed)
    }

    func saveSnapshotNow() {
        persistPlaybackSnapshotForCurrentTrack()
    }

    func restorePlaybackSnapshotIfAvailable(
        resolveSong: (PlaybackSnapshot) -> Song?,
        playbackSpeed: Double
    ) {
        guard let snapshot = snapshotStore.load() else { return }
        guard let restoredSong = resolveSong(snapshot) else { return }

        let restoredQueue = suggestedQueue(restoredSong)
        let selectedSong = queueStore.setQueue(current: restoredSong, in: restoredQueue, isSameTrack: { [isSameTrack] lhs, rhs in
            isSameTrack(lhs, rhs)
        })

        activeSong = selectedSong
        hasPlaybackSession = true
        isMiniPlayerHidden = false

        loadAndPlay(song: selectedSong, autoPlay: false, playbackSpeed: playbackSpeed)

        let estimatedDuration = max(selectedSong.duration, 1)
        let clampedPosition = min(max(snapshot.positionSeconds, 0), estimatedDuration)
        if clampedPosition > 0 {
            playbackController.seek(to: clampedPosition)
        }
        playbackController.pause()
    }

    func handleProgressTickForSnapshotPersistence(wholeSecond: Int, currentTime: Double) {
        guard wholeSecond >= 0, wholeSecond % 5 == 0, wholeSecond != lastPersistedSnapshotSecond, hasPlaybackSession else {
            return
        }
        lastPersistedSnapshotSecond = wholeSecond
        persistPlaybackSnapshotForCurrentTrack(position: currentTime)
    }

    private func resumeIfCurrentSong(_ song: Song, playbackSpeed: Double) -> Bool {
        guard isSameTrack(currentSong, song) else { return false }

        if playbackController.isPlaying {
            return true
        }

        if playbackController.hasLoadedItem {
            playbackController.resume(rate: playbackSpeed)
            return true
        }

        loadAndPlay(song: song, playbackSpeed: playbackSpeed)
        return true
    }

    private func loadAndPlay(song: Song, autoPlay: Bool = true, playbackSpeed: Double) {
        lastPersistedSnapshotSecond = -1
        activeSong = song
        let url = audioURLForSong(song)
        playbackController.load(song: song, audioURL: url, autoPlay: autoPlay, playbackRate: playbackSpeed)
    }

    private func persistPlaybackSnapshotForCurrentTrack(position: Double? = nil) {
        let snapshotPosition = max(position ?? playbackController.currentTime, 0)
        snapshotStore.save(song: currentSong, position: snapshotPosition)
    }
}
