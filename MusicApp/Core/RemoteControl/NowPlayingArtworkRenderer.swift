import SwiftUI
import UIKit

enum NowPlayingArtworkRenderer {
    static func image(for song: Song) -> UIImage? {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        let accentColor = UIColor(song.accent)
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 220, weight: .regular)
        guard let symbolImage = UIImage(systemName: song.coverSymbol, withConfiguration: symbolConfig)?
            .withTintColor(.white.withAlphaComponent(0.9), renderingMode: .alwaysOriginal) else {
            return nil
        }

        return renderer.image { context in
            let cgContext = context.cgContext
            let colors = [accentColor.cgColor, UIColor.black.cgColor] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) else {
                return
            }

            cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )

            let symbolRect = CGRect(
                x: (size.width - 220) / 2,
                y: (size.height - 220) / 2,
                width: 220,
                height: 220
            )
            symbolImage.draw(in: symbolRect)
        }
    }
}
