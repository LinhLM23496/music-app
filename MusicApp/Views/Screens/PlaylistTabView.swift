import SwiftUI

struct PlaylistTabView: View {
    @EnvironmentObject private var vm: MusicLibraryViewModel
    @EnvironmentObject private var playlistViewModel: PlaylistViewModel
    @EnvironmentObject private var libraryViewModel: LibraryViewModel

    @State private var showingCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var selectedPlaylistForAdd: Playlist?

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
            .navigationTitle(vm.localized("playlist.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreatePlaylist = true
                    } label: {
                        Label(vm.localized("playlist.new"), systemImage: "plus")
                    }
                }
            }
        }
        .alert(vm.localized("playlist.create"), isPresented: $showingCreatePlaylist) {
            TextField(vm.localized("playlist.name"), text: $newPlaylistName)
            Button(vm.localized("playlist.cancel"), role: .cancel) {
                newPlaylistName = ""
            }
            Button(vm.localized("playlist.create.button")) {
                playlistViewModel.createPlaylist(name: newPlaylistName)
                newPlaylistName = ""
            }
        }
        .sheet(item: $selectedPlaylistForAdd) { playlist in
            AddSongToPlaylistView(playlist: playlist)
                .environmentObject(vm)
                .environmentObject(playlistViewModel)
                .environmentObject(libraryViewModel)
        }
    }

    private func playlistRow(_ playlist: Playlist) -> some View {
        let playlistSongs = playlistViewModel.songs(in: playlist, allSongs: vm.songs)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AlbumArtworkView(symbol: playlist.coverSymbol, accent: playlistSongs.first?.accent ?? .gray)
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.localizedPlaylistName(playlist))
                        .font(.headline)
                    Text(vm.songsCountText(playlistSongs.count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(vm.localized("playlist.add.song")) {
                    selectedPlaylistForAdd = playlist
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

            if playlistSongs.isEmpty {
                Text(vm.localized("playlist.no.songs"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(playlistSongs.prefix(3)) { song in
                    SongRowView(song: song, title: vm.localizedSongTitle(song), isFavorite: libraryViewModel.favoriteIDs.contains(song.id))
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct AddSongToPlaylistView: View {
    let playlist: Playlist
    @EnvironmentObject private var vm: MusicLibraryViewModel
    @EnvironmentObject private var playlistViewModel: PlaylistViewModel
    @EnvironmentObject private var libraryViewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(vm.songs) { song in
                Button {
                    playlistViewModel.addSong(song, to: playlist.id)
                } label: {
                    SongRowView(song: song, title: vm.localizedSongTitle(song), isFavorite: libraryViewModel.favoriteIDs.contains(song.id))
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(vm.localized("playlist.add.songs"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(vm.localized("common.done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
