import Foundation

final class PlaybackSnapshotStore {
    private let settingsStore: AppSettingsStore

    init(settingsStore: AppSettingsStore) {
        self.settingsStore = settingsStore
    }

    func save(song: Song?, position: Double, playlistID: UUID?) {
        guard let song else { return }

        settingsStore.savePlaybackSnapshot(
            PlaybackSnapshot(
                audioFileName: song.audioFileName,
                titleEN: song.titleEN,
                localFilePath: song.localFilePath,
                positionSeconds: max(position, 0),
                playlistID: playlistID
            )
        )
    }

    func load() -> PlaybackSnapshot? {
        settingsStore.loadPlaybackSnapshot()
    }

    func clear() {
        settingsStore.savePlaybackSnapshot(nil)
    }
}
