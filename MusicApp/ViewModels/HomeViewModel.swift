import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    let source: any HomeFeatureControlling
    private var cancellables = Set<AnyCancellable>()

    init(source: any HomeFeatureControlling) {
        self.source = source
        source.changePublisher
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var featuredSongs: [Song] { source.featuredSongs }
    var favoriteSongs: [Song] { source.favoriteSongs }
    var deviceTracks: [LocalAudioTrack] { source.deviceTracks }

    func localized(_ key: String) -> String { source.localized(key) }
    func localizedSongTitle(_ song: Song) -> String { source.localizedSongTitle(song) }
    func play(song: Song) { source.play(song: song) }
    func presentPlayer(for song: Song) { source.presentPlayer(for: song) }
    func refreshDeviceTracks() { source.refreshDeviceTracks() }
    func songForDeviceTrack(_ track: LocalAudioTrack) -> Song { source.songForDeviceTrack(track) }
    func importAudioFiles(from urls: [URL], completion: @escaping (HomeImportResult) -> Void) {
        source.importAudioFiles(from: urls, completion: completion)
    }
    func importSummaryText(_ result: HomeImportResult) -> String {
        source.importSummaryText(result)
    }
}
