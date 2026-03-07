import Foundation
import Combine

@MainActor
final class PlayerViewModel: ObservableObject {
    let source: any PlayerFeatureControlling
    private var cancellables = Set<AnyCancellable>()

    init(source: any PlayerFeatureControlling) {
        self.source = source
        source.changePublisher
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var currentSong: Song? { source.currentSong }
    var shouldShowMiniPlayer: Bool { source.shouldShowMiniPlayer }
    var isPlaying: Bool { source.isPlaying }
    var playbackProgress: PlaybackProgressState { source.playbackProgress }

    var playerSheetSong: Song? {
        get { source.playerSheetSong }
        set { source.playerSheetSong = newValue }
    }

    func localized(_ key: String) -> String { source.localized(key) }
    func localizedSongTitle(_ song: Song) -> String { source.localizedSongTitle(song) }

    func togglePlayPause() { source.togglePlayPause() }
    func nextSong() { source.nextSong() }
    func hideMiniPlayer() { source.hideMiniPlayer() }
    func stopAndResetPlayback() { source.stopAndResetPlayback() }
    func presentPlayer(for song: Song) { source.presentPlayer(for: song) }
}
