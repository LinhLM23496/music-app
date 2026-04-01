import SwiftUI

struct MarqueeText: View {
    let text: String
    let font: Font

    // Tunable timings
    let startHoldDuration: TimeInterval
    let endHoldDuration: TimeInterval
    let returnDuration: TimeInterval

    // Tunable speed model (longer overflow -> longer travel duration)
    let scrollPointsPerSecond: CGFloat // tốc độ chạy theo độ dài
    let minimumTravelDuration: TimeInterval

    @State private var containerWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isMarqueeActive = false
    @State private var animationTask: Task<Void, Never>?

    init(
        _ text: String,
        font: Font = .body,
        startHoldDuration: TimeInterval = 1.0,
        endHoldDuration: TimeInterval = 1.0,
        returnDuration: TimeInterval = 0.5,
        scrollPointsPerSecond: CGFloat = 42,
        minimumTravelDuration: TimeInterval = 0.7
    ) {
        self.text = text
        self.font = font
        self.startHoldDuration = startHoldDuration
        self.endHoldDuration = endHoldDuration
        self.returnDuration = returnDuration
        self.scrollPointsPerSecond = scrollPointsPerSecond
        self.minimumTravelDuration = minimumTravelDuration
    }

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .truncationMode(.tail)
            .opacity(isMarqueeActive ? 0 : 1)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            containerWidth = geo.size.width
                            restartIfNeeded()
                        }
                        .onChange(of: geo.size.width) { _, newWidth in
                            guard abs(newWidth - containerWidth) > 0.5 else { return }
                            containerWidth = newWidth
                            restartIfNeeded()
                        }
                }
            )
            .background {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: MarqueeTextWidthPreferenceKey.self, value: geo.size.width)
                        }
                    )
                    .hidden()
            }
            .overlay(alignment: .leading) {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: offset)
                    .opacity(isMarqueeActive ? 1 : 0)
            }
            .clipped()
            .onPreferenceChange(MarqueeTextWidthPreferenceKey.self) { newWidth in
                guard abs(newWidth - textWidth) > 0.5 else { return }
                textWidth = newWidth
                restartIfNeeded()
            }
            .onChange(of: text) { _, _ in
                restartIfNeeded(resetMeasurements: true)
            }
            .onDisappear {
                animationTask?.cancel()
                animationTask = nil
                isMarqueeActive = false
                offset = 0
            }
    }

    private var overflowWidth: CGFloat {
        max(textWidth - containerWidth, 0)
    }

    private var canMarquee: Bool {
        containerWidth > 1 && textWidth > 1 && overflowWidth > 1
    }

    private func restartIfNeeded(resetMeasurements: Bool = false) {
        animationTask?.cancel()
        animationTask = nil

        if resetMeasurements {
            textWidth = 0
            containerWidth = 0
        }

        isMarqueeActive = false
        offset = 0

        guard canMarquee else { return }

        let overflow = overflowWidth
        let travelDuration = max(minimumTravelDuration, Double(overflow / max(scrollPointsPerSecond, 1)))

        animationTask = Task { @MainActor in
            while !Task.isCancelled {
                // 1) Show at start and hold
                isMarqueeActive = true
                offset = 0
                try? await Task.sleep(for: .seconds(startHoldDuration))
                guard !Task.isCancelled else { break }

                // 2) Move left based on overflow length ratio
                withAnimation(.linear(duration: travelDuration)) {
                    offset = -overflow
                }
                try? await Task.sleep(for: .seconds(travelDuration))
                guard !Task.isCancelled else { break }

                // 3) Hold at end, then move back quickly
                try? await Task.sleep(for: .seconds(endHoldDuration))
                guard !Task.isCancelled else { break }

                withAnimation(.easeOut(duration: returnDuration)) {
                    offset = 0
                }
                try? await Task.sleep(for: .seconds(returnDuration))
                guard !Task.isCancelled else { break }

                // 4) Loop
            }
        }
    }
}

private struct MarqueeTextWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
