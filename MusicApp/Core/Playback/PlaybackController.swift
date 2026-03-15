//
//  PlaybackController.swift
//  MusicApp
//
//  Created by Linh Le on 14/3/26.
//

import Foundation
import Combine

@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var playerState: PlayerState = .empty
    @Published private(set) var currentTrackID: UUID? // id của bài ở vị trí hiện tại
    @Published private(set) var queueTrackIDs: [UUID] = []
    @Published private(set) var currentIndex: Int = 0 // đang đứng ở vị trí số mấy trong queue
    @Published private(set) var playbackSpeed: Float = 1.0
    @Published private(set) var shuffleEnabled = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var isMiniPlayerVisible = true
    @Published private(set) var isPlayerSheetVisible = false
    
    private let playerEngine: PlayerEngine
    private let contextStore: PlaybackContextStore
    private let playbackPersistence: PlaybackPersistence
    private let trackResolver: TrackResolver
    private let nowPlayingService: NowPlayingControlling
    
    private var cancellables: Set<AnyCancellable> = []
    private var hasRestoredSnapshot = false
    private var restoredStateFallback: PlayerState?
    
    init(
        playerEngine: PlayerEngine,
        contextStore: PlaybackContextStore,
        playbackPersistence: PlaybackPersistence,
        trackResolver: TrackResolver,
        nowPlayingService: NowPlayingControlling
    ) {
        self.playerEngine = playerEngine
        self.contextStore = contextStore
        self.playbackPersistence = playbackPersistence
        self.trackResolver = trackResolver
        self.nowPlayingService = nowPlayingService
        
        bindEngine()
        bindSession()
    }
    
    var currentSong: Song? {
        guard let currentTrackID else { return nil }
        return trackResolver.song(for: currentTrackID)
    }

    var currentQueueSongs: [Song] {
        queueTrackIDs.compactMap { trackResolver.song(for: $0) }
    }

    var shouldShowMiniPlayer: Bool {
        currentSong != nil && isMiniPlayerVisible
    }
    
    func play(trackID: UUID, queueTrackIDs: [UUID] = [], source: PlaybackSource) {
        let resolvedQueue = queueTrackIDs.isEmpty ? [trackID] : queueTrackIDs
        
        guard let index = resolvedQueue.firstIndex(of: trackID) else { return }
        guard let url = trackResolver.audioURL(for: trackID) else { return }

        if let context = contextStore.session,
           context.trackIDs == resolvedQueue,
           context.currentTrackID == trackID {
            currentTrackID = trackID
            self.queueTrackIDs = resolvedQueue
            currentIndex = index
            play()
            return
        }
        
        let playbackContext = PlaybackContext(
            trackIDs: resolvedQueue,
            currentIndex: index,
            source: source,
            repeatMode: repeatMode,
            shuffleEnabled: shuffleEnabled,
            speed: playbackSpeed
        )
        
        contextStore.setSession(playbackContext)
        currentTrackID = trackID
        self.queueTrackIDs = resolvedQueue
        currentIndex = index
        primePlayerStateForNewTrack(trackID: trackID, isPlaying: true)
        
        playerEngine.load(url: url, autoPlay: true, rate: playbackContext.speed)
    
        setMiniPlayerVisible(true)
        
        saveSnapshot()
        refreshNowPlaying()
    }

    func play() {
        guard let context = contextStore.session,
              let trackID = context.currentTrackID,
              let url = trackResolver.audioURL(for: trackID) else { return }

        if playerState.isPlaying {
            return
        }

        if playerState.hasLoadedItem {
            playerEngine.play(rate: context.speed)
        } else {
            playerEngine.load(url: url, autoPlay: true, rate: context.speed)
        }

        setMiniPlayerVisible(true)
        saveSnapshot()
        refreshNowPlaying()
    }

    func pause() {
        guard playerState.isPlaying else { return }
        playerEngine.pause()
        saveSnapshot()
        refreshNowPlaying()
    }
    
    func togglePlayPause() {
        if playerState.isPlaying {
            pause()
        } else {
            play()
        }
    }

    func toggleShuffle() {
        let nextValue = !shuffleEnabled
        contextStore.updateShuffleMode(nextValue)
    }

    func cycleRepeatMode() {
        let nextMode: RepeatMode
        switch repeatMode {
        case .off:
            nextMode = .all
        case .all:
            nextMode = .one
        case .one:
            nextMode = .off
        }
        contextStore.updateRepeatMode(nextMode)
    }

    func setPlaybackSpeed(_ speed: Float) {
        contextStore.updateSpeed(speed)
        if playerState.isPlaying {
            playerEngine.play(rate: speed)
        }
        saveSnapshot()
        refreshNowPlaying()
    }
    
    func next() {
        guard let context = contextStore.session else { return }
        
        if context.repeatMode == .one {
            playFromQueue(at: context.currentIndex)
            return
        }

        if context.shuffleEnabled, context.trackIDs.count > 1 {
            var randomIndex = context.currentIndex
            while randomIndex == context.currentIndex {
                randomIndex = Int.random(in: 0..<context.trackIDs.count)
            }
            playFromQueue(at: randomIndex)
            return
        }

        let nextIndex = context.currentIndex + 1
        if context.trackIDs.indices.contains(nextIndex) {
            playFromQueue(at: nextIndex)
        } else if context.repeatMode == .all {
            playFromQueue(at: 0)
        }
    }
    
    func previous() {
        guard let context = contextStore.session else { return }
        
        if playerState.currentTime > 3 {
            playerEngine.seek(to: 0)
            saveSnapshot()
            refreshNowPlaying()
            return
        }
        
        if context.shuffleEnabled, context.trackIDs.count > 1 {
            var randomIndex = context.currentIndex
            while randomIndex == context.currentIndex {
                randomIndex = Int.random(in: 0..<context.trackIDs.count)
            }
            playFromQueue(at: randomIndex)
            return
        }

        let previousIndex = context.currentIndex - 1
        if context.trackIDs.indices.contains(previousIndex) {
            playFromQueue(at: previousIndex)
        } else if context.repeatMode == .all, !context.trackIDs.isEmpty {
            playFromQueue(at: context.trackIDs.count - 1)
        }
    }
    
    // Nhận progress 0...1 từ UI
    func seek(to normalizedProgress: Float) {
        let duration = max(playerState.duration, 0.01)
        let clamped = min(max(normalizedProgress, 0), 1)
        let seconds = clamped * duration
        
        playerEngine.seek(to: seconds)
        saveSnapshot()
        refreshNowPlaying()
    }
    
    func playFromQueue(at index: Int) {
        guard let context = contextStore.session, context.trackIDs.indices.contains(index) else { return }
        
        let trackID = context.trackIDs[index]
        guard let url = trackResolver.audioURL(for: trackID) else { return }
        
        contextStore.moveToTrack(at: index)
        
        currentTrackID = trackID
        queueTrackIDs = context.trackIDs
        currentIndex = index
        primePlayerStateForNewTrack(trackID: trackID, isPlaying: true)
        
        playerEngine.load(url: url, autoPlay: true, rate: context.speed)
        
        setMiniPlayerVisible(true)
        
        saveSnapshot()
        refreshNowPlaying()
    }
    
    func stop() {
        playerEngine.stop()
        let preservedDuration = max(playerState.duration, Float(currentSong?.duration ?? 0))
        playerState = PlayerState(
            currentTime: 0,
            duration: preservedDuration,
            progress: 0,
            isPlaying: false,
            hasLoadedItem: false
        )
        saveSnapshot()
        refreshNowPlaying()
    }
    
    func hideAndCleanMiniPlayer() {
        playerEngine.stop()
        setMiniPlayerVisible(false)
        dismissPlayer()
        contextStore.clearSession()
        
        currentTrackID = nil
        queueTrackIDs = []
        currentIndex = 0
        
        playerState = .empty
        playbackPersistence.clearSnapshot()
        nowPlayingService.clearNowPlaying()
    }

    func presentPlayer() {
        setPlayerSheetVisible(true)
    }

    func dismissPlayer() {
        setPlayerSheetVisible(false)
    }
    
    func restoreSnapshotIfNeeded() {
        guard !hasRestoredSnapshot else { return }
        hasRestoredSnapshot = true
        
        guard let snapshot = playbackPersistence.loadSnapshot() else { return }
        guard let trackID = snapshot.song.trackID else { return }
        guard let url = trackResolver.audioURL(for: trackID) else { return }
        
        let playbackContext = PlaybackContext(
            trackIDs: snapshot.session.queueTrackIDs,
            currentIndex: snapshot.session.currentIndex,
            source: snapshot.session.source ?? .mixed,
            repeatMode: snapshot.session.repeatMode,
            shuffleEnabled: snapshot.session.shuffleEnabled,
            speed: snapshot.session.speed
        )

        contextStore.setSession(playbackContext)

        currentTrackID = trackID
        queueTrackIDs = snapshot.session.queueTrackIDs
        currentIndex = snapshot.session.currentIndex
        
        let restoredDuration = max(snapshot.song.positionSeconds, 0)
        let restoredTime = max(snapshot.state.positionSeconds, 0)
        let restoredProgress = restoredDuration > 0
            ? min(max(restoredTime / restoredDuration, 0), 1)
            : 0
        let restoredState = PlayerState(
            currentTime: restoredTime,
            duration: restoredDuration,
            progress: restoredProgress,
            isPlaying: false,
            hasLoadedItem: true
        )
        playerState = restoredState
        restoredStateFallback = restoredState

        playerEngine.load(url: url, autoPlay: false, rate: snapshot.session.speed)

        if snapshot.state.positionSeconds > 0 {
            playerEngine.seek(to: snapshot.state.positionSeconds)
        }

        setMiniPlayerVisible(true)
        refreshNowPlaying()
    }
    
    func saveSnapshot() {
        guard let context = contextStore.session else { return }

        let snapshot = PlaybackSnapshot(
            song: SnapshotSong(
                trackID: context.currentTrackID,
                audioFileName: currentSong?.audioFileName,
                localFilePath: currentSong?.localFilePath,
                titleEN: currentSong?.titleEN,
                positionSeconds: playerState.duration > 0
                    ? playerState.duration
                    : Float(currentSong?.duration ?? 0)
            ),
            session: SnapshotSession(
                source: context.source,
                queueTrackIDs: context.trackIDs,
                currentIndex: context.currentIndex,
                speed: context.speed,
                repeatMode: context.repeatMode,
                shuffleEnabled: context.shuffleEnabled
            ),
            state: SnapshotState(
                positionSeconds: playerState.currentTime,
                isPlaying: playerState.isPlaying
            )
        )

        playbackPersistence.saveSnapshot(snapshot)
    }
    
    private func refreshNowPlaying() {
        guard let song = currentSong else {
            nowPlayingService.clearNowPlaying()
            return
        }
        
        nowPlayingService.updateNowPlaying(
            title: song.titleEN,
            artist: song.artist,
            album: song.album,
            duration: Double(playerState.duration),
            elapsedTime: Double(playerState.currentTime),
            playbackRate: playerState.isPlaying ? 1.0 : 0.0,
            defaultRate: 1.0
        )
    }
    
    private func handleTrackDidFinish() {
        guard let context = contextStore.session else { return }

        if context.repeatMode == .one {
            playFromQueue(at: context.currentIndex)
            return
        }

        if context.shuffleEnabled, context.trackIDs.count > 1 {
            var randomIndex = context.currentIndex
            while randomIndex == context.currentIndex {
                randomIndex = Int.random(in: 0..<context.trackIDs.count)
            }
            playFromQueue(at: randomIndex)
            return
        }

        let nextIndex = context.currentIndex + 1
        if context.trackIDs.indices.contains(nextIndex) {
            playFromQueue(at: nextIndex)
        } else if context.repeatMode == .all {
            playFromQueue(at: 0)
        } else {
            stop()
        }
    }
    
    private func bindEngine() {
        playerEngine.statePublisher.receive(on: DispatchQueue.main).sink { [weak self] playerState in
            guard let self else { return }
            
            let mergedPlayerState = self.mergePlayerState(playerState)
            self.playerState = mergedPlayerState
            self.refreshNowPlaying()
        }
        .store(in: &cancellables)
        
        playerEngine.didFinishPublisher.receive(on: DispatchQueue.main).sink { [weak self] in
            guard let self else { return }
            self.handleTrackDidFinish()
        }.store(in: &cancellables)
    }
    
    private func bindSession() {
        contextStore.$session.sink { [weak self] context in
            guard let self else { return }
            
            self.currentTrackID = context?.currentTrackID
            self.queueTrackIDs = context?.trackIDs ?? []
            self.currentIndex = context?.currentIndex ?? 0
            self.playbackSpeed = context?.speed ?? 1.0
            self.shuffleEnabled = context?.shuffleEnabled ?? false
            self.repeatMode = context?.repeatMode ?? .off
        }
        .store(in: &cancellables)
    }

    private func mergePlayerState(_ engineState: PlayerState) -> PlayerState {
        let fallbackState = restoredStateFallback
        let duration = engineState.duration > 0
            ? engineState.duration
            : (fallbackState?.duration ?? 0)
        let currentTime = engineState.currentTime > 0
            ? engineState.currentTime
            : (fallbackState?.currentTime ?? 0)
        let progress = duration > 0
            ? min(max(currentTime / duration, 0), 1)
            : (fallbackState?.progress ?? 0)

        let mergedState = PlayerState(
            currentTime: currentTime,
            duration: duration,
            progress: progress,
            isPlaying: engineState.isPlaying,
            hasLoadedItem: engineState.hasLoadedItem
        )

        if mergedState.duration > 0 || mergedState.currentTime > 0 {
            restoredStateFallback = mergedState
        }

        return mergedState
    }
    
    private func primePlayerStateForNewTrack(trackID: UUID, isPlaying: Bool) {
        let fallbackDuration = max(
            trackResolver.song(for: trackID).map { Float($0.duration) } ?? 0,
            0
        )

        let primedState = PlayerState(
            currentTime: 0,
            duration: fallbackDuration,
            progress: 0,
            isPlaying: isPlaying,
            hasLoadedItem: true
        )

        playerState = primedState
        restoredStateFallback = primedState
    }

    private func setMiniPlayerVisible(_ isVisible: Bool) {
        isMiniPlayerVisible = isVisible
    }

    private func setPlayerSheetVisible(_ isVisible: Bool) {
        isPlayerSheetVisible = isVisible
    }
}
