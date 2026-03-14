//
//  PlaybackState.swift
//  MusicApp
//
//  Created by Linh Le on 14/3/26.
//

import Foundation

struct PlaybackState: Equatable {
    var currentTime: Float
    var duration: Float
    var progress: Float
    var isPlaying: Bool
    var hasLoadedItem: Bool
    
    static let empty = PlaybackState(
        currentTime: 0,
        duration: 0,
        progress: 0,
        isPlaying: false,
        hasLoadedItem: false
    )
}
