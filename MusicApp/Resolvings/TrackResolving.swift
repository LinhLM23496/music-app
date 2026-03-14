//
//  TrackResolving.swift
//  MusicApp
//
//  Created by Linh Le on 15/3/26.
//

import Foundation

@MainActor
protocol TrackResolving {
    func song(for id: UUID) -> Song?
    func audioURL(for id: UUID) -> URL?
}
