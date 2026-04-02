import SwiftUI
import AVFoundation
import UIKit

struct AlbumArtworkView: View {
    let symbol: String
    let accent: Color
    var localFilePath: String? = nil
    var cornerRadius: CGFloat = 16
    @State private var artworkImage: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [accent.opacity(0.95), .black.opacity(0.95)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                if let artworkImage {
                    Image(uiImage: artworkImage)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    Image(systemName: symbol)
                        .resizable()
                        .scaledToFit()
                        .padding(22)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: localFilePath) {
                artworkImage = await LocalArtworkExtractor.image(for: localFilePath)
            }
    }
}

private enum LocalArtworkExtractor {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for localFilePath: String?) async -> UIImage? {
        guard let localFilePath, !localFilePath.isEmpty else { return nil }
        let key = NSString(string: localFilePath)

        if let cached = cache.object(forKey: key) {
            return cached
        }

        return await Task.detached(priority: .utility) {
            let url = URL(fileURLWithPath: localFilePath)
            let asset = AVURLAsset(url: url)

            if let data = artworkData(from: asset), let image = UIImage(data: data) {
                cache.setObject(image, forKey: key)
                return image
            }

            return nil
        }.value
    }

    private static func artworkData(from asset: AVURLAsset) -> Data? {
        if let commonArtwork = asset.commonMetadata.first(where: { $0.commonKey?.rawValue == "artwork" }),
           let data = commonArtwork.dataValue {
            return data
        }

        for format in asset.availableMetadataFormats {
            for item in asset.metadata(forFormat: format) {
                if let data = item.dataValue {
                    return data
                }
            }
        }

        return nil
    }
}
