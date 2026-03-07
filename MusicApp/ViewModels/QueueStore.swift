import Foundation
import Combine

@MainActor
final class QueueStore: ObservableObject {
    enum PreviousAction {
        case seekToStart
        case play(Song)
        case none
    }

    enum NextAction {
        case play(Song)
        case stopAtEnd
    }

    @Published var queueSongs: [Song]
    @Published var queueIndex: Int
    @Published var isShuffleOn: Bool
    @Published var repeatMode: RepeatMode

    init(queueSongs: [Song], queueIndex: Int, isShuffleOn: Bool, repeatMode: RepeatMode) {
        self.queueSongs = queueSongs
        self.queueIndex = queueIndex
        self.isShuffleOn = isShuffleOn
        self.repeatMode = repeatMode
    }

    var currentSong: Song? {
        guard queueSongs.indices.contains(queueIndex) else { return nil }
        return queueSongs[queueIndex]
    }

    func setQueue(current song: Song, in queue: [Song], isSameTrack: (Song, Song) -> Bool) -> Song {
        let safeQueue = queue.isEmpty ? [song] : queue
        queueSongs = safeQueue

        if let index = safeQueue.firstIndex(where: { isSameTrack($0, song) }) {
            queueIndex = index
        } else {
            queueSongs.insert(song, at: 0)
            queueIndex = 0
        }

        return queueSongs[queueIndex]
    }

    func song(at index: Int) -> Song? {
        guard queueSongs.indices.contains(index) else { return nil }
        return queueSongs[index]
    }

    func reset() {
        queueSongs = []
        queueIndex = 0
    }

    func previousAction(currentTime: Double) -> PreviousAction {
        guard !queueSongs.isEmpty else { return .none }

        if currentTime > 3 {
            return .seekToStart
        }

        if isShuffleOn, queueSongs.count > 1 {
            var randomIndex = queueIndex
            while randomIndex == queueIndex {
                randomIndex = Int.random(in: 0..<queueSongs.count)
            }
            return .play(queueSongs[randomIndex])
        }

        let previousIndex = queueIndex - 1
        if previousIndex >= 0 {
            return .play(queueSongs[previousIndex])
        }

        if repeatMode == .all, let last = queueSongs.indices.last {
            return .play(queueSongs[last])
        }

        return .seekToStart
    }

    func nextAction(autoTriggered: Bool) -> NextAction {
        guard !queueSongs.isEmpty else { return .stopAtEnd }

        if isShuffleOn, queueSongs.count > 1 {
            var randomIndex = queueIndex
            while randomIndex == queueIndex {
                randomIndex = Int.random(in: 0..<queueSongs.count)
            }
            return .play(queueSongs[randomIndex])
        }

        let nextIndex = queueIndex + 1
        if queueSongs.indices.contains(nextIndex) {
            return .play(queueSongs[nextIndex])
        }

        if repeatMode == .all {
            return .play(queueSongs[0])
        }

        if repeatMode == .off || autoTriggered {
            return .stopAtEnd
        }

        return .stopAtEnd
    }
}
