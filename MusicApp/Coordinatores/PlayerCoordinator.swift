//
//  PlayerCoordinator.swift
//  lớp điều phối chính nhận action từ UI dùng:
//  PlayerSessionStore
//  PlaybackEngine
//  PlayerPersistence
//  NowPlayingService

//  MusicApp
//
//  Created by Linh Le on 14/3/26.
//

import Foundation
import Combine

@MainActor
final class PlayerCoordinator: ObservableObject {
    @Published private(set) var playbackState: PlaybackState = .empty
    @Published private(set) var currentTrackID: UUID? // id của bài ở vị trí hiện tại
    @Published private(set) var queueTrackIDs: [UUID] = []
    @Published private(set) var currentIndex: Int = 0 // đang đứng ở vị trí số mấy trong queue
    @Published private(set) var playbackSpeed: Float = 1.0
    @Published private(set) var shuffleEnabled = false
    @Published private(set) var repeatMode: RepeatMode = .off
    
    private let engine: PlaybackEngine
    private let sessionStore: PlayerSessionStore
    private let playerPresentationStore: PlayerPresentationStore
    private let playerPersistence: PlayerPersistence
    private let trackResolver: TrackResolving
    private let nowPlayingService: NowPlayingControlling
    
    private var cancellables: Set<AnyCancellable> = []
    
