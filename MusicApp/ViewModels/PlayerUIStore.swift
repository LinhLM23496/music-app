import Foundation
import Combine

@MainActor
final class PlayerUIStore: ObservableObject {
    @Published var isMiniPlayerHidden = false
    @Published var playerSheetSong: Song?
}
