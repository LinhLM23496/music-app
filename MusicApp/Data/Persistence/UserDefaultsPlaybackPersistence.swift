//
//  UserDefaultsPlaybackPersistence.swift
//  MusicApp
//
//  Created by Linh Le on 14/3/26.
//

import Foundation

@MainActor
final class UserDefaultsPlaybackPersistence: PlaybackPersistence {
    private enum Storage {
        static let playbackSnapshotKey = "playback.snapshot.v2"
    }

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func saveSnapshot(_ snapshot: PlaybackSnapshot) {
        do {
            let data = try encoder.encode(snapshot)
            userDefaults.set(data, forKey: Storage.playbackSnapshotKey)
        } catch {
            print("Failed to save playback snapshot: \(error)")
        }
    }
    
    func loadSnapshot() -> PlaybackSnapshot? {
        guard let data = userDefaults.data(forKey: Storage.playbackSnapshotKey) else {
            return nil
        }

        do {
            return try decoder.decode(PlaybackSnapshot.self, from: data)
        } catch {
            print("Failed to load playback snapshot: \(error)")
            return nil
        }
    }

    func clearSnapshot() {
        userDefaults.removeObject(forKey: Storage.playbackSnapshotKey)
    }
}
