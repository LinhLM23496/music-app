import SwiftUI
import UniformTypeIdentifiers

struct HomeTabView: View {
    @EnvironmentObject private var localizationViewModel: LocalizationViewModel
    @EnvironmentObject private var importViewModel: ImportViewModel
    @EnvironmentObject private var libraryViewModel: LibraryViewModel
    @EnvironmentObject private var playerViewModel: PlayerViewModel
    @State private var showImporter = false
    @State private var importMessage: String?

    private var favoriteSongs: [Song] {
        let libraryFavorites = libraryViewModel.tracks.filter { libraryViewModel.favoriteIDs.contains($0.id) }
        let importedFavorites = importViewModel.importedSongs.filter { libraryViewModel.favoriteIDs.contains($0.id) }
        return libraryFavorites + importedFavorites
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    sectionTitle(localizationViewModel.t("home.featured"))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(libraryViewModel.featuredTracks) { song in
                                Button {
                                    playerViewModel.play(song: song)
                                    playerViewModel.presentPlayer(for: song)
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
                                    playerViewModel.play(song: song)
                                    playerViewModel.presentPlayer(for: song)
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
                        sectionTitle(localizationViewModel.t("home.device.music"))
                        Spacer()
                        Button(localizationViewModel.t("home.device.music.import")) {
                            showImporter = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    }

                    if importViewModel.importedTracks.isEmpty {
                        Text(localizationViewModel.t("home.device.music.empty"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(importViewModel.importedTracks) { track in
                                Button {
                                    let importedSong = importViewModel.songForImportedTrack(track)
                                    playerViewModel.play(song: importedSong)
                                    playerViewModel.presentPlayer(for: importedSong)
                                } label: {
                                    HStack(spacing: 12) {
                                        AlbumArtworkView(symbol: "waveform", accent: .green, cornerRadius: 12)
                                            .frame(width: 58, height: 58)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(track.displayName)
                                                .font(.headline)
                                                .lineLimit(1)
                                            Text(track.fileName)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        Image(systemName: "play.fill")
                                            .foregroundStyle(.green)
                                    }
                                    .padding(10)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    importMessage = importViewModel.importSummaryText(importResult)
                }
            case .failure:
                importMessage = localizationViewModel.t("home.device.music.import.error")
            }
        }
        .alert(localizationViewModel.t("home.device.music.import"), isPresented: Binding(
            get: { importMessage != nil },
            set: { isShowing in
                if !isShowing {
                    importMessage = nil
                }
            }
        )) {
            Button(localizationViewModel.t("common.done"), role: .cancel) {
                importMessage = nil
            }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
    }
}
