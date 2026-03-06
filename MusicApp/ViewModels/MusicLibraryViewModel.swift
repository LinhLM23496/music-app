import SwiftUI
import Combine
import AVFoundation

final class MusicLibraryViewModel: ObservableObject {
    struct ImportResult {
        let importedCount: Int
        let skippedCount: Int
        let failedCount: Int
    }

    private enum Storage {
        static let musicFolderName = "MusicFiles"
    }

    @Published var songs: [Song]
    @Published var deviceTracks: [LocalAudioTrack] = []
    @Published var featuredSongIDs: [UUID]
    @Published var favoriteSongIDs: Set<UUID>
    @Published var playlists: [Playlist]
    @Published var language: AppLanguage {
        didSet {
            if settingsStore.language != language {
                settingsStore.language = language
            }
        }
    }

    @Published var currentSongID: UUID?
    @Published var isPlaying = false
    let playbackProgress = PlaybackProgressState()
    @Published var isShuffleOn: Bool {
        didSet {
            if settingsStore.shuffleEnabled != isShuffleOn {
                settingsStore.shuffleEnabled = isShuffleOn
            }
        }
    }
    @Published var repeatMode: RepeatMode {
        didSet {
            if settingsStore.repeatMode != repeatMode {
                settingsStore.repeatMode = repeatMode
            }
        }
    }
    @Published var queueSongs: [Song]
    @Published var queueIndex: Int
    @Published var playbackSpeed: Double = 1.0
    @Published var hasPlaybackSession = false
    @Published var isMiniPlayerHidden = false
    @Published var playerSheetSong: Song?
    @Published var sleepTimerRemaining: Double?
    @Published var musicStorageFolderPath: String = "-"
    @Published var musicStorageFolderStatus: String = "-"

    let user = AppUser(username: "LinhLe", avatarSymbol: "person.crop.circle.fill", appVersion: "1.0.0")

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var didPlayToEndObserver: NSObjectProtocol?
    private let settingsStore: AppSettingsStore
    private let sleepTimerService = SleepTimerService()
    private let ioQueue = DispatchQueue(label: "com.musicapp.audio-io", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()
    private var activeSong: Song?
    private var pauseLiveUpdatesUntil: Date = .distantPast
    private var lastPersistedSnapshotSecond: Int = -1

    init(settingsStore: AppSettingsStore = .shared) {
        self.settingsStore = settingsStore
        language = settingsStore.language
        isShuffleOn = settingsStore.shuffleEnabled
        repeatMode = settingsStore.repeatMode

        let demoSongs: [Song] = [
            Song(id: UUID(), titleEN: "Afterglow", titleVI: "Dư Âm Hoàng Hôn", artist: "Nova Lane", album: "Neon Nights", coverSymbol: "music.note.tv", audioFileName: "demo_track_1.wav", localFilePath: nil, duration: 228, accent: .pink),
            Song(id: UUID(), titleEN: "Ocean Drive", titleVI: "Đường Ven Biển", artist: "Skyline Echo", album: "City Pulse", coverSymbol: "car.fill", audioFileName: "demo_track_2.wav", localFilePath: nil, duration: 201, accent: .blue),
            Song(id: UUID(), titleEN: "Dream Circuit", titleVI: "Mạch Mơ", artist: "Synth Bloom", album: "Pulse", coverSymbol: "waveform.path.ecg", audioFileName: "demo_track_3.wav", localFilePath: nil, duration: 245, accent: .mint),
            Song(id: UUID(), titleEN: "Golden Hour", titleVI: "Giờ Vàng", artist: "Maya Quill", album: "Sunset Tape", coverSymbol: "sun.max.fill", audioFileName: "demo_track_1.wav", localFilePath: nil, duration: 231, accent: .orange),
            Song(id: UUID(), titleEN: "Lost in Motion", titleVI: "Lạc Trong Chuyển Động", artist: "Vera K", album: "Midnight Run", coverSymbol: "figure.run", audioFileName: "demo_track_2.wav", localFilePath: nil, duration: 214, accent: .purple),
            Song(id: UUID(), titleEN: "Moonline", titleVI: "Đường Trăng", artist: "Ari Voss", album: "Night Signals", coverSymbol: "moon.stars.fill", audioFileName: "demo_track_3.wav", localFilePath: nil, duration: 196, accent: .cyan)
        ]

        songs = demoSongs
        featuredSongIDs = Array(demoSongs.prefix(4).map(\.id))
        favoriteSongIDs = Set([demoSongs[0].id, demoSongs[2].id])
        playlists = [
            Playlist(id: UUID(), nameEN: "Late Night Focus", nameVI: "Tập Trung Đêm Khuya", coverSymbol: "moon.fill", songIDs: [demoSongs[0].id, demoSongs[3].id, demoSongs[5].id]),
            Playlist(id: UUID(), nameEN: "Morning Boost", nameVI: "Năng Lượng Sáng", coverSymbol: "sunrise.fill", songIDs: [demoSongs[1].id, demoSongs[2].id]),
            Playlist(id: UUID(), nameEN: "Weekend Chill", nameVI: "Thư Giãn Cuối Tuần", coverSymbol: "beach.umbrella.fill", songIDs: [demoSongs[4].id])
        ]

        queueSongs = demoSongs
        queueIndex = 0
        activeSong = demoSongs.first
        currentSongID = demoSongs.first?.id

        ensureMusicStorageFolderExists()
        refreshDeviceTracks()
        settingsStore.didRunInitialMusicScan = true
        bindSettingsStore()
        bindSleepTimerService()
        configureAudioSession()
        restorePlaybackSnapshotIfAvailable()
    }

    deinit {
        persistPlaybackSnapshotForCurrentTrack()
        cleanupPlayerObservers()
        cancelSleepTimer()
    }

    var featuredSongs: [Song] {
        songs.filter { featuredSongIDs.contains($0.id) }
    }

    var favoriteSongs: [Song] {
        songs.filter { favoriteSongIDs.contains($0.id) }
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
        songs.first(where: { $0.id == id })
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

        let safeQueue = queue.isEmpty ? [song] : queue
        queueSongs = safeQueue

        if let index = safeQueue.firstIndex(where: { isSameTrack($0, song) }) {
            queueIndex = index
        } else {
            queueSongs.insert(song, at: 0)
            queueIndex = 0
        }

        activeSong = queueSongs[queueIndex]
        currentSongID = activeSong?.id
        hasPlaybackSession = true
        isMiniPlayerHidden = false
        loadAndPlay(song: queueSongs[queueIndex])
        persistPlaybackSnapshotForCurrentTrack(position: 0)
    }

    private func resumeIfCurrentSong(_ song: Song) -> Bool {
        guard isSameTrack(currentSong, song) else { return false }

        if isPlaying {
            return true
        }

        if let player {
            player.playImmediately(atRate: Float(playbackSpeed))
            isPlaying = true
            return true
        }

        loadAndPlay(song: song)
        return true
    }

    func playFromQueue(index: Int) {
        guard queueSongs.indices.contains(index) else { return }
        play(song: queueSongs[index], in: queueSongs)
    }

    func togglePlayPause() {
        guard let player else {
            if let song = currentSong {
                loadAndPlay(song: song)
            }
            return
        }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.playImmediately(atRate: Float(playbackSpeed))
            isPlaying = true
        }
        persistPlaybackSnapshotForCurrentTrack()
    }

