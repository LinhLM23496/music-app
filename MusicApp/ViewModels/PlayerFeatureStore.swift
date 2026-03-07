import Foundation
import Combine
import AVFoundation
import CryptoKit
import SwiftUI

@MainActor
final class PlayerFeatureStore: ObservableObject, PlayerFeatureControlling {
    private let settingsStore: AppSettingsStore
    private let libraryStore: LibraryStore
    private let deviceMediaStore: DeviceMediaStore
    private let deviceMediaService: DeviceMediaService
    private let playerUIStore: PlayerUIStore

    private let queueStore: QueueStore
    private let playbackController: PlaybackController
    private let snapshotStore: PlaybackSnapshotStore
    private let sleepTimerService = SleepTimerService()
    private let libraryUseCases = LibraryUseCases()

    private var cancellables = Set<AnyCancellable>()
    private var activeSong: Song?
    private var lastPersistedSnapshotSecond: Int = -1

    @Published var currentSongID: UUID?
    @Published var isPlaying = false
    @Published var isShuffleOn: Bool {
        didSet {
            if settingsStore.shuffleEnabled != isShuffleOn {
                settingsStore.shuffleEnabled = isShuffleOn
            }
            if queueStore.isShuffleOn != isShuffleOn {
                queueStore.isShuffleOn = isShuffleOn
            }
        }
    }
    @Published var repeatMode: RepeatMode {
        didSet {
            if settingsStore.repeatMode != repeatMode {
                settingsStore.repeatMode = repeatMode
            }
            if queueStore.repeatMode != repeatMode {
                queueStore.repeatMode = repeatMode
            }
        }
    }
    @Published var queueSongs: [Song]
    @Published var queueIndex: Int
    @Published var playbackSpeed: Double = 1.0
    @Published var hasPlaybackSession = false
    @Published var sleepTimerRemaining: Double?

    let playbackProgress: PlaybackProgressState

    init(
        settingsStore: AppSettingsStore,
        libraryStore: LibraryStore,
        deviceMediaStore: DeviceMediaStore,
        deviceMediaService: DeviceMediaService,
        playerUIStore: PlayerUIStore,
        queueStore: QueueStore,
        playbackController: PlaybackController,
        snapshotStore: PlaybackSnapshotStore
    ) {
        self.settingsStore = settingsStore
        self.libraryStore = libraryStore
        self.deviceMediaStore = deviceMediaStore
        self.deviceMediaService = deviceMediaService
        self.playerUIStore = playerUIStore
        self.queueStore = queueStore
        self.playbackController = playbackController
        self.snapshotStore = snapshotStore

        isShuffleOn = settingsStore.shuffleEnabled
        repeatMode = settingsStore.repeatMode
        queueSongs = queueStore.queueSongs
        queueIndex = queueStore.queueIndex
        activeSong = queueStore.currentSong
        currentSongID = activeSong?.id
        playbackProgress = playbackController.progress

        bindSettingsStore()
        bindQueueStore()
        bindPlaybackController()
        bindSleepTimerService()
        bindProgressSnapshotPersistence()
    }

    var changePublisher: AnyPublisher<Void, Never> {
        objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }

    var language: AppLanguage { settingsStore.language }
    var languagePublisher: AnyPublisher<AppLanguage, Never> { settingsStore.$language.eraseToAnyPublisher() }
    var favoriteSongIDs: Set<UUID> { libraryStore.favoriteSongIDs }
    var favoriteSongIDsPublisher: AnyPublisher<Set<UUID>, Never> { libraryStore.$favoriteSongIDs.eraseToAnyPublisher() }

    var currentSong: Song? {
        if let activeSong {
            return activeSong
        }

        guard let currentSongID else { return nil }
        return libraryStore.songs.first(where: { $0.id == currentSongID })
    }

    var shouldShowMiniPlayer: Bool {
        hasPlaybackSession && !playerUIStore.isMiniPlayerHidden && currentSong != nil
    }

    var playerSheetSong: Song? {
        get { playerUIStore.playerSheetSong }
        set { playerUIStore.playerSheetSong = newValue }
    }

    var sleepTimerText: String? {
        guard let remaining = sleepTimerRemaining, remaining > 0 else { return nil }
        let total = Int(remaining)
        let minute = total / 60
        let second = total % 60
        let time = String(format: "%d:%02d", minute, second)
        return String(format: localized("player.sleep.remaining"), time)
    }

    func localized(_ key: String) -> String {
        Localizer.string(key, language: language)
    }

    func localizedSongTitle(_ song: Song) -> String {
        song.localizedTitle(for: language)
    }

    func isCurrentSong(_ song: Song) -> Bool {
        isSameTrack(currentSong, song)
    }

    func play(song: Song) {
        if resumeIfCurrentSong(song) {
            return
        }
        let autoQueue = suggestedQueue(for: song)
        play(song: song, in: autoQueue)
    }

