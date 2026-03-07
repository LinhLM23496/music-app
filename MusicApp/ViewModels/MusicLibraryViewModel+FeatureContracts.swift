import Foundation
import Combine

extension MusicLibraryViewModel {
    var changePublisher: AnyPublisher<Void, Never> {
        objectWillChange
            .map { _ in () }
            .eraseToAnyPublisher()
    }
}

extension MusicLibraryViewModel: HomeFeatureControlling {}
extension MusicLibraryViewModel: PlaylistFeatureControlling {}
extension MusicLibraryViewModel: InfoFeatureControlling {}
extension MusicLibraryViewModel: PlayerFeatureControlling {}