    func hideMiniPlayer() {
        stopPlaybackAndHideMiniPlayer()
    }

    func stopAndResetPlayback() {
        cancelSleepTimer()
        player?.pause()
        isPlaying = false

        let duration = playbackProgress.duration > 0 ? playbackProgress.duration : (currentSong?.duration ?? 1)
        player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        playbackProgress.currentTime = 0
        playbackProgress.progress = 0
        playbackProgress.duration = max(duration, 1)
        persistPlaybackSnapshotForCurrentTrack(position: 0)
    }

    func presentPlayer(for song: Song) {
        playerSheetSong = song
    }

    func stopPlaybackAndHideMiniPlayer() {
        player?.pause()
        isPlaying = false
        cancelSleepTimer()
        cleanupPlayerObservers()
        player = nil
        activeSong = nil
        currentSongID = nil
        hasPlaybackSession = false
        isMiniPlayerHidden = false
        queueSongs = []
        queueIndex = 0
        playbackProgress.progress = 0
        playbackProgress.currentTime = 0
        playbackProgress.duration = 1
        settingsStore.savePlaybackSnapshot(nil)
    }

    func setPlaybackSpeed(_ speed: Double) {
        playbackSpeed = speed
        if isPlaying {
            player?.rate = Float(speed)
        }
    }

    func setSleepTimer(minutes: Double?) {
        guard let minutes, minutes > 0 else {
            cancelSleepTimer()
            return
        }

        sleepTimerService.start(minutes: minutes) { [weak self] in
            guard let self else { return }
            self.player?.pause()
            self.isPlaying = false
        }
    }

    func cancelSleepTimer() {
        sleepTimerService.cancel()
    }

    func pauseLiveProgressUpdates(seconds: Double) {
        pauseLiveUpdatesUntil = Date().addingTimeInterval(seconds)
    }

    func resumeLiveProgressUpdates() {
        pauseLiveUpdatesUntil = .distantPast
    }

