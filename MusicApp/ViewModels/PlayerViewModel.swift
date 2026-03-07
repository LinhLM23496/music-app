import Foundation
import Combine

@MainActor
final class PlayerViewModel: ObservableObject {
    let appVM: MusicLibraryViewModel
    private var cancellables = Set<AnyCancellable>()

    init(appVM: MusicLibraryViewModel) {
        self.appVM = appVM
        appVM.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var currentSong: Song? { appVM.currentSong }
    var shouldShowMiniPlayer: Bool { appVM.shouldShowMiniPlayer }
    var isPlaying: Bool { appVM.isPlaying }
    var playbackProgress: PlaybackProgressState { appVM.playbackProgress }

    var playerSheetSong: Song? {
        get { appVM.playerSheetSong }
        set { appVM.playerSheetSong = newValue }
    }

    func localized(_ key: String) -> String { appVM.localized(key) }
    func localizedSongTitle(_ song: Song) -> String { appVM.localizedSongTitle(song) }

    func togglePlayPause() { appVM.togglePlayPause() }
    func nextSong() { appVM.nextSong() }
    func hideMiniPlayer() { appVM.hideMiniPlayer() }
    func stopAndResetPlayback() { appVM.stopAndResetPlayback() }
    func presentPlayer(for song: Song) { appVM.presentPlayer(for: song) }
}
