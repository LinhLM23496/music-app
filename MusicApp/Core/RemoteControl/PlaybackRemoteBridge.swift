import Foundation

struct PlaybackRemoteActions {
    let onPlay: () -> Bool
    let onPause: () -> Bool
    let onNext: () -> Bool
    let onPrevious: () -> Bool
    let onSeekToTime: (Double) -> Bool
}

@MainActor
final class PlaybackRemoteBridge {
    private let service: NowPlayingControlling
    private let actions: PlaybackRemoteActions

    init(service: NowPlayingControlling, actions: PlaybackRemoteActions) {
        self.service = service
        self.actions = actions
    }

    func configure() {
        service.configureRemoteCommands(
            handlers: RemotePlaybackCommandHandlers(
                onPlay: actions.onPlay,
                onPause: actions.onPause,
                onNext: actions.onNext,
                onPrevious: actions.onPrevious,
                onChangePosition: actions.onSeekToTime
            )
        )
    }
}