    func seek(to normalizedProgress: Double) {
        guard let player else { return }

        let duration = playbackProgress.duration > 0 ? playbackProgress.duration : (currentSong?.duration ?? 1)
        let clamped = min(max(normalizedProgress, 0), 1)
        let seconds = duration * clamped
        let target = CMTime(seconds: seconds, preferredTimescale: 600)

        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        playbackProgress.progress = clamped
        playbackProgress.currentTime = seconds
        persistPlaybackSnapshotForCurrentTrack(position: seconds)
    }

    func displayDuration(for song: Song) -> Double {
        if isSameTrack(song, currentSong), playbackProgress.duration > 0 {
            return playbackProgress.duration
        }
        return song.duration
    }

    func toggleFavorite(for song: Song) {
        if favoriteSongIDs.contains(song.id) {
            favoriteSongIDs.remove(song.id)
        } else {
            favoriteSongIDs.insert(song.id)
        }
    }

    func nextSong() {
        advanceToNext(autoTriggered: false)
    }

    func previousSong() {
        rewindToPreviousSongOrStart()
    }

    private func rewindToPreviousSongOrStart() {
        guard !queueSongs.isEmpty else { return }

        if playbackProgress.currentTime > 3 {
            seek(to: 0)
            return
        }

        if isShuffleOn, queueSongs.count > 1 {
            var randomIndex = queueIndex
            while randomIndex == queueIndex {
                randomIndex = Int.random(in: 0..<queueSongs.count)
            }
            play(song: queueSongs[randomIndex], in: queueSongs)
            return
        }

        let previousIndex = queueIndex - 1
        if previousIndex >= 0 {
            play(song: queueSongs[previousIndex], in: queueSongs)
            return
        }

        if repeatMode == .all, let last = queueSongs.indices.last {
            play(song: queueSongs[last], in: queueSongs)
        } else {
            seek(to: 0)
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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        playlists.insert(
            Playlist(
                id: UUID(),
                nameEN: trimmed,
                nameVI: trimmed,
                coverSymbol: "music.note.list",
                songIDs: []
            ),
            at: 0
        )
    }

    func deletePlaylist(at offsets: IndexSet) {
        playlists.remove(atOffsets: offsets)
    }

    func addSong(_ song: Song, to playlistID: UUID) {
        guard let playlistIndex = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        if !playlists[playlistIndex].songIDs.contains(song.id) {
            playlists[playlistIndex].songIDs.append(song.id)
            playlists[playlistIndex].coverSymbol = song.coverSymbol
        }
    }

    func songs(in playlist: Playlist) -> [Song] {
        songs.filter { playlist.songIDs.contains($0.id) }
    }

    func refreshDeviceTracks() {
        ensureMusicStorageFolderExists()

        guard let musicFolderURL = musicStorageFolderURL() else {
            deviceTracks = []
            return
        }

        ioQueue.async { [weak self] in
            let tracks = Self.loadDeviceTracks(in: musicFolderURL)
            DispatchQueue.main.async {
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

            DispatchQueue.main.async {
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
            id: UUID(),
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
        if songs.contains(where: { $0.id == song.id }) {
            return songs
        }

        if song.localFilePath != nil {
            let deviceQueue = deviceTracks.map(songForDeviceTrack)
            if !deviceQueue.isEmpty {
                return deviceQueue
            }
        }

        return [song]
    }

    private func loadAndPlay(song: Song, autoPlay: Bool = true) {
        cleanupPlayerObservers()
        configureAudioSession()
        lastPersistedSnapshotSecond = -1

        guard let url = audioURL(for: song) else {
            isPlaying = false
            playbackProgress.progress = 0
            playbackProgress.currentTime = 0
            playbackProgress.duration = song.duration
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player

        observePlayer(player: player, item: item, fallbackDuration: song.duration)
        if autoPlay {
            player.playImmediately(atRate: Float(playbackSpeed))
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            // Keep app functional even if session activation fails on specific routes/devices.
        }
    }

    private func observePlayer(player: AVPlayer, item: AVPlayerItem, fallbackDuration: Double) {
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            if Date() < self.pauseLiveUpdatesUntil { return }

            let seconds = time.seconds
            if seconds.isFinite {
                self.playbackProgress.currentTime = max(0, seconds)
            }

            let duration = item.duration.seconds
            if duration.isFinite, duration > 0 {
                self.playbackProgress.duration = duration
            } else {
                self.playbackProgress.duration = fallbackDuration
            }

            let total = self.playbackProgress.duration > 0 ? self.playbackProgress.duration : fallbackDuration
            self.playbackProgress.progress = min(max(self.playbackProgress.currentTime / max(total, 0.001), 0), 1)

            let wholeSecond = Int(self.playbackProgress.currentTime.rounded(.down))
            if wholeSecond >= 0, wholeSecond % 5 == 0, wholeSecond != self.lastPersistedSnapshotSecond {
                self.lastPersistedSnapshotSecond = wholeSecond
                self.persistPlaybackSnapshotForCurrentTrack(position: self.playbackProgress.currentTime)
            }
        }

        didPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.handleSongDidFinish()
        }
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

    private static func loadDeviceTracks(in root: URL) -> [LocalAudioTrack] {
        let allowedExtensions = Set(["mp3", "m4a", "wav", "aac"])
        let files = allAudioFiles(in: root, allowedExtensions: allowedExtensions)

        return files
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let duration = AVURLAsset(url: url).duration.seconds
                return LocalAudioTrack(
                    id: url,
                    url: url,
                    fileName: url.lastPathComponent,
                    displayName: url.deletingPathExtension().lastPathComponent,
                    duration: duration.isFinite && duration > 0 ? duration : 180
                )
            }
    }

    private static func allAudioFiles(in root: URL, allowedExtensions: Set<String>) -> [URL] {
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

    private func bindSettingsStore() {
        settingsStore.$language
            .removeDuplicates()
            .sink { [weak self] language in
                guard let self, self.language != language else { return }
                self.language = language
            }
            .store(in: &cancellables)

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

    private func bindSleepTimerService() {
        sleepTimerService.$remaining
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.sleepTimerRemaining = value
            }
            .store(in: &cancellables)
    }

    func savePlaybackSnapshotNow() {
        persistPlaybackSnapshotForCurrentTrack()
    }

    private func persistPlaybackSnapshotForCurrentTrack(position: Double? = nil) {
        guard let song = currentSong else { return }
        let snapshotPosition = max(position ?? playbackProgress.currentTime, 0)

        settingsStore.savePlaybackSnapshot(
            PlaybackSnapshot(
                audioFileName: song.audioFileName,
                titleEN: song.titleEN,
                localFilePath: song.localFilePath,
                positionSeconds: snapshotPosition
            )
        )
    }

    private func restorePlaybackSnapshotIfAvailable() {
        guard let snapshot = settingsStore.loadPlaybackSnapshot() else { return }
        guard let restoredSong = resolveSong(for: snapshot) else { return }

        let restoredQueue = suggestedQueue(for: restoredSong)
        let safeQueue = restoredQueue.isEmpty ? [restoredSong] : restoredQueue

        queueSongs = safeQueue
        queueIndex = safeQueue.firstIndex(where: { isSameTrack($0, restoredSong) }) ?? 0
        activeSong = safeQueue[queueIndex]
        currentSongID = activeSong?.id
        hasPlaybackSession = true
        isMiniPlayerHidden = false

        loadAndPlay(song: safeQueue[queueIndex], autoPlay: false)
        let estimatedDuration = max(safeQueue[queueIndex].duration, 1)
        let clampedPosition = min(max(snapshot.positionSeconds, 0), estimatedDuration)
        if clampedPosition > 0 {
            let seekTime = CMTime(seconds: clampedPosition, preferredTimescale: 600)
            player?.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
            playbackProgress.currentTime = clampedPosition
            let total = max(estimatedDuration, 1)
            playbackProgress.progress = min(max(clampedPosition / total, 0), 1)
        }

        player?.pause()
        isPlaying = false
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
            player?.seek(to: .zero)
            player?.playImmediately(atRate: Float(playbackSpeed))
            isPlaying = true
            return
        }

        advanceToNext(autoTriggered: true)
    }

    private func advanceToNext(autoTriggered: Bool) {
        guard !queueSongs.isEmpty else { return }

        if isShuffleOn, queueSongs.count > 1 {
            var randomIndex = queueIndex
            while randomIndex == queueIndex {
                randomIndex = Int.random(in: 0..<queueSongs.count)
            }
            play(song: queueSongs[randomIndex], in: queueSongs)
            return
        }

        let nextIndex = queueIndex + 1
        if queueSongs.indices.contains(nextIndex) {
            play(song: queueSongs[nextIndex], in: queueSongs)
            return
        }

        if repeatMode == .all {
            play(song: queueSongs[0], in: queueSongs)
            return
        }

        if repeatMode == .off || autoTriggered {
            stopPlaybackAtEnd()
        }
    }

    private func stopPlaybackAtEnd() {
        player?.pause()
        isPlaying = false
        playbackProgress.progress = 1
        playbackProgress.currentTime = playbackProgress.duration
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

    private func cleanupPlayerObservers() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }

        if let observer = didPlayToEndObserver {
            NotificationCenter.default.removeObserver(observer)
            didPlayToEndObserver = nil
        }
    }
}
