import SwiftUI
import Combine
import AVFoundation
import CryptoKit

@MainActor
final class MusicLibraryViewModel: ObservableObject {
    struct ImportResult {
        let importedCount: Int
        let skippedCount: Int
        let failedCount: Int
    }

    private enum Storage {
        static let musicFolderName = "MusicFiles"
    }

    @Published var songs: [Song] {
        didSet { libraryStore.songs = songs }
    }
    @Published var deviceTracks: [LocalAudioTrack] {
        didSet { deviceMediaStore.deviceTracks = deviceTracks }
    }
    @Published var featuredSongIDs: [UUID] {
        didSet { libraryStore.featuredSongIDs = featuredSongIDs }
    }
    @Published var favoriteSongIDs: Set<UUID> {
        didSet { libraryStore.favoriteSongIDs = favoriteSongIDs }
    }
    @Published var playlists: [Playlist] {
        didSet { playlistStore.playlists = playlists }
    }

    var language: AppLanguage {
        get { settingsStore.language }
        set {
            if settingsStore.language != newValue {
                settingsStore.language = newValue
            }
        }
    }
    var languagePublisher: AnyPublisher<AppLanguage, Never> {
        settingsStore.$language.eraseToAnyPublisher()
    }
    var favoriteSongIDsPublisher: AnyPublisher<Set<UUID>, Never> {
        $favoriteSongIDs.eraseToAnyPublisher()
    }

    @Published var currentSongID: UUID?
    @Published var isPlaying = false
    let playbackProgress: PlaybackProgressState

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
    @Published var playerSheetSong: Song? {
        didSet { playerUIStore.playerSheetSong = playerSheetSong }
    }
    @Published var sleepTimerRemaining: Double?
    @Published var musicStorageFolderPath: String {
        didSet { deviceMediaStore.musicStorageFolderPath = musicStorageFolderPath }
    }
    @Published var musicStorageFolderStatus: String {
        didSet { deviceMediaStore.musicStorageFolderStatus = musicStorageFolderStatus }
    }

    @Published var user: AppUser {
        didSet { userInfoStore.user = user }
    }

    private let settingsStore: AppSettingsStore
    private let libraryStore: LibraryStore
    private let playlistStore: PlaylistStore
    private let deviceMediaStore = DeviceMediaStore()
    private let playerUIStore = PlayerUIStore()
    private let userInfoStore = UserInfoStore()

    private let queueStore: QueueStore
    private let playbackController: PlaybackController
    private let snapshotStore: PlaybackSnapshotStore
    private let libraryUseCases = LibraryUseCases()
    private let playlistUseCases = PlaylistUseCases()

    private let sleepTimerService = SleepTimerService()
    private let ioQueue = DispatchQueue(label: "com.musicapp.audio-io", qos: .userInitiated)

    private var cancellables = Set<AnyCancellable>()
    private var activeSong: Song?
    private var didPerformInitialActivationWork = false
    private var lastPersistedSnapshotSecond: Int = -1

    init(
        settingsStore: AppSettingsStore,
        catalogProvider: MusicCatalogProviding? = nil
    ) {
        self.settingsStore = settingsStore
        let initialShuffle = settingsStore.shuffleEnabled
        let initialRepeatMode = settingsStore.repeatMode
        isShuffleOn = initialShuffle
        repeatMode = initialRepeatMode

        let provider = catalogProvider ?? MockMusicCatalogProvider()
        let initialCatalog = provider.loadInitialCatalog()
        let initialSongs = initialCatalog.songs

        libraryStore = LibraryStore(
            songs: initialSongs,
            featuredSongIDs: initialCatalog.featuredSongIDs,
            favoriteSongIDs: initialCatalog.favoriteSongIDs
        )
        playlistStore = PlaylistStore(playlists: initialCatalog.playlists)

        queueStore = QueueStore(
            queueSongs: initialSongs,
            queueIndex: 0,
            isShuffleOn: initialShuffle,
            repeatMode: initialRepeatMode
        )
        playbackController = PlaybackController()
        playbackProgress = playbackController.progress
        snapshotStore = PlaybackSnapshotStore(settingsStore: settingsStore)

        songs = libraryStore.songs
        featuredSongIDs = libraryStore.featuredSongIDs
        favoriteSongIDs = libraryStore.favoriteSongIDs
        playlists = playlistStore.playlists
        deviceTracks = deviceMediaStore.deviceTracks

        queueSongs = queueStore.queueSongs
        queueIndex = queueStore.queueIndex
        activeSong = queueStore.currentSong
        currentSongID = activeSong?.id

        isMiniPlayerHidden = playerUIStore.isMiniPlayerHidden
        playerSheetSong = playerUIStore.playerSheetSong
        musicStorageFolderPath = deviceMediaStore.musicStorageFolderPath
        musicStorageFolderStatus = deviceMediaStore.musicStorageFolderStatus
        user = userInfoStore.user

        ensureMusicStorageFolderExists()
        bindSettingsStore()
        bindQueueStore()
        bindPlaybackController()
        bindSleepTimerService()
        bindProgressSnapshotPersistence()
    }

