//
//  PlayerEngine.swift
//  MusicApp
//
//  Created by Linh Le on 14/3/26.
//

import Foundation
import Combine

@MainActor
protocol PlayerEngine: AnyObject {
    var statePublisher: AnyPublisher<PlayerState, Never> { get }
    var didFinishPublisher: AnyPublisher<Void, Never> { get }
    var currentState: PlayerState { get }
    
    func load(url: URL, autoPlay: Bool, rate: Float)
    func play(rate: Float)
    func pause()
    func seek(to seconds: Float)
    func stop()
}
