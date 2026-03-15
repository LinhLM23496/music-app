//
//  PlaybackSnapshot.swift
//  MusicApp
//
//  Created by Linh Le on 14/3/26.
//

import Foundation

struct PlaybackSnapshot: Codable, Equatable {
    var song: SnapshotSong
    var session: SnapshotSession
    var state: SnapshotState
}

struct SnapshotSong: Codable, Equatable {
    var trackID: UUID?
    var audioFileName: String?
    var localFilePath: String?
    var titleEN: String?
    var positionSeconds: Float
}

struct SnapshotSession: Codable, Equatable {
    var source: PlaybackSource?
    var queueTrackIDs: [UUID]
    var currentIndex: Int
    var speed: Float
    var repeatMode: RepeatMode
    var shuffleEnabled: Bool
}

struct SnapshotState: Codable, Equatable {
    var positionSeconds: Float
    var isPlaying: Bool
}
