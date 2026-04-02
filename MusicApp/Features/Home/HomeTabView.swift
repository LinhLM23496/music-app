import SwiftUI
import UniformTypeIdentifiers
import Combine

struct HomeTabView: View {
    @EnvironmentObject private var localizationViewModel: LocalizationViewModel
    @EnvironmentObject private var importViewModel: ImportViewModel
    @EnvironmentObject private var libraryViewModel: LibraryViewModel
    @EnvironmentObject private var playbackController: PlaybackController
    @State private var showImporter = false
    @State private var importToast: String?
    @State private var importToastWorkItem: DispatchWorkItem?
    @State private var favoriteSongs: [Song] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    sectionTitle(localizationViewModel.t("home.featured"))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(libraryViewModel.featuredTracks) { song in
                                Button {
                                    playbackController.play(
                                        trackID: song.id,
                                        queueTrackIDs: libraryViewModel.featuredTracks.map(\.id),
                                        source: .library
                                    )
                                    playbackController.presentPlayer()
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        AlbumArtworkView(symbol: song.coverSymbol, accent: song.accent)
                                            .frame(width: 170, height: 170)
                                        Text(localizationViewModel.songTitle(song))
                                            .font(.headline)
                                            .lineLimit(1)
                                        Text(song.artist)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 170, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    sectionTitle(localizationViewModel.t("home.favorites"))

                    if favoriteSongs.isEmpty {
                        Text(localizationViewModel.t("home.favorites.empty.cta"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(favoriteSongs) { song in
                                Button {
                                    playbackController.play(
                                        trackID: song.id,
                                        queueTrackIDs: favoriteSongs.map(\.id),
                                        source: .favorites
                                    )
                                    playbackController.presentPlayer()
                                } label: {
                                    SongRowView(
                                        song: song,
                                        title: localizationViewModel.songTitle(song),
                                        isFavorite: libraryViewModel.favoriteIDs.contains(song.id)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HStack {
                        NavigationLink {
                            DeviceMusicDetailView()
                                .environmentObject(localizationViewModel)
                                .environmentObject(importViewModel)
                                .environmentObject(libraryViewModel)
                                .environmentObject(playbackController)
                        } label: {
                            HStack(spacing: 6) {
                                sectionTitle(localizationViewModel.t("home.device.music"))
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()
                        Button(localizationViewModel.t("home.device.music.import")) {
                            showImporter = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    }

                    let recentImportedTracks = importViewModel.recentImportedTracks

                    if recentImportedTracks.isEmpty {
                        Text(localizationViewModel.t("home.device.music.empty"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(recentImportedTracks) { track in
                                Button {
                                    let importedSong = importViewModel.songForImportedTrack(track)
                                    playbackController.play(
                                        trackID: importedSong.id,
                                        queueTrackIDs: importViewModel.importedSongs.map(\.id),
                                        source: .imported
                                    )
                                    playbackController.presentPlayer()
                                } label: {
                                    let importedSong = importViewModel.songForImportedTrack(track)
                                    SongRowView(
                                        song: importedSong,
                                        title: track.displayName,
                                        isFavorite: libraryViewModel.favoriteIDs.contains(importedSong.id)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
                .padding(.bottom, 59)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(localizationViewModel.t("home.title"))
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importViewModel.importAudioFiles(from: urls) { importResult in
                    showImportToast(importViewModel.importSummaryText(importResult))
                }
            case .failure:
                showImportToast(localizationViewModel.t("home.device.music.import.error"))
            }
        }
        .overlay(alignment: .top) {
            if let importToast {
                AppToastView(message: importToast)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: importToast != nil)
        .onAppear {
            refreshFavoriteSongs()
        }
        .onReceive(
            Publishers.CombineLatest3(
                libraryViewModel.$tracks,
                libraryViewModel.$favoriteIDs,
                importViewModel.$importedTracks
            )
        ) { _, _, _ in
            refreshFavoriteSongs()
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
    }

    private func showImportToast(_ message: String) {
        importToastWorkItem?.cancel()
        importToast = message

        let workItem = DispatchWorkItem {
            importToast = nil
        }
        importToastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: workItem)
    }

    private func refreshFavoriteSongs() {
        let favoriteIDs = libraryViewModel.favoriteIDs
        guard !favoriteIDs.isEmpty else {
            favoriteSongs = []
            return
        }

        let libraryFavorites = libraryViewModel.tracks.filter { favoriteIDs.contains($0.id) }
        let importedFavorites = importViewModel.importedSongs.filter { favoriteIDs.contains($0.id) }
        favoriteSongs = libraryFavorites + importedFavorites
    }
}
