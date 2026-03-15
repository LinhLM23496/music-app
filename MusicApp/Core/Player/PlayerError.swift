//
//  PlayerError.swift
//  MusicApp
//
//  Created by Linh Le on 15/3/26.
//

import Foundation

enum PlayerError: Error, Equatable {
    case audioSessionActivationFailed
    case invalidAudioFile
    case playerUnavailable
}
