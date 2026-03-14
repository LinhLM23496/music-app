//
//  PlayerPersistence.swift
//  MusicApp
//
//  Created by Linh Le on 14/3/26.
//

import Foundation

@MainActor
protocol PlayerPersistence {
    func saveSnapshot(_ snapshot: PlayerSnapshot)
    func loadSnapshot() -> PlayerSnapshot?
    func clearSnapshot()
}
