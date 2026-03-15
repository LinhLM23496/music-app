import Foundation
import Combine

final class PlaybackProgressState: ObservableObject {
    @Published var progress: Float = 0
    @Published var currentTime: Float = 0
    @Published var duration: Float = 1
    
    init(progress: Float, currentTime: Float, duration: Float) {
        self.progress = progress
        self.currentTime = currentTime
        self.duration = duration
    }
}