    func play(song: Song, in queue: [Song]) {
        if resumeIfCurrentSong(song) {
            return
        }

        let selectedSong = queueStore.setQueue(current: song, in: queue, isSameTrack: isSameTrack)
        activeSong = selectedSong
        currentSongID = selectedSong.id
        hasPlaybackSession = true
        playerUIStore.isMiniPlayerHidden = false
        loadAndPlay(song: selectedSong)
        persistPlaybackSnapshotForCurrentTrack(position: 0)
    }

    func playFromQueue(index: Int) {
        guard let song = queueStore.song(at: index) else { return }
        play(song: song, in: queueStore.queueSongs)
    }

    func togglePlayPause() {
        if !playbackController.hasLoadedItem {
            if let song = currentSong {
                loadAndPlay(song: song)
            }
            return
        }

        if isPlaying {
            playbackController.pause()
        } else {
            playbackController.resume(rate: playbackSpeed)
        }
        persistPlaybackSnapshotForCurrentTrack()
    }

    func nextSong() {
        advanceToNext(autoTriggered: false)
    }

    func previousSong() {
        switch queueStore.previousAction(currentTime: playbackProgress.currentTime) {
        case .seekToStart:
            seek(to: 0)
        case .play(let song):
            play(song: song, in: queueStore.queueSongs)
        case .none:
            break
        }
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func setPlaybackSpeed(_ speed: Double) {
        playbackSpeed = speed
        playbackController.setRateIfPlaying(speed)
    }

    func pauseLiveProgressUpdates(seconds: Double) {
        playbackController.pauseLiveProgressUpdates(seconds: seconds)
    }

    func resumeLiveProgressUpdates() {
        playbackController.resumeLiveProgressUpdates()
    }

    func cancelSleepTimer() {
        sleepTimerService.cancel()
    }

    func setSleepTimer(minutes: Double?) {
        guard let minutes, minutes > 0 else {
            cancelSleepTimer()
            return
        }

        sleepTimerService.start(minutes: minutes) { [weak self] in
            guard let self else { return }
            self.playbackController.pause()
        }
    }

    func seek(to normalizedProgress: Double) {
        let duration = playbackProgress.duration > 0 ? playbackProgress.duration : (currentSong?.duration ?? 1)
        let clamped = min(max(normalizedProgress, 0), 1)
        let seconds = duration * clamped
        playbackController.seek(to: seconds)
        persistPlaybackSnapshotForCurrentTrack(position: seconds)
    }

    func toggleFavorite(for song: Song) {
        libraryStore.favoriteSongIDs = libraryUseCases.toggleFavorite(
            songID: song.id,
            currentFavorites: libraryStore.favoriteSongIDs
        )
    }

    func hideMiniPlayer() {
        stopPlaybackAndHideMiniPlayer()
    }

    func stopAndResetPlayback() {
        cancelSleepTimer()
        playbackController.stopAndReset(fallbackDuration: currentSong?.duration ?? 1)
        persistPlaybackSnapshotForCurrentTrack(position: 0)
    }

    func presentPlayer(for song: Song) {
        playerSheetSong = song
    }

    func stopPlaybackAndHideMiniPlayer() {
        cancelSleepTimer()
        playbackController.stopAndClear()
        activeSong = nil
        currentSongID = nil
        hasPlaybackSession = false
        playerUIStore.isMiniPlayerHidden = false
        queueStore.reset()
        snapshotStore.clear()
    }

    func restorePlaybackSnapshotIfAvailable() {
        guard let snapshot = snapshotStore.load() else { return }
        guard let restoredSong = resolveSong(for: snapshot) else { return }

        let restoredQueue = suggestedQueue(for: restoredSong)
        let selectedSong = queueStore.setQueue(current: restoredSong, in: restoredQueue, isSameTrack: isSameTrack)

        activeSong = selectedSong
        currentSongID = selectedSong.id
        hasPlaybackSession = true
        playerUIStore.isMiniPlayerHidden = false

        loadAndPlay(song: selectedSong, autoPlay: false)

        let estimatedDuration = max(selectedSong.duration, 1)
        let clampedPosition = min(max(snapshot.positionSeconds, 0), estimatedDuration)
        if clampedPosition > 0 {
            playbackController.seek(to: clampedPosition)
        }
        playbackController.pause()
    }

    func savePlaybackSnapshotNow() {
        persistPlaybackSnapshotForCurrentTrack()
    }

    private func suggestedQueue(for song: Song) -> [Song] {
        libraryUseCases.suggestedQueue(
            for: song,
            songs: libraryStore.songs,
            deviceTracks: deviceMediaStore.deviceTracks,
            trackToSong: songForDeviceTrack
        )
    }

    private func songForDeviceTrack(_ track: LocalAudioTrack) -> Song {
        Song(
            id: stableSongID(forLocalPath: track.url.path),
            titleEN: track.displayName,
            titleVI: track.displayName,
            artist: localized("device.artist"),
            album: localized("home.device.music"),
            coverSymbol: "iphone.gen3",
            audioFileName: track.fileName,
            localFilePath: track.url.path,
            duration: track.duration,
            accent: .green
        )
    }

    private func loadAndPlay(song: Song, autoPlay: Bool = true) {
        lastPersistedSnapshotSecond = -1
        let url = deviceMediaService.audioURL(for: song)
        playbackController.load(song: song, audioURL: url, autoPlay: autoPlay, playbackRate: playbackSpeed)
    }

    private func persistPlaybackSnapshotForCurrentTrack(position: Double? = nil) {
        let snapshotPosition = max(position ?? playbackProgress.currentTime, 0)
        snapshotStore.save(song: currentSong, position: snapshotPosition)
    }

    private func bindSettingsStore() {
        settingsStore.$shuffleEnabled
            .removeDuplicates()
            .sink { [weak self] value in
                guard let self, self.isShuffleOn != value else { return }
                self.isShuffleOn = value
            }
            .store(in: &cancellables)

        settingsStore.$repeatMode
            .removeDuplicates()
            .sink { [weak self] value in
                guard let self, self.repeatMode != value else { return }
                self.repeatMode = value
            }
            .store(in: &cancellables)
    }

    private func bindQueueStore() {
        queueStore.$queueSongs
            .sink { [weak self] value in
                self?.queueSongs = value
            }
            .store(in: &cancellables)

        queueStore.$queueIndex
            .sink { [weak self] value in
                self?.queueIndex = value
            }
            .store(in: &cancellables)
    }

    private func bindPlaybackController() {
        playbackController.$isPlaying
            .removeDuplicates()
            .sink { [weak self] value in
                self?.isPlaying = value
            }
            .store(in: &cancellables)

        playbackController.onDidFinish = { [weak self] in
            guard let self else { return }
            self.handleSongDidFinish()
        }
    }

    private func bindSleepTimerService() {
        sleepTimerService.$remaining
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.sleepTimerRemaining = value
            }
            .store(in: &cancellables)
    }

