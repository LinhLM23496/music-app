//
//  UserDefaultsPlayerPersistence.swift
//  MusicApp
//
//  Created by Linh Le on 14/3/26.
//

import Foundation

@MainActor
final class UserDefaultsPlayerPersistence: PlayerPersistence {
    private enum Storage {
        static let playerSnapshotKey = "player.snapshot.v2"
    }

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func saveSnapshot(_ snapshot: PlayerSnapshot) {
        do {
            let data = try encoder.encode(snapshot)
            userDefaults.set(data, forKey: Storage.playerSnapshotKey)
        } catch {
            print("saveSnapshot: Failed to save player snapshot: \(error)")
        }
    }
    
    func loadSnapshot() -> PlayerSnapshot? {
        guard let data = userDefaults.data(forKey: Storage.playerSnapshotKey) else {
            return nil
        }

        do {
            return try decoder.decode(PlayerSnapshot.self, from: data)
        } catch {
            print("Failed to load player snapshot: \(error)")
            return nil
        }
    }

    func clearSnapshot() {
        userDefaults.removeObject(forKey: Storage.playerSnapshotKey)
    }
}
