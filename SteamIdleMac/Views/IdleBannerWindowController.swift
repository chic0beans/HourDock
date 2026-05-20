import AppKit
import SwiftUI

enum IdleBannerLayout {
    static let landscapeSize = CGSize(width: 460, height: 215)
    static let iconSize = CGSize(width: 184, height: 69)
    static let spacing: CGFloat = 12
    /// Inset from the screen's visible frame so banners never sit under the Dock or menu bar.
    static let edgeInset: CGFloat = 24

    static func windowSize(for style: BannerStyle) -> CGSize {
        style == .landscape ? landscapeSize : iconSize
    }

    static func frameOrigin(index: Int, windowSize: CGSize, style: BannerStyle) -> CGPoint {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let availableWidth = max(visibleFrame.width - edgeInset * 2, windowSize.width)
        let perRowFromWidth = max(1, Int(floor((availableWidth + spacing) / (windowSize.width + spacing))))

        let preferredCols: Int
        switch style {
        case .landscape: preferredCols = 2
        case .icon: preferredCols = 5
        }
        let cols = min(preferredCols, perRowFromWidth)

        let row = index / cols
        let col = index % cols
        let x = visibleFrame.minX + edgeInset + CGFloat(col) * (windowSize.width + spacing)
        let y = visibleFrame.minY + edgeInset + CGFloat(row) * (windowSize.height + spacing)
        return CGPoint(x: x, y: y)
    }
}

@MainActor
final class IdleBannerWindowController: NSWindowController, NSWindowDelegate {
    private let onStop: () -> Void
    private var didHandleStop = false
    let appid: UInt64
    let style: BannerStyle

    init(game: Game, style: BannerStyle, gridIndex: Int, onStop: @escaping () -> Void) {
        self.onStop = onStop
        self.appid = game.appid
        self.style = style

        let size = IdleBannerLayout.windowSize(for: style)
        let origin = IdleBannerLayout.frameOrigin(index: gridIndex, windowSize: size, style: style)

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = game.name
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.setAccessibilityTitle("Idling \(game.name)")

        super.init(window: panel)
        panel.delegate = self

        let root = IdleBannerView(game: game, style: style)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setGridFrame(index: Int) {
        guard let panel = window as? NSPanel else { return }
        let size = IdleBannerLayout.windowSize(for: style)
        let origin = IdleBannerLayout.frameOrigin(index: index, windowSize: size, style: style)
        var frame = panel.frame
        frame.size = NSSize(width: size.width, height: size.height)
        frame.origin = origin
        panel.setFrame(frame, display: true)
    }

    func closeFromSync() {
        guard !didHandleStop else { return }
        didHandleStop = true
        window?.delegate = nil
        // Drop the hosted SwiftUI tree before close so any captured references are freed
        // immediately rather than at the next runloop tick.
        if let panel = window as? NSPanel {
            panel.contentView = nil
        }
        close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        guard !didHandleStop else { return }
        didHandleStop = true
        onStop()
    }
}

struct IdleBannerView: View {
    let game: Game
    let style: BannerStyle

    var body: some View {
        let size = IdleBannerLayout.windowSize(for: style)
        Group {
            switch style {
            case .landscape:
                landscapeArtwork(size: size)
            case .icon:
                iconTile(size: size)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func landscapeArtwork(size: CGSize) -> some View {
        CachedRemoteImage(url: game.headerImageURL, contentMode: .fill) {
            placeholder(size: size, label: game.name)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    @ViewBuilder
    private func iconTile(size: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)

            // Single loader walks the URL fallback chain (widget icon -> icon hash) so
            // we don't stack AsyncImages and double-fetch on failure.
            BannerIconImage(game: game)
                .padding(8)
        }
        .frame(width: size.width, height: size.height)
    }

    private func placeholder(size: CGSize, label: String) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
            Text(label)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(6)
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct BannerIconImage: View {
    let game: Game
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Text(game.name)
                    .font(.caption.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .task(id: game.appid) {
            // Try high-res widget icon first, fall back to icon hash URL.
            let candidates: [URL?] = [game.widgetIconURL, game.iconImageURL]
            for case let url? in candidates {
                if let cached = RemoteImageCache.shared.image(for: url) {
                    image = cached
                    return
                }
            }
            for case let url? in candidates {
                if let loaded = await RemoteImageCache.shared.load(url) {
                    image = loaded
                    return
                }
            }
        }
    }
}

@MainActor
final class IdleBannerWindowManager: ObservableObject {
    private var controllers: [UInt64: IdleBannerWindowController] = [:]
    private var sessionOrder: [UInt64] = []
    private var currentStyle: BannerStyle?

    func sync(with sessions: [ActiveIdleSession],
              games: [Game],
              style: BannerStyle,
              onStop: @escaping (UInt64) -> Void) {
        var didMutateLayout = false
        if currentStyle != style {
            closeAll()
            currentStyle = style
            didMutateLayout = true
        }

        let activeIDs = Set(sessions.map(\.appid))

        for appid in sessionOrder where !activeIDs.contains(appid) {
            if let controller = controllers[appid] {
                controller.closeFromSync()
                controllers.removeValue(forKey: appid)
                didMutateLayout = true
            }
        }
        sessionOrder.removeAll { !activeIDs.contains($0) }

        for session in sessions {
            if let existing = controllers[session.appid], existing.style != style {
                existing.closeFromSync()
                controllers.removeValue(forKey: session.appid)
                sessionOrder.removeAll { $0 == session.appid }
                didMutateLayout = true
            }

            if !sessionOrder.contains(session.appid) {
                sessionOrder.append(session.appid)
                didMutateLayout = true
            }

            guard controllers[session.appid] == nil else { continue }

            let game = games.first(where: { $0.appid == session.appid })
                ?? Game(appid: session.appid, name: session.name, playtimeForever: 0)

            let appid = session.appid
            let gridIndex = (sessionOrder.firstIndex(of: appid)) ?? (sessionOrder.count - 1)
            let controller = IdleBannerWindowController(
                game: game,
                style: style,
                gridIndex: gridIndex
            ) {
                onStop(appid)
            }
            controllers[session.appid] = controller
            controller.showWindow(nil)
            controller.setGridFrame(index: gridIndex)
        }

        if didMutateLayout {
            relayoutAll(style: style)
        }
    }

    func closeAll() {
        for (_, controller) in controllers {
            controller.closeFromSync()
        }
        controllers.removeAll()
        sessionOrder.removeAll()
        currentStyle = nil
    }

    private func relayoutAll(style: BannerStyle) {
        for (index, appid) in sessionOrder.enumerated() {
            controllers[appid]?.setGridFrame(index: index)
        }
    }
}
