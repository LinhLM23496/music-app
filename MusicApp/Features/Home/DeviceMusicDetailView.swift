import SwiftUI

struct DeviceMusicDetailView: View {
    @EnvironmentObject private var localizationViewModel: LocalizationViewModel
    @EnvironmentObject private var importViewModel: ImportViewModel
    @EnvironmentObject private var libraryViewModel: LibraryViewModel
    @EnvironmentObject private var playbackController: PlaybackController

    @State private var toastMessage: String?
    @State private var toastWorkItem: DispatchWorkItem?

    private var tracks: [LocalAudioTrack] {
        importViewModel.importedTracks
    }

    private var songs: [Song] {
        tracks.map(importViewModel.songForImportedTrack)
    }

    var body: some View {
        List {
            if tracks.isEmpty {
                Text(localizationViewModel.t("home.device.music.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            } else {
                ForEach(tracks) { track in
                    let song = importViewModel.songForImportedTrack(track)

                    SongRowView(
                        song: song,
                        title: track.displayName,
                        isFavorite: libraryViewModel.favoriteIDs.contains(song.id)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playbackController.play(
                            trackID: song.id,
                            queueTrackIDs: songs.map(\.id),
                            source: .imported
                        )
                        playbackController.presentPlayer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            importViewModel.deleteImportedTrack(track) { success in
                                let key = success
                                    ? "home.device.music.delete.success"
                                    : "home.device.music.delete.error"
                                showToast(localizationViewModel.t(key))
                            }
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
        .navigationTitle(localizationViewModel.t("home.device.music"))
        .overlay(alignment: .top) {
            if let toastMessage {
                AppToastView(message: toastMessage)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: toastMessage != nil)
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
