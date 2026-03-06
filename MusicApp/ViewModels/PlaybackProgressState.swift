import Foundation
import Combine

final class PlaybackProgressState: ObservableObject {
    @Published var progress: Double = 0
    @Published var currentTime: Double = 0
    @Published var duration: Double = 1
}
