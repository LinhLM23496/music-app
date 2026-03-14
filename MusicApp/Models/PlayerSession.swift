//
//  PlayerSession.swift
//  MusicApp
//
//  Created by Linh Le on 14/3/26.
//

import Foundation

struct PlayerSession: Equatable, Codable {
    var trackIDs: [UUID]
    var currentIndex: Int
    var source: PlaybackSource
    var repeatMode: RepeatMode
    var shuffleEnabled: Bool
    var speed: Float

    var currentTrackID: UUID? {
        guard !trackIDs.isEmpty else { return nil }
        guard trackIDs.indices.contains(currentIndex) else { return nil }
        return trackIDs[currentIndex]
    }
}
