import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
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

    var featuredSongs: [Song] { appVM.featuredSongs }
    var favoriteSongs: [Song] { appVM.favoriteSongs }
    var deviceTracks: [LocalAudioTrack] { appVM.deviceTracks }

    func localized(_ key: String) -> String { appVM.localized(key) }
    func localizedSongTitle(_ song: Song) -> String { appVM.localizedSongTitle(song) }
    func play(song: Song) { appVM.play(song: song) }
    func presentPlayer(for song: Song) { appVM.presentPlayer(for: song) }
    func refreshDeviceTracks() { appVM.refreshDeviceTracks() }
    func songForDeviceTrack(_ track: LocalAudioTrack) -> Song { appVM.songForDeviceTrack(track) }
    func importAudioFiles(from urls: [URL], completion: @escaping (MusicLibraryViewModel.ImportResult) -> Void) {
        appVM.importAudioFiles(from: urls, completion: completion)
    }
    func importSummaryText(_ result: MusicLibraryViewModel.ImportResult) -> String {
        appVM.importSummaryText(result)
    }
}
