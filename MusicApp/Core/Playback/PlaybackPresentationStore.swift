//
//  PlaybackPresentationStore.swift
//  MusicApp
//
//  Created by Linh Le on 14/3/26.
//

import Foundation
import Combine

@MainActor
final class PlaybackPresentationStore: ObservableObject {
    @Published var isMiniPlayerHidden: Bool = false
    @Published var presentedTrackID: UUID?
}
