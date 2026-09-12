import SwiftUI
import UIKit

/// Produktbild wie ein Icon: freigestellt, ohne Kasten dahinter.
///
/// Lässt sich ein Foto nicht freistellen, bleibt es in seiner Kachel. Ein
/// Foto mit Küchentisch ohne Rahmen sähe verloren aus.
struct ProductImage: View {

    let url: URL?
    let size: CGFloat
    var placeholderSymbol = "shippingbox"
    var cornerRadius: CGFloat = 12

    @State private var shown: DisplayCache.Entry?

    var body: some View {
        content
            .frame(width: size, height: size)
            .task(id: url) { await load() }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if let shown, shown.isCutout {
            Image(uiImage: shown.image)
                .resizable()
                .scaledToFit()
                // Hebt die Packung leicht vom dunklen Grund ab, ohne wieder
                // eine Fläche dahinterzulegen.
                .shadow(color: .black.opacity(0.5), radius: size / 16, y: size / 24)
        } else if let shown {
            Image(uiImage: shown.image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .background(Theme.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            Image(systemName: placeholderSymbol)
                .font(.system(size: size * 0.36, weight: .light))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: size, height: size)
                .background(Theme.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @MainActor
    private func load() async {
        guard let url else {
            shown = nil
            return
        }
        if let cached = DisplayCache.storage.object(forKey: url as NSURL) {
            shown = cached
            return
        }

        shown = nil
        guard let loaded = await ProductImageStore.shared.image(for: url),
              let image = UIImage(data: loaded.data) else { return }

        let entry = DisplayCache.Entry(image: image, isCutout: loaded.isCutout)
        DisplayCache.storage.setObject(entry, forKey: url as NSURL)
        shown = entry
    }
}

/// Fertig dekodierte Bilder für flüssiges Scrollen. Die Festplatte liegt
/// dahinter in `ProductImageStore`.
@MainActor
enum DisplayCache {

    final class Entry {
        let image: UIImage
        let isCutout: Bool

        init(image: UIImage, isCutout: Bool) {
            self.image = image
            self.isCutout = isCutout
        }
    }

    static let storage: NSCache<NSURL, Entry> = {
        let cache = NSCache<NSURL, Entry>()
        cache.countLimit = 200
        return cache
    }()
}
