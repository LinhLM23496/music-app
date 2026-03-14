//
//  PlayerSessionStore.swift
//  MusicApp
//
//  Created by Linh Le on 14/3/26.
//

import Foundation
import Combine

@MainActor
final class PlayerSessionStore: ObservableObject {
    @Published private(set) var session: PlayerSession?
    
    var currentTrackID: UUID? { session?.currentTrackID }
    
    func setSession(_ session: PlayerSession?) {
        self.session = session
    }
    
    func clearSession() {
        self.session = nil
    }
    
    func updateRepeatMode(_ repeatMode: RepeatMode) {
        guard var session else { return }
        session.repeatMode = repeatMode
        self.session = session
    }
    
    func updateShuffleMode(_ shuffleMode: Bool) {
        guard var session else { return }
        session.shuffleEnabled = shuffleMode
        self.session = session
    }
    
    func updateSpeed(_ speed: Float) {
        guard var session else { return }
        session.speed = speed
        self.session = session
    }
    
    func moveToTrack(at index: Int) {
        guard var session, session.currentIndex != index, session.trackIDs.indices.contains(index) else { return }
        session.currentIndex = index
        self.session = session
    }
}
