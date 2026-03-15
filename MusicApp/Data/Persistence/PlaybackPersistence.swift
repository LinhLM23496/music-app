//
//  PlaybackPersistence.swift
//  MusicApp
//
//  Created by Linh Le on 14/3/26.
//

import Foundation

@MainActor
protocol PlaybackPersistence {
    func saveSnapshot(_ snapshot: PlaybackSnapshot)
    func loadSnapshot() -> PlaybackSnapshot?
    func clearSnapshot()
}
