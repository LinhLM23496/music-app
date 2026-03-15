//
//  TrackResolver.swift
//  MusicApp
//
//  Created by Linh Le on 15/3/26.
//

import Foundation

@MainActor
protocol TrackResolver {
    func song(for id: UUID) -> Song?
    func audioURL(for id: UUID) -> URL?
}
