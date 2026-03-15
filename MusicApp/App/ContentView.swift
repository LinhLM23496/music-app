import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var playerHeroNamespace
    private let playerHeroAnimation = Animation.spring(response: 0.9, dampingFraction: 0.9)
    @StateObject private var settingsStore: AppSettingsStore
    @StateObject private var localizationViewModel: LocalizationViewModel
    @StateObject private var importViewModel: ImportViewModel
    @StateObject private var playlistViewModel: PlaylistViewModel
    @StateObject private var authViewModel: AuthViewModel
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var playbackController: PlaybackController

    init() {
        let container = AppContainer.shared
        let settings = AppSettingsStore.shared
        let localizationViewModel = LocalizationViewModel(
            settingsStore: settings,
            service: BundleLocalizationService()
        )
        let libraryViewModel = container.makeLibraryViewModel()
        let importViewModel = ImportViewModel(settingsStore: settings)
        let playlistViewModel = container.makePlaylistViewModel()
        let playbackContextStore = PlaybackContextStore()

        let trackResolver = DefaultTrackResolver(
            librarySongsProvider: { libraryViewModel.tracks },
            importedSongsProvider: { importViewModel.importedSongs }
        )

        let playbackPersistence = UserDefaultsPlaybackPersistence()
        let playerEngine = AVPlayerEngine()

        let playbackController = PlaybackController(
            playerEngine: playerEngine,
            contextStore: playbackContextStore,
            playbackPersistence: playbackPersistence,
            trackResolver: trackResolver,
            nowPlayingService: SystemNowPlayingService()
        )

        _playbackController = StateObject(wrappedValue: playbackController)

        _settingsStore = StateObject(wrappedValue: settings)
        _localizationViewModel = StateObject(wrappedValue: localizationViewModel)
        _importViewModel = StateObject(wrappedValue: importViewModel)
        _playlistViewModel = StateObject(wrappedValue: playlistViewModel)
        _authViewModel = StateObject(wrappedValue: container.makeAuthViewModel())
        _libraryViewModel = StateObject(wrappedValue: libraryViewModel)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                HomeTabView()
                    .tabItem {
                        Label(localizationViewModel.t("tab.home"), systemImage: "house.fill")
                    }

                PlaylistTabView()
                    .tabItem {
                        Label(localizationViewModel.t("tab.playlist"), systemImage: "music.note.list")
                    }

                InfoTabView()
                    .tabItem {
                        Label(localizationViewModel.t("tab.info"), systemImage: "person.crop.circle")
                    }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if playbackController.shouldShowMiniPlayer, let currentSong = playbackController.currentSong {
                    MiniPlayerBarView(
                        song: currentSong,
                        title: currentSong.localizedTitle(for: settingsStore.language),
                        isPlaying: playbackController.playerState.isPlaying,
                        currentTime: playbackController.playerState.currentTime,
                        duration: playbackController.playerState.duration,
                        progress: playbackController.playerState.progress,
                        heroNamespace: playerHeroNamespace,
                        onTogglePlayPause: { playbackController.togglePlayPause() },
                        onNext: { playbackController.next() },
                        onHide: { playbackController.hideAndCleanMiniPlayer() },
                        onStop: { playbackController.stop() },
                        onOpen: {
                            withAnimation(playerHeroAnimation) {
                                playbackController.presentPlayer()
                            }
                        }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 56)
                }
            }

            if playbackController.isPlayerSheetVisible, let song = playbackController.currentSong {
                MusicPlayerOverlay(
                    song: song,
                    heroNamespace: playerHeroNamespace,
                    dismiss: {
                        withAnimation(playerHeroAnimation) {
                            playbackController.dismissPlayer()
                        }
                    }
                )
                .environmentObject(playbackController)
                .environmentObject(localizationViewModel)
                .environmentObject(libraryViewModel)
                .environmentObject(playlistViewModel)
                .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                .zIndex(10)
            }
        }
        .animation(playerHeroAnimation, value: playbackController.isPlayerSheetVisible)
        .tint(.green)
        .preferredColorScheme(.dark)
        .environmentObject(localizationViewModel)
        .environmentObject(importViewModel)
        .environmentObject(playlistViewModel)
        .environmentObject(settingsStore)
        .environmentObject(authViewModel)
        .environmentObject(libraryViewModel)
        .environmentObject(playbackController)
        .onAppear {
            if scenePhase == .active {
                playbackController.restoreSnapshotIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                DispatchQueue.main.async {
                    playbackController.restoreSnapshotIfNeeded()
                }
            } else if newPhase == .inactive || newPhase == .background {
                DispatchQueue.main.async {
                    playbackController.saveSnapshot()
                }
            }
        }
    }
}

private struct MusicPlayerOverlay: View {
    let song: Song
    let heroNamespace: Namespace.ID
    let dismiss: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            MusicPlayerView(song: song, heroNamespace: heroNamespace, onDismiss: dismiss)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
