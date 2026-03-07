import Foundation
import AVFoundation
import Combine

@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var isPlaying = false
    let progress = PlaybackProgressState()

    var onDidFinish: (() -> Void)?

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var didPlayToEndObserver: NSObjectProtocol?
    private var pauseLiveUpdatesUntil: Date = .distantPast

    var currentTime: Double {
        progress.currentTime
    }

    var hasLoadedItem: Bool {
        player != nil
    }

    func load(song: Song, audioURL: URL?, autoPlay: Bool, playbackRate: Double) {
        cleanup()

        guard let audioURL else {
            isPlaying = false
            progress.progress = 0
            progress.currentTime = 0
            progress.duration = song.duration
            return
        }

        let item = AVPlayerItem(url: audioURL)
        let player = AVPlayer(playerItem: item)
        self.player = player
        observePlayer(player: player, item: item, fallbackDuration: song.duration)

        if autoPlay {
            configureAudioSessionForPlayback()
            player.playImmediately(atRate: Float(playbackRate))
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }
    }

    func resume(rate: Double) {
        guard let player else { return }
        configureAudioSessionForPlayback()
        player.playImmediately(atRate: Float(rate))
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func setRateIfPlaying(_ rate: Double) {
        guard isPlaying else { return }
        player?.rate = Float(rate)
    }

    func seek(to seconds: Double) {
        guard let player else { return }

        let clampedSeconds = max(seconds, 0)
        let target = CMTime(seconds: clampedSeconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        progress.currentTime = clampedSeconds

        let duration = max(progress.duration, 0.001)
        progress.progress = min(max(clampedSeconds / duration, 0), 1)
    }

    func stopAndReset(fallbackDuration: Double) {
        pause()

        let duration = progress.duration > 0 ? progress.duration : max(fallbackDuration, 1)
        player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        progress.currentTime = 0
        progress.progress = 0
        progress.duration = max(duration, 1)
    }

    func stopAndClear() {
        pause()
        cleanup()
        progress.progress = 0
        progress.currentTime = 0
        progress.duration = 1
    }

    func stopAtEnd() {
        pause()
        progress.progress = 1
        progress.currentTime = progress.duration
    }

    func pauseLiveProgressUpdates(seconds: Double) {
        pauseLiveUpdatesUntil = Date().addingTimeInterval(seconds)
    }

    func resumeLiveProgressUpdates() {
        pauseLiveUpdatesUntil = .distantPast
    }

    private func configureAudioSessionForPlayback() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            // Keep app functional even if session activation fails on specific routes/devices.
        }
    }

    private func observePlayer(player: AVPlayer, item: AVPlayerItem, fallbackDuration: Double) {
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if Date() < self.pauseLiveUpdatesUntil { return }

                let seconds = time.seconds
                if seconds.isFinite {
                    self.progress.currentTime = max(0, seconds)
                }

                let duration = item.duration.seconds
                if duration.isFinite, duration > 0 {
                    self.progress.duration = duration
                } else {
                    self.progress.duration = fallbackDuration
                }

                let total = self.progress.duration > 0 ? self.progress.duration : fallbackDuration
                self.progress.progress = min(max(self.progress.currentTime / max(total, 0.001), 0), 1)
            }
        }

        didPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onDidFinish?()
            }
        }
    }

    private func cleanup() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }

        if let observer = didPlayToEndObserver {
            NotificationCenter.default.removeObserver(observer)
            didPlayToEndObserver = nil
        }

        player = nil
    }
}
