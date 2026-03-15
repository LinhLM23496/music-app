//
//  AVPlayerEngine.swift
//  MusicApp
//
//  Created by Linh Le on 14/3/26.
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class AVPlayerEngine: PlayerEngine {
    @Published private var playerState: PlayerState = .empty
    @Published private(set) var lastError: PlayerError?
    
    var statePublisher: AnyPublisher<PlayerState, Never> {
        $playerState.eraseToAnyPublisher()
    }
    
    private let didFinishSubject = PassthroughSubject<Void, Never>()
    
    var didFinishPublisher: AnyPublisher<Void, Never> {
        didFinishSubject.eraseToAnyPublisher()
    }
    
    var currentState: PlayerState {
        playerState
    }
    
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var didPlayToEndObserver: NSObjectProtocol?
    
    func load(url: URL, autoPlay: Bool, rate: Float) {
        cleanup()
        
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        
        playerState = PlayerState(
            currentTime: 0,
            duration: 0,
            progress: 0,
            isPlaying: false,
            hasLoadedItem: true
        )
        
        observe(player: player, item: item)
        
        if autoPlay {
            play(rate: rate)
        } else {
            player.pause()
            playerState.isPlaying = false
        }
    }
    
    func play(rate: Float) {
        guard let player = player else { return }
        configureAudioSessionForPlayback()
        player.playImmediately(atRate: rate)
        playerState.isPlaying = true
    }
    
    func pause() {
        player?.pause()
        playerState.isPlaying = false
    }
    
    func seek(to seconds: Float) {
        guard let player = player else { return }
        
        let clampedSeconds = max(seconds, 0)
        let targetTime = CMTime(value: Int64(clampedSeconds * 1000), timescale: 1000)
        
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        playerState.currentTime = clampedSeconds
        if playerState.duration > 0 {
            playerState.progress = min(max(clampedSeconds / playerState.duration, 0), 1)
        }
    }
    
    func stop() {
        player?.pause()
        cleanup()
        playerState = .empty
    }
    
    private func observe(player: AVPlayer, item: AVPlayerItem) {
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let currentTime = Float(max(0, time.seconds))
                let runtimeDuration = Float(item.duration.seconds)
                let duration = runtimeDuration.isFinite && runtimeDuration > 0
                    ? runtimeDuration
                    : self.playerState.duration
                let progress = duration > 0
                    ? min(max(currentTime / duration, 0), 1)
                    : self.playerState.progress

                self.playerState = PlayerState(
                    currentTime: currentTime,
                    duration: duration,
                    progress: progress,
                    isPlaying: player.rate > 0,
                    hasLoadedItem: true
                )
            }
        }

        didPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.playerState.isPlaying = false
                self.playerState.currentTime = self.playerState.duration
                self.playerState.progress = 1
                // khi end thì gửi action cho ai subject
                self.didFinishSubject.send(())
            }
        }
    }
    
    private func configureAudioSessionForPlayback() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            lastError = .audioSessionActivationFailed
            print("Failed to activate audio session: \(error)")
        }
    }
    
    private func cleanup() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        
        if let observer = didPlayToEndObserver {
            NotificationCenter.default.removeObserver(observer)
            didPlayToEndObserver = nil
        }
        
        player = nil
    }
}
