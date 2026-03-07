import SwiftUI
import UniformTypeIdentifiers

struct HomeTabView: View {
    @ObservedObject var vm: HomeViewModel
    @State private var showImporter = false
    @State private var importMessage: String?

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
                                    vm.presentPlayer(for: song)
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
                                vm.presentPlayer(for: song)
                            } label: {
                                SongRowView(song: song, title: vm.localizedSongTitle(song), isFavorite: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        sectionTitle(vm.localized("home.device.music"))
                        Spacer()
                        Button(vm.localized("home.device.music.import")) {
                            showImporter = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)

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
                                    vm.presentPlayer(for: deviceSong)
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
            .navigationTitle(vm.localized("home.title"))
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                vm.importAudioFiles(from: urls) { importResult in
                    importMessage = vm.importSummaryText(importResult)
                }
            case .failure:
                importMessage = vm.localized("home.device.music.import.error")
            }
        }
        .alert(vm.localized("home.device.music.import"), isPresented: Binding(
            get: { importMessage != nil },
            set: { isShowing in
                if !isShowing {
                    importMessage = nil
                }
            }
        )) {
            Button(vm.localized("common.done"), role: .cancel) {
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
