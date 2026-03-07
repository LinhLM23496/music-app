import Foundation
import Combine

@MainActor
final class DeviceMediaStore: ObservableObject {
    @Published var deviceTracks: [LocalAudioTrack] = []
    @Published var musicStorageFolderPath: String = "-"
    @Published var musicStorageFolderStatus: String = "-"
}
