import Foundation
import Combine

@MainActor
final class PlayerUIStore: ObservableObject {
    @Published var isMiniPlayerHidden = false
    @Published var playerSheetSong: Song?
}

protocol LibraryPlaybackDataProviding {
    var songs: [Song] { get }
    var importedSongs: [Song] { get }
    var language: AppLanguage { get }
    var languagePublisher: AnyPublisher<AppLanguage, Never> { get }
    func localized(_ key: String) -> String
}

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var isBackgroundPlaybackEnabled = true
    @Published var currentSongID: UUID?
    @Published private(set) var isPlaying = false
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
    @Published var isMiniPlayerHidden: Bool {
        didSet { playerUIStore.isMiniPlayerHidden = isMiniPlayerHidden }
    }
    @Published private(set) var sleepTimerText: String?
    @Published var playerSheetSong: Song?

    let playbackProgress: PlaybackProgressState

    private let settingsStore: AppSettingsStore
    private let libraryDataSource: LibraryPlaybackDataProviding
    private let queueStore: QueueStore
    private let playbackController: PlaybackController
    private let snapshotStore: PlaybackSnapshotStore
    private let libraryUseCases = LibraryUseCases()
    private let sleepTimerService = SleepTimerService()
    private let playerUIStore = PlayerUIStore()

    private var cancellables = Set<AnyCancellable>()
    private var activeSong: Song?
    private var didPerformInitialActivationWork = false
    private var lastPersistedSnapshotSecond: Int = -1

    private enum Storage {
        static let musicFolderName = "MusicFiles"
    }

    init(settingsStore: AppSettingsStore, libraryDataSource: LibraryPlaybackDataProviding) {
        self.settingsStore = settingsStore
        self.libraryDataSource = libraryDataSource

        let initialShuffle = settingsStore.shuffleEnabled
        let initialRepeatMode = settingsStore.repeatMode
        isShuffleOn = initialShuffle
        repeatMode = initialRepeatMode

        let initialSongs = libraryDataSource.songs
        queueStore = QueueStore(
            queueSongs: initialSongs,
            queueIndex: 0,
            isShuffleOn: initialShuffle,
            repeatMode: initialRepeatMode
        )
        playbackController = PlaybackController()
        playbackProgress = playbackController.progress
        snapshotStore = PlaybackSnapshotStore(settingsStore: settingsStore)

        queueSongs = queueStore.queueSongs
        queueIndex = queueStore.queueIndex
        activeSong = queueStore.currentSong
        currentSongID = activeSong?.id
        isMiniPlayerHidden = playerUIStore.isMiniPlayerHidden
        playerSheetSong = playerUIStore.playerSheetSong

        bindSettingsStore()
        bindQueueStore()
        bindPlaybackController()
        bindSleepTimerService()
        bindProgressSnapshotPersistence()
    }

    var languagePublisher: AnyPublisher<AppLanguage, Never> {
        libraryDataSource.languagePublisher
    }

    var currentSong: Song? {
        if let activeSong {
            return activeSong
        }

        guard let currentSongID else { return nil }
        return librarySongs.first(where: { $0.id == currentSongID })
            ?? importedSongs.first(where: { $0.id == currentSongID })
    }

    var shouldShowMiniPlayer: Bool {
        hasPlaybackSession && !isMiniPlayerHidden && currentSong != nil
    }

    func localized(_ key: String) -> String {
        libraryDataSource.localized(key)
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
        let autoQueue = libraryUseCases.suggestedQueue(for: song, songs: librarySongs, importedSongs: importedSongs)
        play(song: song, in: autoQueue)
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
        case .off:
            repeatMode = .all
        case .all:
            repeatMode = .one
        case .one:
            repeatMode = .off
        }
    }

    func toggleShuffle() {
        isShuffleOn.toggle()
    }

    func setPlaybackSpeed(_ speed: Double) {
        playbackSpeed = speed
        playbackController.setRateIfPlaying(speed)
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

    func cancelSleepTimer() {
        sleepTimerService.cancel()
    }

    func pauseLiveProgressUpdates(seconds: Double) {
        playbackController.pauseLiveProgressUpdates(seconds: seconds)
    }

    func resumeLiveProgressUpdates() {
        playbackController.resumeLiveProgressUpdates()
    }

    func seek(to normalizedProgress: Double) {
        let duration = playbackProgress.duration > 0 ? playbackProgress.duration : (currentSong?.duration ?? 1)
        let clamped = min(max(normalizedProgress, 0), 1)
        let seconds = duration * clamped
        playbackController.seek(to: seconds)
        persistPlaybackSnapshotForCurrentTrack(position: seconds)
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

    func handleSceneDidBecomeActive() {
        if !didPerformInitialActivationWork {
            didPerformInitialActivationWork = true
            restorePlaybackSnapshotIfAvailable()
        }
    }

    func savePlaybackSnapshotNow() {
        persistPlaybackSnapshotForCurrentTrack()
    }

    // Placeholder for future remote command center / background session orchestration.
    func setBackgroundPlaybackEnabled(_ enabled: Bool) {
        isBackgroundPlaybackEnabled = enabled
    }

    private var librarySongs: [Song] {
        libraryDataSource.songs
    }

    private var importedSongs: [Song] {
        libraryDataSource.importedSongs
    }

    var language: AppLanguage {
        libraryDataSource.language
    }

    private func play(song: Song, in queue: [Song]) {
        if resumeIfCurrentSong(song) {
            return
        }

        guard audioURL(for: song) != nil else { return }

        let selectedSong = queueStore.setQueue(current: song, in: queue, isSameTrack: isSameTrack)
        activeSong = selectedSong
        currentSongID = selectedSong.id
        hasPlaybackSession = true
        isMiniPlayerHidden = false
        loadAndPlay(song: selectedSong)
        persistPlaybackSnapshotForCurrentTrack(position: 0)
    }

    private func resumeIfCurrentSong(_ song: Song) -> Bool {
        guard isSameTrack(currentSong, song) else { return false }
        activeSong = song
        currentSongID = song.id
        hasPlaybackSession = true
        isMiniPlayerHidden = false

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

    private func stopPlaybackAndHideMiniPlayer() {
        cancelSleepTimer()
        playbackController.stopAndClear()
        activeSong = nil
        currentSongID = nil
        hasPlaybackSession = false
        isMiniPlayerHidden = false
        queueStore.reset()
        snapshotStore.clear()
    }

    private func loadAndPlay(song: Song, autoPlay: Bool = true) {
        lastPersistedSnapshotSecond = -1
        let url = audioURL(for: song)
        if url == nil { return }
        playbackController.load(song: song, audioURL: url, autoPlay: autoPlay, playbackRate: playbackSpeed)
    }

    private func audioURL(for song: Song) -> URL? {
        if let localFilePath = song.localFilePath, FileManager.default.fileExists(atPath: localFilePath) {
            return URL(fileURLWithPath: localFilePath)
        }

        let file = song.audioFileName as NSString
        let name = file.deletingPathExtension
        let ext = file.pathExtension

        if let localURL = musicFileURL(fileName: song.audioFileName), FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        for candidateExt in ["mp3", "m4a", "wav"] {
            let candidate = "\(name).\(candidateExt)"
            if let url = musicFileURL(fileName: candidate), FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/Audio") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/MockAudio") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Audio") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "MockAudio") {
            return url
        }
        return nil
    }

    private func musicStorageFolderURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(Storage.musicFolderName, isDirectory: true)
    }

    private func musicFileURL(fileName: String) -> URL? {
        musicStorageFolderURL()?
            .appendingPathComponent(fileName)
    }

    private func persistPlaybackSnapshotForCurrentTrack(position: Double? = nil) {
        let snapshotPosition = max(position ?? playbackProgress.currentTime, 0)
        snapshotStore.save(song: currentSong, position: snapshotPosition)
    }

    private func restorePlaybackSnapshotIfAvailable() {
        guard let snapshot = snapshotStore.load() else { return }
        guard let restoredSong = resolveSong(for: snapshot) else { return }

        let restoredQueue = libraryUseCases.suggestedQueue(for: restoredSong, songs: librarySongs, importedSongs: importedSongs)
        let selectedSong = queueStore.setQueue(current: restoredSong, in: restoredQueue, isSameTrack: isSameTrack)
        guard audioURL(for: selectedSong) != nil else {
            snapshotStore.clear()
            return
        }

        activeSong = selectedSong
        currentSongID = selectedSong.id
        hasPlaybackSession = true
        isMiniPlayerHidden = false

        loadAndPlay(song: selectedSong, autoPlay: false)
        let estimatedDuration = max(selectedSong.duration, 1)
        let clampedPosition = min(max(snapshot.positionSeconds, 0), estimatedDuration)
        if clampedPosition > 0 {
            playbackController.seek(to: clampedPosition)
        }
        playbackController.pause()
    }

    private func resolveSong(for snapshot: PlaybackSnapshot) -> Song? {
        if let localPath = snapshot.localFilePath,
           let song = importedSongs.first(where: { $0.localFilePath == localPath }) {
            return song
        }

        if let song = importedSongs.first(where: { $0.audioFileName == snapshot.audioFileName }) {
            return song
        }

        if let song = librarySongs.first(where: { $0.audioFileName == snapshot.audioFileName && $0.titleEN == snapshot.titleEN }) {
            return song
        }

        return nil
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

    private func bindSettingsStore() {
        settingsStore.$shuffleEnabled
            .removeDuplicates()
            .sink { [weak self] shuffleEnabled in
                guard let self, self.isShuffleOn != shuffleEnabled else { return }
                self.isShuffleOn = shuffleEnabled
            }
            .store(in: &cancellables)

        settingsStore.$repeatMode
            .removeDuplicates()
            .sink { [weak self] repeatMode in
                guard let self, self.repeatMode != repeatMode else { return }
                self.repeatMode = repeatMode
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
            .assign(to: &$isPlaying)

        playbackController.onDidFinish = { [weak self] in
            self?.handleSongDidFinish()
        }
    }

    private func bindSleepTimerService() {
        sleepTimerService.$remaining
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                guard let value, value > 0 else {
                    self.sleepTimerText = nil
                    return
                }
                let total = Int(value)
                let minute = total / 60
                let second = total % 60
                let time = String(format: "%d:%02d", minute, second)
                self.sleepTimerText = String(format: self.localized("player.sleep.remaining"), time)
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
}
