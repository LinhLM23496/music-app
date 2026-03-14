import SwiftUI

struct PlaylistDetailView: View {
    let playlistID: UUID
    let allSongs: [Song]
    let onRequestAddSongs: () -> Void
    let onShowToast: (String) -> Void

    @EnvironmentObject private var localizationViewModel: LocalizationViewModel
    @EnvironmentObject private var playlistViewModel: PlaylistViewModel
    @EnvironmentObject private var libraryViewModel: LibraryViewModel
    @EnvironmentObject private var playerViewModel: PlayerViewModel

    private var playlist: Playlist? {
        playlistViewModel.playlist(id: playlistID)
    }

    private var playlistSongs: [Song] {
        guard let playlist else { return [] }
        return playlistViewModel.songs(in: playlist, allSongs: allSongs)
    }

    var body: some View {
        List {
            if playlistSongs.isEmpty {
                Text(localizationViewModel.t("playlist.no.songs"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            } else {
                ForEach(playlistSongs) { song in
                    SongRowView(
                        song: song,
                        title: localizationViewModel.songTitle(song),
                        isFavorite: libraryViewModel.favoriteIDs.contains(song.id)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playerViewModel.play(song: song, in: playlistSongs)
                        playerViewModel.presentPlayer(for: song)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            playlistViewModel.removeSong(song, from: playlistID)
                            onShowToast(localizationViewModel.t("playlist.remove.song.success"))
                        } label: {
                            Image(systemName: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
        }
        .safeAreaPadding(.bottom, 59)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(
            playlist.map { localizationViewModel.playlistName($0) }
                ?? localizationViewModel.t("playlist.title")
        )
        .overlay(alignment: .bottomTrailing) {
            if let firstSong = playlistSongs.first {
                Button {
                    playerViewModel.play(song: firstSong, in: playlistSongs)
                    playerViewModel.presentPlayer(for: firstSong)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 60, height: 60)
                        .background(Color.green, in: Circle())
                        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
                .padding(.bottom, 84)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onRequestAddSongs()
                } label: {
                    Label(localizationViewModel.t("playlist.add.song"), systemImage: "plus")
                }
            }
        }
    }
}
