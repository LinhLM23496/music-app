import Foundation

@MainActor
final class PlaybackNowPlayingAdapter {
    private let service: NowPlayingControlling

    init(service: NowPlayingControlling) {
        self.service = service
    }

    func publish(song: Song, playerState: PlayerState) {
        service.updateNowPlaying(
            title: song.titleEN,
            artist: song.artist,
            album: song.album,
            duration: Double(playerState.duration),
            elapsedTime: Double(playerState.currentTime),
            playbackRate: playerState.isPlaying ? 1.0 : 0.0,
            defaultRate: 1.0,
            artwork: NowPlayingArtworkRenderer.image(for: song)
        )
    }

    func clear() {
        service.clearNowPlaying()
    }
}
