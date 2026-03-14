//
//  PlayerSnapshot.swift
//  MusicApp
//
//  Created by Linh Le on 14/3/26.
//

import Foundation

struct PlayerSnapshot: Codable, Equatable {
    var trackID: UUID?
    var audioFileName: String?
    var localFilePath: String?
    var titleEN: String?
    var positionSeconds: Float
    var source: PlaybackSource?
    var queueTrackIDs: [UUID]
    var currentIndex: Int
    var speed: Float
    var repeatMode: RepeatMode
    var shuffleEnabled: Bool
}
