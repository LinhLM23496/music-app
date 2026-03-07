import SwiftUI

struct PlaylistTabView: View {
    @EnvironmentObject private var localizationViewModel: LocalizationViewModel
    @EnvironmentObject private var playlistViewModel: PlaylistViewModel
    @EnvironmentObject private var libraryViewModel: LibraryViewModel
    @EnvironmentObject private var importViewModel: ImportViewModel

    @State private var showingCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var selectedPlaylistForAdd: Playlist?
    @State private var toastMessage: String?
    @State private var toastWorkItem: DispatchWorkItem?

    private var allSongs: [Song] {
        var combined = libraryViewModel.tracks
        let existingIDs = Set(combined.map(\.id))
        combined.append(contentsOf: importViewModel.importedSongs.filter { !existingIDs.contains($0.id) })
        return combined
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(playlistViewModel.playlists) { playlist in
                    playlistRow(playlist)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onDelete(perform: playlistViewModel.deletePlaylist)
            }
            .safeAreaPadding(.bottom, 59)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(localizationViewModel.t("playlist.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreatePlaylist = true
                    } label: {
                        Label(localizationViewModel.t("playlist.new"), systemImage: "plus")
                    }
                }
            }
        }
        .alert(localizationViewModel.t("playlist.create"), isPresented: $showingCreatePlaylist) {
            TextField(localizationViewModel.t("playlist.name"), text: $newPlaylistName)
            Button(localizationViewModel.t("playlist.cancel"), role: .cancel) {
                newPlaylistName = ""
            }
            Button(localizationViewModel.t("playlist.create.button")) {
                playlistViewModel.createPlaylist(name: newPlaylistName)
                newPlaylistName = ""
            }
        }
        .sheet(item: $selectedPlaylistForAdd) { playlist in
            AddSongToPlaylistView(
                playlist: playlist,
                songs: allSongs,
                onSongAdded: {
                    showToast(localizationViewModel.t("playlist.add.song.success"))
                }
            )
                .environmentObject(localizationViewModel)
                .environmentObject(playlistViewModel)
                .environmentObject(libraryViewModel)
        }
        .overlay(alignment: .top) {
            if let toastMessage {
                AppToastView(message: toastMessage)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: toastMessage != nil)
    }

    private func playlistRow(_ playlist: Playlist) -> some View {
        let playlistSongs = playlistViewModel.songs(in: playlist, allSongs: allSongs)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AlbumArtworkView(symbol: playlist.coverSymbol, accent: playlistSongs.first?.accent ?? .gray)
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(localizationViewModel.playlistName(playlist))
                        .font(.headline)
                    Text(localizationViewModel.songsCountText(playlistSongs.count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(localizationViewModel.t("playlist.add.song")) {
                    selectedPlaylistForAdd = playlist
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

            if playlistSongs.isEmpty {
                Text(localizationViewModel.t("playlist.no.songs"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(playlistSongs.prefix(3)) { song in
                    SongRowView(song: song, title: localizationViewModel.songTitle(song), isFavorite: libraryViewModel.favoriteIDs.contains(song.id))
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func showToast(_ message: String) {
        toastWorkItem?.cancel()
        toastMessage = message

        let workItem = DispatchWorkItem {
            toastMessage = nil
        }
        toastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }
}

struct AddSongToPlaylistView: View {
    let playlist: Playlist
    let songs: [Song]
    let onSongAdded: () -> Void
    @EnvironmentObject private var localizationViewModel: LocalizationViewModel
    @EnvironmentObject private var playlistViewModel: PlaylistViewModel
    @EnvironmentObject private var libraryViewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(songs) { song in
                Button {
                    playlistViewModel.addSong(song, to: playlist.id)
                    onSongAdded()
                } label: {
                    SongRowView(song: song, title: localizationViewModel.songTitle(song), isFavorite: libraryViewModel.favoriteIDs.contains(song.id))
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(localizationViewModel.t("playlist.add.songs"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localizationViewModel.t("common.done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