    func handleSceneDidBecomeActive() {
        if !didPerformInitialActivationWork {
            didPerformInitialActivationWork = true
            restorePlaybackSnapshotIfAvailable()
        }
        refreshDeviceTracks()
    }

    var featuredSongs: [Song] {
        libraryUseCases.featuredSongs(songs: songs, featuredSongIDs: featuredSongIDs)
    }

    var favoriteSongs: [Song] {
        libraryUseCases.favoriteSongs(songs: songs, favoriteSongIDs: favoriteSongIDs)
    }

    var currentSong: Song? {
        if let activeSong {
            return activeSong
        }

        guard let currentSongID else { return nil }
        return songs.first(where: { $0.id == currentSongID })
    }

    var shouldShowMiniPlayer: Bool {
        hasPlaybackSession && !isMiniPlayerHidden && currentSong != nil
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

    func songsCountText(_ count: Int) -> String {
        String(format: localized("songs.count"), count)
    }

    func localizedSongTitle(_ song: Song) -> String {
        song.localizedTitle(for: language)
    }

    func localizedPlaylistName(_ playlist: Playlist) -> String {
        playlist.localizedName(for: language)
    }

    func repeatModeTitle() -> String {
        localized(repeatMode.localizationKey)
    }

    func song(for id: UUID) -> Song? {
        libraryUseCases.song(for: id, in: songs)
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
        isMiniPlayerHidden = false
        loadAndPlay(song: selectedSong)
        persistPlaybackSnapshotForCurrentTrack(position: 0)
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
        isMiniPlayerHidden = false
        queueStore.reset()
        snapshotStore.clear()
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

    func displayDuration(for song: Song) -> Double {
        if isSameTrack(song, currentSong), playbackProgress.duration > 0 {
            return playbackProgress.duration
        }
        return song.duration
    }

    func toggleFavorite(for song: Song) {
        favoriteSongIDs = libraryUseCases.toggleFavorite(
            songID: song.id,
            currentFavorites: favoriteSongIDs
        )
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

    func createPlaylist(name: String) {
        playlists = playlistUseCases.createPlaylist(name: name, in: playlists)
    }

    func deletePlaylist(at offsets: IndexSet) {
        playlists = playlistUseCases.deletePlaylists(at: offsets, in: playlists)
    }

    func addSong(_ song: Song, to playlistID: UUID) {
        playlists = playlistUseCases.addSong(song, to: playlistID, in: playlists)
    }

    func songs(in playlist: Playlist) -> [Song] {
        playlistUseCases.songs(in: playlist, allSongs: songs)
    }

    func refreshDeviceTracks() {
        ensureMusicStorageFolderExists()

        guard let musicFolderURL = musicStorageFolderURL() else {
            deviceTracks = []
            return
        }

        ioQueue.async { [weak self] in
            let tracks = Self.loadDeviceTracks(in: musicFolderURL)
            Task { @MainActor [weak self] in
                self?.deviceTracks = tracks
            }
        }
    }

    func importAudioFiles(from urls: [URL], completion: @escaping (ImportResult) -> Void) {
        ensureMusicStorageFolderExists()

        guard let destinationFolder = musicStorageFolderURL() else {
            completion(ImportResult(importedCount: 0, skippedCount: 0, failedCount: urls.count))
            return
        }

        ioQueue.async { [weak self] in
            let supportedExtensions = Set(["mp3", "m4a", "wav", "aac"])
            var imported = 0
            var skipped = 0
            var failed = 0

            for sourceURL in urls {
                let accessed = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }

                let ext = sourceURL.pathExtension.lowercased()
                guard supportedExtensions.contains(ext) else {
                    skipped += 1
                    continue
                }

                let destinationURL = destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)

                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    imported += 1
                } catch {
                    failed += 1
                }
            }

            let result = ImportResult(importedCount: imported, skippedCount: skipped, failedCount: failed)
            let tracks = Self.loadDeviceTracks(in: destinationFolder)

            Task { @MainActor [weak self] in
                self?.deviceTracks = tracks
                completion(result)
            }
        }
    }

