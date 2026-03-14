import SwiftUI

struct PlaylistTabView: View {
    @EnvironmentObject private var localizationViewModel: LocalizationViewModel
    @EnvironmentObject private var playlistViewModel: PlaylistViewModel
    @EnvironmentObject private var libraryViewModel: LibraryViewModel
    @EnvironmentObject private var importViewModel: ImportViewModel
    @EnvironmentObject private var playerViewModel: PlayerViewModel

    @State private var showingCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var selectedPlaylistForAdd: Playlist?
    @State private var selectedPlaylistForDetail: Playlist?
    @State private var playlistPendingDeletion: Playlist?
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                playlistPendingDeletion = playlist
                            } label: {
                                Image(systemName: "trash")
                            }
                            .tint(.red)
                        }
                }
            }
            .safeAreaPadding(.bottom, 59)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(localizationViewModel.t("playlist.title"))
            .navigationDestination(item: $selectedPlaylistForDetail) { playlist in
                PlaylistDetailView(
                    playlistID: playlist.id,
                    allSongs: allSongs,
                    onRequestAddSongs: {
                        selectedPlaylistForAdd = playlistViewModel.playlist(id: playlist.id)
                    },
                    onShowToast: { message in
                        showToast(message)
                    }
                )
                .environmentObject(localizationViewModel)
                .environmentObject(playlistViewModel)
                .environmentObject(libraryViewModel)
                .environmentObject(playerViewModel)
            }
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
        .alert(
            localizationViewModel.t("playlist.delete.confirm.title"),
            isPresented: Binding(
                get: { playlistPendingDeletion != nil },
                set: { if !$0 { playlistPendingDeletion = nil } }
            ),
            presenting: playlistPendingDeletion
        ) { playlist in
            Button(localizationViewModel.t("playlist.delete.confirm.button"), role: .destructive) {
                guard let index = playlistViewModel.playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
                playlistViewModel.deletePlaylist(at: IndexSet(integer: index))
                playlistPendingDeletion = nil
            }
            Button(localizationViewModel.t("playlist.cancel"), role: .cancel) {
                playlistPendingDeletion = nil
            }
        } message: { _ in
            Text(localizationViewModel.t("playlist.delete.confirm.message"))
        }
        .sheet(item: $selectedPlaylistForAdd) { playlist in
            AddSongToPlaylistView(
                playlist: playlist,
                songs: allSongs,
                onSongToggled: { didAdd in
                    let key = didAdd ? "playlist.add.song.success" : "playlist.remove.song.success"
                    showToast(localizationViewModel.t(key))
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
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            selectedPlaylistForDetail = playlist
        }
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
    let onSongToggled: (Bool) -> Void
    @EnvironmentObject private var localizationViewModel: LocalizationViewModel
    @EnvironmentObject private var playlistViewModel: PlaylistViewModel
    @EnvironmentObject private var libraryViewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    private var selectedSongIDs: Set<UUID> {
        let ids = playlistViewModel.playlists
            .first(where: { $0.id == playlist.id })?
            .songIDs ?? []
        return Set(ids)
    }

    var body: some View {
        NavigationStack {
            List(songs) { song in
                Button {
                    let didAdd = playlistViewModel.toggleSong(song, in: playlist.id)
                    onSongToggled(didAdd)
                } label: {
                    HStack(spacing: 10) {
                        SongRowView(song: song, title: localizationViewModel.songTitle(song), isFavorite: libraryViewModel.favoriteIDs.contains(song.id))
                        Image(systemName: selectedSongIDs.contains(song.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selectedSongIDs.contains(song.id) ? .green : .secondary)
                    }
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
