import SwiftUI

struct HomeTabView: View {
    @EnvironmentObject private var vm: MusicLibraryViewModel
    @State private var selectedSong: Song?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    sectionTitle(vm.localized("home.featured"))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(vm.featuredSongs) { song in
                                Button {
                                    vm.play(song: song)
                                    selectedSong = song
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        AlbumArtworkView(symbol: song.coverSymbol, accent: song.accent)
                                            .frame(width: 170, height: 170)
                                        Text(vm.localizedSongTitle(song))
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

                    sectionTitle(vm.localized("home.favorites"))

                    VStack(spacing: 10) {
                        ForEach(vm.favoriteSongs) { song in
                            Button {
                                vm.play(song: song)
                                selectedSong = song
                            } label: {
                                SongRowView(song: song, title: vm.localizedSongTitle(song), isFavorite: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        sectionTitle(vm.localized("home.device.music"))
                        Spacer()
                        Button(vm.localized("common.refresh")) {
                            vm.refreshDeviceTracks()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    }

                    if vm.deviceTracks.isEmpty {
                        Text(vm.localized("home.device.music.empty"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(vm.deviceTracks) { track in
                                Button {
                                    let deviceSong = vm.songForDeviceTrack(track)
                                    vm.play(song: deviceSong)
                                    selectedSong = deviceSong
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
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(vm.localized("home.title"))
        }
        .task {
            vm.refreshDeviceTracks()
        }
        .sheet(item: $selectedSong) { song in
            MusicPlayerView(song: song, controller: vm)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
    }
}