    func importSummaryText(_ result: ImportResult) -> String {
        String(
            format: localized("home.device.music.import.result"),
            result.importedCount,
            result.skippedCount,
            result.failedCount
        )
    }

    func songForDeviceTrack(_ track: LocalAudioTrack) -> Song {
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

    private func suggestedQueue(for song: Song) -> [Song] {
        libraryUseCases.suggestedQueue(
            for: song,
            songs: songs,
            deviceTracks: deviceTracks,
            trackToSong: songForDeviceTrack
        )
    }

    private func loadAndPlay(song: Song, autoPlay: Bool = true) {
        lastPersistedSnapshotSecond = -1
        let url = audioURL(for: song)
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
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Audio") {
            return url
        }
        return nil
    }

    private func musicStorageFolderURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(Storage.musicFolderName, isDirectory: true)
    }

    func musicStorageURL() -> URL? {
        musicStorageFolderURL()
    }

    private func musicFileURL(fileName: String) -> URL? {
        musicStorageFolderURL()?
            .appendingPathComponent(fileName)
    }

    private func ensureMusicStorageFolderExists() {
        guard let folderURL = musicStorageFolderURL() else {
            musicStorageFolderPath = "-"
            musicStorageFolderStatus = localized("storage.status.unavailable")
            return
        }

        musicStorageFolderPath = folderURL.path

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory)

        if exists, isDirectory.boolValue {
            musicStorageFolderStatus = localized("storage.status.ready")
            return
        }

        do {
            if exists && !isDirectory.boolValue {
                try FileManager.default.removeItem(at: folderURL)
            }

            try FileManager.default.createDirectory(
                at: folderURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            musicStorageFolderStatus = localized("storage.status.created")
        } catch {
            musicStorageFolderStatus = "\(localized("storage.status.failed")): \(error.localizedDescription)"
        }
    }

    nonisolated private static func loadDeviceTracks(in root: URL) -> [LocalAudioTrack] {
        let allowedExtensions = Set(["mp3", "m4a", "wav", "aac"])
        let files = allAudioFiles(in: root, allowedExtensions: allowedExtensions)

        return files
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                LocalAudioTrack(
                    id: url,
                    url: url,
                    fileName: url.lastPathComponent,
                    displayName: url.deletingPathExtension().lastPathComponent,
                    duration: 180
                )
            }
    }

    nonisolated private static func allAudioFiles(in root: URL, allowedExtensions: Set<String>) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var result: [URL] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }
            result.append(url)
        }
        return result
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

    func savePlaybackSnapshotNow() {
        persistPlaybackSnapshotForCurrentTrack()
    }

    private func persistPlaybackSnapshotForCurrentTrack(position: Double? = nil) {
        let snapshotPosition = max(position ?? playbackProgress.currentTime, 0)
        snapshotStore.save(song: currentSong, position: snapshotPosition)
    }

    private func restorePlaybackSnapshotIfAvailable() {
        guard let snapshot = snapshotStore.load() else { return }
        guard let restoredSong = resolveSong(for: snapshot) else { return }

        let restoredQueue = suggestedQueue(for: restoredSong)
        let selectedSong = queueStore.setQueue(current: restoredSong, in: restoredQueue, isSameTrack: isSameTrack)

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
        if let localPath = snapshot.localFilePath {
            if let track = deviceTracks.first(where: { $0.url.path == localPath }) {
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

        if let track = deviceTracks.first(where: { $0.fileName == snapshot.audioFileName }) {
            return songForDeviceTrack(track)
        }

        if let song = songs.first(where: { $0.audioFileName == snapshot.audioFileName && $0.titleEN == snapshot.titleEN }) {
            return song
        }

        return songs.first(where: { $0.audioFileName == snapshot.audioFileName })
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
            stopPlaybackAtEnd()
        }
    }

    private func stopPlaybackAtEnd() {
        playbackController.stopAtEnd()
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
}
