import Foundation
import Combine

@MainActor
final class SleepTimerService: ObservableObject {
    @Published private(set) var remaining: Double?

    private var workItem: DispatchWorkItem?
    private var endDate: Date?
    private var ticker: AnyCancellable?
    private var onFire: (() -> Void)?

    func start(minutes: Double, onFire: @escaping () -> Void) {
        cancel()

        guard minutes > 0 else { return }

        let duration = minutes * 60
        self.onFire = onFire
        remaining = duration
        endDate = Date().addingTimeInterval(duration)

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.onFire?()
            self.cancel()
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)

        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let endDate = self.endDate else { return }
                self.remaining = max(0, endDate.timeIntervalSinceNow)
            }
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
        endDate = nil
        ticker?.cancel()
        ticker = nil
        remaining = nil
        onFire = nil
    }
}
