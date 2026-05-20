import AppKit
import SwiftUI

struct AmbientBubbleSpec: Identifiable {
    let id: String
    let color: Color
    let diameter: CGFloat
    let offset: CGSize
    let drift: CGSize
    let phase: Double
    let speed: Double
    let intensity: Double
}

@MainActor
final class IdleBackdropPaletteStore: ObservableObject {
    @Published private(set) var specs: [AmbientBubbleSpec] = IdleBackdropPaletteStore.fallbackSpecs
    private var refreshTask: Task<Void, Never>?

    func refresh(activeSessions: [ActiveIdleSession], games: [Game]) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            let next = await buildSpecs(activeSessions: activeSessions, games: games)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.9)) {
                specs = next
            }
        }
    }

    private func buildSpecs(activeSessions: [ActiveIdleSession], games: [Game]) async -> [AmbientBubbleSpec] {
        guard !activeSessions.isEmpty else { return Self.fallbackSpecs }
        let gamesByID = Dictionary(uniqueKeysWithValues: games.map { ($0.appid, $0) })
        let visible = Array(activeSessions.prefix(12))
        let count = max(1, visible.count)
        let baseDiameter = max(150.0, 520.0 / sqrt(Double(count)))
        var results: [AmbientBubbleSpec] = []
        results.reserveCapacity(count)

        for (idx, session) in visible.enumerated() {
            let game = gamesByID[session.appid]
            let color = await colorForGame(game, index: idx)
            let diameter = CGFloat(baseDiameter) + CGFloat((idx % 3) * 18) - CGFloat(count * 2)
            let seed = Double((session.appid % 997) + UInt64(idx * 13))
            let offset = CGSize(
                width: CGFloat(sin(seed) * 260.0),
                height: CGFloat(cos(seed * 1.7) * 180.0)
            )
            let drift = CGSize(
                width: 26 + CGFloat((idx % 4) * 9),
                height: 18 + CGFloat((idx % 5) * 7)
            )
            results.append(
                AmbientBubbleSpec(
                    id: "\(session.appid)",
                    color: color,
                    diameter: max(130, diameter),
                    offset: offset,
                    drift: drift,
                    phase: seed,
                    speed: 0.26 + (Double((idx % 5) + 1) * 0.07),
                    intensity: min(0.48, 0.28 + (0.02 * Double(idx % 4)))
                )
            )
        }
        return results
    }

    private func colorForGame(_ game: Game?, index: Int) async -> Color {
        let fallback = Self.fallbackColors[index % Self.fallbackColors.count]
        guard let game else { return fallback }
        let candidates = [game.widgetIconURL, game.iconImageURL, game.headerImageURL].compactMap { $0 }
        for url in candidates {
            if let cached = RemoteImageCache.shared.image(for: url),
               let avg = Self.averageColor(from: cached) {
                return Color(nsColor: Self.tunedColor(avg))
            }
        }
        for url in candidates {
            if let loaded = await RemoteImageCache.shared.load(url),
               let avg = Self.averageColor(from: loaded) {
                return Color(nsColor: Self.tunedColor(avg))
            }
        }
        return fallback
    }

    private static func averageColor(from image: NSImage) -> NSColor? {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 1, height: 1), from: .zero, operation: .copy, fraction: 1)
        return rep.colorAt(x: 0, y: 0)
    }

    private static func tunedColor(_ color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let tunedS = min(1.0, max(0.45, s * 1.6))
        let tunedB = min(1.0, max(0.55, b * 1.25))
        return NSColor(hue: h, saturation: tunedS, brightness: tunedB, alpha: 1.0)
    }

    private static let fallbackColors: [Color] = [
        Color.blue,
        Color.green,
        Color.purple,
        Color.cyan
    ]

    private static let fallbackSpecs: [AmbientBubbleSpec] = [
        AmbientBubbleSpec(
            id: "fallback-blue",
            color: .blue,
            diameter: 460,
            offset: CGSize(width: -160, height: 140),
            drift: CGSize(width: 32, height: 22),
            phase: 1.2,
            speed: 0.34,
            intensity: 0.34
        ),
        AmbientBubbleSpec(
            id: "fallback-green",
            color: .green,
            diameter: 340,
            offset: CGSize(width: 180, height: -140),
            drift: CGSize(width: 24, height: 30),
            phase: 2.6,
            speed: 0.28,
            intensity: 0.30
        )
    ]
}
