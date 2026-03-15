import Foundation
import MediaPlayer
import UIKit

struct RemotePlaybackCommandHandlers {
    let onPlay: () -> Bool
    let onPause: () -> Bool
    let onNext: () -> Bool
    let onPrevious: () -> Bool
    let onChangePosition: (Double) -> Bool
}

@MainActor
protocol NowPlayingControlling: AnyObject {
    func configureRemoteCommands(handlers: RemotePlaybackCommandHandlers)
    func updateNowPlaying(
        title: String,
        artist: String,
        album: String,
        duration: Double,
        elapsedTime: Double,
        playbackRate: Double,
        defaultRate: Double,
        artwork: UIImage?
    )
    func clearNowPlaying()
}

@MainActor
final class SystemNowPlayingService: NowPlayingControlling {
    private let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
    private let remoteCommandCenter = MPRemoteCommandCenter.shared()
    private var didConfigureRemoteCommands = false
    private var hasPublishedNowPlayingInfo = false

    func configureRemoteCommands(handlers: RemotePlaybackCommandHandlers) {
        guard !didConfigureRemoteCommands else { return }
        didConfigureRemoteCommands = true

        remoteCommandCenter.playCommand.isEnabled = true
        remoteCommandCenter.pauseCommand.isEnabled = true
        remoteCommandCenter.nextTrackCommand.isEnabled = true
        remoteCommandCenter.previousTrackCommand.isEnabled = true
        remoteCommandCenter.changePlaybackPositionCommand.isEnabled = true

        remoteCommandCenter.playCommand.addTarget { _ in
            handlers.onPlay() ? .success : .commandFailed
        }
        remoteCommandCenter.pauseCommand.addTarget { _ in
            handlers.onPause() ? .success : .commandFailed
        }
        remoteCommandCenter.nextTrackCommand.addTarget { _ in
            handlers.onNext() ? .success : .commandFailed
        }
        remoteCommandCenter.previousTrackCommand.addTarget { _ in
            handlers.onPrevious() ? .success : .commandFailed
        }
        remoteCommandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            return handlers.onChangePosition(positionEvent.positionTime) ? .success : .commandFailed
        }
    }

    func updateNowPlaying(
        title: String,
        artist: String,
        album: String,
        duration: Double,
        elapsedTime: Double,
        playbackRate: Double,
        defaultRate: Double,
        artwork: UIImage?
    ) {
        var info = nowPlayingInfoCenter.nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = artist
        info[MPMediaItemPropertyAlbumTitle] = album
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = defaultRate
        if let artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        nowPlayingInfoCenter.nowPlayingInfo = info
        hasPublishedNowPlayingInfo = true
    }

    func clearNowPlaying() {
        guard hasPublishedNowPlayingInfo || nowPlayingInfoCenter.nowPlayingInfo != nil else {
            return
        }
        nowPlayingInfoCenter.nowPlayingInfo = nil
        hasPublishedNowPlayingInfo = false
    }
}
