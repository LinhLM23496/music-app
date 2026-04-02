import Foundation
import Network
import Combine

@MainActor
final class NetworkPathObserver: ObservableObject {
    @Published private(set) var isCellular = false
    @Published private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.musicapp.network-path")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isCellular = path.usesInterfaceType(.cellular)
                self.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
