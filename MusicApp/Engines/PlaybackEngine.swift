//
//  PlaybackEngine.swift
//  MusicApp
//
//  Created by Linh Le on 14/3/26.
//

import Foundation
import Combine

@MainActor
protocol PlaybackEngine: AnyObject {
    var statePublisher: AnyPublisher<PlaybackState, Never> { get }
    var currentState: PlaybackState { get }
    
    func load(url: URL, autoPlay: Bool, rate: Float)
    func play(rate: Float)
    func pause()
    func seek(to seconds: Float)
    func stop()
}
