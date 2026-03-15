//
//  PlaybackSource.swift
//  MusicApp
//
//  Created by Linh Le on 14/3/26.
//

import Foundation

enum PlaybackSource: Equatable, Codable {
    case library
    case playlist(UUID)
    case imported
    case favorites
    case mixed
}
