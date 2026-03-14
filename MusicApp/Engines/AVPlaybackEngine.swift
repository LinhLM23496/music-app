//
//  AVPlaybackEngine.swift
//  MusicApp
//
//  Created by Linh Le on 14/3/26.
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class AVPlaybackEngine: PlaybackEngine {
    @Published private var state: PlaybackState = .empty
    @Published private(set) var lastError: PlaybackError?
    
    var statePublisher: AnyPublisher<PlaybackState, Never> {
        $state.eraseToAnyPublisher()
    }
    
    var currentState: PlaybackState {
        state
    }
    
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var didPlayToEndObserver: NSObjectProtocol?
    
    func load(url: URL, autoPlay: Bool, rate: Float) {
        clearup()
        
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        
        state = PlaybackState(
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
            state.isPlaying = false
        }
    }
    
    func play(rate: Float) {
        guard let player = player else { return }
        configAudioSessionForPlayback()
        player.playImmediately(atRate: rate)
        state.isPlaying = true
    }
    
    func pause() {
        player?.pause()
        state.isPlaying = false
    }
    
    func seek(to seconds: Float) {
        guard let player = player else { return }
        
        let clampedSeconds = max(seconds, 0)
        let targetTime = CMTime(value: Int64(clampedSeconds * 1000), timescale: 1000)
        
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        state.currentTime = clampedSeconds
        // caculate progress
        let duration = max(state.duration, 0.01)
        state.progress = min(max(clampedSeconds / duration, 0), 1)
    }
    
    func stop() {
        player?.pause()
        clearup()
        state = .empty
    }
    
    // subcrise observer
    // 1. update realtime currentTime, progress
    // 2. update play music complete
    private func observe(player: AVPlayer, item: AVPlayerItem) {
        // cứ mỗi 0.2 giây sẽ callback 1 lần
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)

        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval,    queue: .main) { [weak self] time in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let currentTime = Float(max(0, time.seconds))
                    let durationSeconds = Float(item.duration.seconds)
                    let duration = durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : 0
                    let progress = duration > 0 ? min(max(currentTime / duration, 0), 1) : 0

                    self.state = PlaybackState(
                        currentTime: currentTime,
                        duration: duration,
                        progress: progress,
                        isPlaying: player.rate > 0,
                        hasLoadedItem: true
                    )
                }
            }

        // lắng nghe notification của hệ thống
        // khi item phát đến cuối, block này chạy
        didPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.state.isPlaying = false
                    self.state.currentTime = self.state.duration
                    self.state.progress = 1
                }
            }
    }
    
    // chuẩn bị audio session cho app media
    private func configAudioSessionForPlayback() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            lastError = .audioSessionActivationFailed
            print("configAudioSessionForPlayback Audio session activation failed: \(error)")
        }
    }
    
    private func clearup() {
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