    private func bindProgressSnapshotPersistence() {
        playbackProgress.$currentTime
            .sink { [weak self] time in
                guard let self else { return }
                let wholeSecond = Int(time.rounded(.down))
                if wholeSecond >= 0,
                   wholeSecond % 5 == 0,
                   wholeSecond != self.lastPersistedSnapshotSecond,
                   self.hasPlaybackSession {
                    self.lastPersistedSnapshotSecond = wholeSecond
                    self.persistPlaybackSnapshotForCurrentTrack(position: time)
                }
            }
            .store(in: &cancellables)
    }

    private func resolveSong(for snapshot: PlaybackSnapshot) -> Song? {
        if let localPath = snapshot.localFilePath {
            if let track = deviceMediaStore.deviceTracks.first(where: { $0.url.path == localPath }) {
                return songForDeviceTrack(track)
            }

            if FileManager.default.fileExists(atPath: localPath) {
                let localURL = URL(fileURLWithPath: localPath)
                let duration = AVURLAsset(url: localURL).duration.seconds
                let track = LocalAudioTrack(
                    id: localURL,
                    url: localURL,
                    fileName: localURL.lastPathComponent,
                    displayName: localURL.deletingPathExtension().lastPathComponent,
                    duration: duration.isFinite && duration > 0 ? duration : 180
                )
                return songForDeviceTrack(track)
            }
        }

        if let track = deviceMediaStore.deviceTracks.first(where: { $0.fileName == snapshot.audioFileName }) {
            return songForDeviceTrack(track)
        }

        if let song = libraryStore.songs.first(where: { $0.audioFileName == snapshot.audioFileName && $0.titleEN == snapshot.titleEN }) {
            return song
        }

        return libraryStore.songs.first(where: { $0.audioFileName == snapshot.audioFileName })
    }

    private func handleSongDidFinish() {
        if repeatMode == .one {
            playbackController.seek(to: 0)
            playbackController.resume(rate: playbackSpeed)
            return
        }

        advanceToNext(autoTriggered: true)
    }

    private func advanceToNext(autoTriggered: Bool) {
        switch queueStore.nextAction(autoTriggered: autoTriggered) {
        case .play(let song):
            play(song: song, in: queueStore.queueSongs)
        case .stopAtEnd:
            playbackController.stopAtEnd()
        }
    }

    private func isSameTrack(_ lhs: Song?, _ rhs: Song?) -> Bool {
        guard let lhs, let rhs else { return false }

        if let lhsPath = lhs.localFilePath, let rhsPath = rhs.localFilePath {
            return lhsPath == rhsPath
        }

        if lhs.id == rhs.id {
            return true
        }

        return lhs.audioFileName == rhs.audioFileName && lhs.titleEN == rhs.titleEN
    }

    private func resumeIfCurrentSong(_ song: Song) -> Bool {
        guard isSameTrack(currentSong, song) else { return false }

        if isPlaying {
            return true
        }

        if playbackController.hasLoadedItem {
            playbackController.resume(rate: playbackSpeed)
            return true
        }

        loadAndPlay(song: song)
        return true
    }

    private func stableSongID(forLocalPath path: String) -> UUID {
        let digest = SHA256.hash(data: Data(path.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let uuid = uuid_t(bytes[0], bytes[1], bytes[2], bytes[3],
                          bytes[4], bytes[5], bytes[6], bytes[7],
                          bytes[8], bytes[9], bytes[10], bytes[11],
                          bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: uuid)
    }
}