    init(
        engine: PlaybackEngine,
        sessionStore: PlayerSessionStore,
        playerPresentationStore: PlayerPresentationStore,
        playerPersistence: PlayerPersistence,
        trackResolver: TrackResolving,
        nowPlayingService: NowPlayingControlling
    ) {
        self.engine = engine
        self.sessionStore = sessionStore
        self.playerPresentationStore = playerPresentationStore
        self.playerPersistence = playerPersistence
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

    var presentedTrackID: UUID? {
        playerPresentationStore.presentedTrackID
    }

    var presentedSong: Song? {
        guard let presentedTrackID else { return nil }
        return trackResolver.song(for: presentedTrackID)
    }

    var shouldShowMiniPlayer: Bool {
        currentSong != nil && !playerPresentationStore.isMiniPlayerHidden
    }
    
    func play(trackID: UUID, queueTrackIDs: [UUID] = [], source: PlaybackSource) {
        guard let index = queueTrackIDs.firstIndex(of: trackID) else { return }
        guard let url = trackResolver.audioURL(for: trackID) else { return }
        
        let playerSession = PlayerSession(
            trackIDs: queueTrackIDs,
            currentIndex: index,
            source: source,
            repeatMode: .all,
            shuffleEnabled: false,
            speed: 1.0
        )
        
        sessionStore.setSession(playerSession)
        currentTrackID = trackID
        self.queueTrackIDs = queueTrackIDs
        currentIndex = index
        
        engine.load(url: url, autoPlay: true, rate: playerSession.speed)
    
        playerPresentationStore.isMiniPlayerHidden = false
        playerPresentationStore.presentedTrackID = trackID
        
        saveSnapshot()
        refreshNowPlaying()
    }
    
    func togglePlayPause() {
        if playbackState == .empty { return }
        if playbackState.isPlaying {
            engine.pause()
        } else {
            guard let session = sessionStore.session,
                    let trackID = session.currentTrackID,
                    let url = trackResolver.audioURL(for: trackID) else { return }
            if playbackState.hasLoadedItem {
                engine.play(rate: session.speed)
            } else {
                engine.load(url: url, autoPlay: true, rate: session.speed)
            }
            
        }
        
        saveSnapshot()
        refreshNowPlaying()
    }

    func toggleShuffle() {
        let nextValue = !shuffleEnabled
        sessionStore.updateShuffleMode(nextValue)
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
        sessionStore.updateRepeatMode(nextMode)
    }

    func setPlaybackSpeed(_ speed: Float) {
        sessionStore.updateSpeed(speed)
        if playbackState.isPlaying {
            engine.play(rate: speed)
        }
        saveSnapshot()
        refreshNowPlaying()
    }
    
    func next() {
        guard let session = sessionStore.session else { return }
        
        if session.repeatMode == .one {
            playFromQueue(at: session.currentIndex)
            return
        }

        if session.shuffleEnabled, session.trackIDs.count > 1 {
            var randomIndex = session.currentIndex
            while randomIndex == session.currentIndex {
                randomIndex = Int.random(in: 0..<session.trackIDs.count)
            }
            playFromQueue(at: randomIndex)
            return
        }

        let nextIndex = session.currentIndex + 1
        if session.trackIDs.indices.contains(nextIndex) {
            playFromQueue(at: nextIndex)
        } else if session.repeatMode == .all {
            playFromQueue(at: 0)
        }
    }
    
    func previous() {
        guard let session = sessionStore.session else { return }
        
        if playbackState.currentTime > 3 {
            engine.seek(to: 0)
            saveSnapshot()
            refreshNowPlaying()
            return
        }
        
        if session.shuffleEnabled, session.trackIDs.count > 1 {
            var randomIndex = session.currentIndex
            while randomIndex == session.currentIndex {
                randomIndex = Int.random(in: 0..<session.trackIDs.count)
            }
            playFromQueue(at: randomIndex)
            return
        }

        let previousIndex = session.currentIndex - 1
        if session.trackIDs.indices.contains(previousIndex) {
            playFromQueue(at: previousIndex)
        } else if session.repeatMode == .all, !session.trackIDs.isEmpty {
            playFromQueue(at: session.trackIDs.count - 1)
        }
    }
    
    // Nhận progress 0...1 từ UI
    func seek(to normalizedProgress: Float) {
        let duration = max(playbackState.duration, 0.01)
        let clamped = min(max(normalizedProgress, 0), 1)
        let seconds = clamped * duration
        
        engine.seek(to: seconds)
        saveSnapshot()
        refreshNowPlaying()
    }
    
    func playFromQueue(at index: Int) {
        guard let session = sessionStore.session, session.trackIDs.indices.contains(index) else { return }
        
        let trackID = session.trackIDs[index]
        guard let url = trackResolver.audioURL(for: trackID) else { return }
        
        sessionStore.moveToTrack(at: index)
        
        currentTrackID = trackID
        queueTrackIDs = session.trackIDs
        currentIndex = index
        
        engine.load(url: url, autoPlay: true, rate: session.speed)
        
        playerPresentationStore.isMiniPlayerHidden = false
        playerPresentationStore.presentedTrackID = trackID
        
        saveSnapshot()
        refreshNowPlaying()
    }
    
    func stop() {
        engine.stop()
        sessionStore.clearSession()
        
        currentTrackID = nil
        queueTrackIDs = []
        currentIndex = 0
        
        playerPresentationStore.presentedTrackID = nil
        playerPersistence.clearSnapshot()
        nowPlayingService.clearNowPlaying()
    }
    
    func hideMiniPlayer() {
        playerPresentationStore.isMiniPlayerHidden = true
    }

    func presentPlayer(for trackID: UUID) {
        playerPresentationStore.presentedTrackID = trackID
    }

    func dismissPlayer() {
        playerPresentationStore.presentedTrackID = nil
    }
    
    func restoreSnapshotIfNeeded() {
        guard let snapshot = playerPersistence.loadSnapshot() else { return }
        guard let trackID = snapshot.trackID else { return }
        guard let url = trackResolver.audioURL(for: trackID) else { return }

        let session = PlayerSession(
            trackIDs: snapshot.queueTrackIDs,
            currentIndex: snapshot.currentIndex,
            source: snapshot.source ?? .mixed,
            repeatMode: snapshot.repeatMode,
            shuffleEnabled: snapshot.shuffleEnabled,
            speed: snapshot.speed
        )

        sessionStore.setSession(session)

        currentTrackID = trackID
        queueTrackIDs = snapshot.queueTrackIDs
        currentIndex = snapshot.currentIndex

        engine.load(url: url, autoPlay: false, rate: snapshot.speed)

        if snapshot.positionSeconds > 0 {
            engine.seek(to: snapshot.positionSeconds)
        }

        playerPresentationStore.isMiniPlayerHidden = false
        refreshNowPlaying()
    }
    
    func saveSnapshot() {
        guard let session = sessionStore.session else { return }

        let snapshot = PlayerSnapshot(
            trackID: session.currentTrackID,
            audioFileName: currentSong?.audioFileName,
            localFilePath: currentSong?.localFilePath,
            titleEN: currentSong?.titleEN,
            positionSeconds: playbackState.currentTime,
            source: session.source,
            queueTrackIDs: session.trackIDs,
            currentIndex: session.currentIndex,
            speed: session.speed,
            repeatMode: session.repeatMode,
            shuffleEnabled: session.shuffleEnabled
        )

        playerPersistence.saveSnapshot(snapshot)
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
            duration: Double(playbackState.duration),
            elapsedTime: Double(playbackState.currentTime),
            playbackRate: playbackState.isPlaying ? 1.0 : 0.0,
            defaultRate: 1.0
        )
    }
    
    private func bindEngine() {
        engine.statePublisher.receive(on: DispatchQueue.main).sink { [weak self] state in
            guard let self else { return }
            self.playbackState = state
            self.refreshNowPlaying()
        }
        .store(in: &cancellables)
    }
    
    private func bindSession() {
        sessionStore.$session.sink { [weak self] session in
            guard let self else { return }
            
            self.currentTrackID = session?.currentTrackID
            self.queueTrackIDs = session?.trackIDs ?? []
            self.currentIndex = session?.currentIndex ?? 0
            self.playbackSpeed = session?.speed ?? 1.0
            self.shuffleEnabled = session?.shuffleEnabled ?? false
            self.repeatMode = session?.repeatMode ?? .off
        }
        .store(in: &cancellables)
    }
}
