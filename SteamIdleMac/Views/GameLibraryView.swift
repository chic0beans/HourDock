import AppKit
import SwiftUI

private enum LibraryGridMetrics {
    static let cardMinWidth: CGFloat = 220
    static let spacing: CGFloat = 16
    static let horizontalPadding: CGFloat = 20
}

struct GameLibraryView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var idleTimeStore = IdleTimeStore.shared
    @StateObject private var backdropPalette = IdleBackdropPaletteStore()
    @State private var refreshTask: Task<Void, Never>?

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: LibraryGridMetrics.cardMinWidth), spacing: LibraryGridMetrics.spacing)]
    }

    var body: some View {
        GeometryReader { proxy in
            let showRail = proxy.size.width >= 1220

            ZStack {
                AmbientBubbleBackground(specs: backdropPalette.specs, dimWhenInactive: true)

                if appState.isLoadingLibrary && appState.games.isEmpty {
                    ProgressView("Loading games...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if appState.games.isEmpty {
                    emptyState
                } else {
                    contentLayout(showRail: showRail)
                }
            }
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
        .onAppear {
            refreshBackdropPalette()
        }
        .onChange(of: appState.idleManager.activeSessions) { _ in
            refreshBackdropPalette()
        }
        .onChange(of: appState.games) { _ in
            refreshBackdropPalette()
        }
    }

    private func contentLayout(showRail: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroHeader
                        .padding(.horizontal, LibraryGridMetrics.horizontalPadding)

                    controlBar
                        .padding(.horizontal, LibraryGridMetrics.horizontalPadding)

                    if !spotlightGames.isEmpty {
                        sectionCard(title: "Recent Games") {
                            spotlightStrip
                        }
                        .padding(.horizontal, LibraryGridMetrics.horizontalPadding)
                    }

                    if !idlingGames.isEmpty {
                        sectionCard(title: "Idling", subtitle: "\(idlingGames.count) active") {
                            libraryGrid(games: idlingGames)
                        }
                        .padding(.horizontal, LibraryGridMetrics.horizontalPadding)
                    }

                    sectionCard(title: "Library", subtitle: "\(libraryGames.count) games") {
                        libraryGrid(games: libraryGames)
                    }
                    .padding(.horizontal, LibraryGridMetrics.horizontalPadding)
                }
                .padding(.vertical, 18)
                .animation(.spring(response: 0.32, dampingFraction: 0.8), value: appState.idleManager.activeSessions.count)
            }

            if showRail {
                utilityRail
                    .frame(width: 300)
                    .padding(.trailing, 20)
                    .padding(.top, 18)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !showRail {
                compactUtilityPills
                    .padding(.trailing, 22)
                    .padding(.bottom, 14)
            }
        }
    }

    private var heroHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            CachedRemoteImage(url: appState.profileAvatarURL, contentMode: .fill) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.10))
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                AnimatedGreetingText(text: appState.greetingLine)
                Text(heroSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Start Selected") { appState.startIdleForSelection() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appState.canStartIdle)

                Button("Stop All") { appState.stopAllIdling() }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(appState.idleManager.activeSessions.isEmpty)

                Button {
                    refreshTask?.cancel()
                    refreshTask = Task { @MainActor in
                        await appState.refreshLibrary(force: true)
                        guard !Task.isCancelled else { return }
                        await appState.refreshProfileFromNetwork(minInterval: 0)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Refresh library")
                .help("Refresh library")
                .disabled(appState.isLoadingLibrary || appState.isLoadingProfile)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.93))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search games", text: $appState.searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search games")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .frame(maxWidth: 280)

            SortSegmentedControl(selection: $appState.sortOrder)
                .accessibilityLabel("Sort by")

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    appState.toggleSortDirection()
                }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(.degrees(appState.sortAscending ? 0 : 180))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: appState.sortAscending)
            .accessibilityLabel("Toggle sort direction")
            .help(appState.sortOrder.directionHelp(ascending: appState.sortAscending))

            Spacer()

            if !appState.selectedAppIDs.isEmpty {
                Text("\(appState.selectedAppIDs.count) selected")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.accentColor.opacity(0.30)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
            }

            Button {
                appState.showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Settings")
            .help("Settings")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.93))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private func sectionCard<Content: View>(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.bold())
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.93))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
    }

    private var spotlightStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(spotlightGames) { game in
                    MiniSpotlightCard(
                        game: game,
                        isIdling: appState.idleManager.activeAppIDs.contains(game.appid),
                        isLaunching: appState.launchingAppIDs.contains(game.appid),
                        onPrimary: {
                            if !appState.idleManager.activeAppIDs.contains(game.appid) &&
                                !appState.launchingAppIDs.contains(game.appid) {
                                appState.startIdle(game: game)
                            }
                        }
                    )
                    .frame(width: 230)
                    .id(game.appid)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func libraryGrid(games: [Game]) -> some View {
        LazyVGrid(columns: columns, spacing: LibraryGridMetrics.spacing) {
            ForEach(games) { game in
                gameCard(for: game)
                    .id(game.appid)
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .animation(nil, value: appState.sortOrder)
        .animation(nil, value: appState.sortAscending)
        .animation(nil, value: appState.searchText)
    }

    private func refreshBackdropPalette() {
        backdropPalette.refresh(activeSessions: appState.idleManager.activeSessions, games: appState.games)
    }

    private var utilityRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Stats")
                .font(.headline)
            UtilityStatRow(label: "Total games", value: "\(appState.games.count)")
            UtilityStatRow(label: "Idling now", value: "\(appState.idleManager.activeSessions.count)")
            UtilityStatRow(label: "Selected", value: "\(appState.selectedAppIDs.count)")
            UtilityStatRow(label: "Total idled", value: totalIdleHoursLabel)
            UtilityStatRow(label: "Sort", value: appState.sortOrder.displayLabel)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.93))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
    }

    private var compactUtilityPills: some View {
        HStack(spacing: 8) {
            UtilityPill(text: "\(appState.idleManager.activeSessions.count) idling")
            UtilityPill(text: "\(appState.selectedAppIDs.count) selected")
            UtilityPill(text: totalIdleHoursLabel)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No games yet")
                .font(.title3)
            Text("Add your API key in Settings.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func gameCard(for game: Game) -> some View {
        GameCardView(
            game: game,
            isSelected: appState.selectedAppIDs.contains(game.appid),
            isIdling: appState.idleManager.activeAppIDs.contains(game.appid),
            isLaunching: appState.launchingAppIDs.contains(game.appid)
        ) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                appState.toggleSelection(game)
            }
        } onStart: {
            appState.startIdle(game: game)
        } onStop: {
            appState.stopIdle(game: game)
        }
    }

    private var idlingGames: [Game] {
        let active = appState.idleManager.activeAppIDs
        return appState.filteredGames.filter { active.contains($0.appid) }
    }

    private var libraryGames: [Game] {
        let active = appState.idleManager.activeAppIDs
        return appState.filteredGames.filter { !active.contains($0.appid) }
    }

    private var spotlightGames: [Game] {
        let active = appState.idleManager.activeAppIDs
        // Single sort: active titles first, then by most-recently-played.
        let sorted = appState.games.sorted { lhs, rhs in
            let la = active.contains(lhs.appid)
            let ra = active.contains(rhs.appid)
            if la != ra { return la && !ra }
            return (lhs.lastPlayedAt ?? 0) > (rhs.lastPlayedAt ?? 0)
        }
        return Array(sorted.prefix(10))
    }

    private var heroSubtitle: String {
        if appState.idleManager.activeSessions.isEmpty {
            return "Pick a game to start."
        }
        return "\(appState.idleManager.activeSessions.count) idling now."
    }

    private var totalIdleHoursLabel: String {
        // Sum stored hours plus any currently-active session deltas; no per-appid lookup
        // against the full library so this stays cheap as the library grows.
        var total = idleTimeStore.hoursByAppID.values.reduce(0, +)
        for appid in appState.idleManager.activeAppIDs {
            total += idleTimeStore.hours(for: appid) - (idleTimeStore.hoursByAppID[appid] ?? 0)
        }
        if total < 10 {
            return String(format: "%.1fh", total)
        }
        return String(format: "%.0fh", total)
    }
}

/// Subscribes only to `IdleTimeStore` so the parent library grid doesn't re-body
/// every minute when the store ticks.
struct IdleHoursLabel: View {
    let appid: UInt64
    @ObservedObject private var store = IdleTimeStore.shared

    var body: some View {
        let label = store.formattedHours(for: appid)
        if !label.isEmpty {
            Text("(\(label))")
                .font(.caption)
                .foregroundStyle(.green.opacity(0.85))
        }
    }
}

private struct UtilityStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }
}

private struct UtilityPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}

private struct SortSegmentedControl: View {
    @Binding var selection: GameSortOrder
    @Namespace private var highlightNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(GameSortOrder.allCases) { order in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        selection = order
                    }
                } label: {
                    ZStack {
                        if selection == order {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.accentColor.opacity(0.9))
                                .matchedGeometryEffect(id: "sortHighlight", in: highlightNamespace)
                        }

                        Text(order.displayLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selection == order ? Color.white : Color.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .frame(minWidth: 100, minHeight: 32)
                    .background(
                        Rectangle().fill(Color.white.opacity(0.001))
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct MiniSpotlightCard: View {
    let game: Game
    let isIdling: Bool
    let isLaunching: Bool
    let onPrimary: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedRemoteImage(url: game.headerImageURL, contentMode: .fill) {
                Rectangle().fill(Color.gray.opacity(0.25))
            }
            .frame(height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(game.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(isIdling ? Color.green : Color.primary)

            IdleHoursLabel(appid: game.appid)

            if isLaunching {
                Label("Launching", systemImage: "hourglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Launching \(game.name)")
            } else if isIdling {
                Label("Idling", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Label("Click to idle", systemImage: "play.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isIdling ? Color.green.opacity(0.8) : Color.white.opacity(0.08), lineWidth: 1.5)
        )
        .scaleEffect(hovering ? 1.02 : 1.0)
        .shadow(color: .black.opacity(hovering ? 0.18 : 0.08), radius: hovering ? 8 : 4, y: hovering ? 4 : 2)
        .onHover { hovering = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            if !isIdling && !isLaunching {
                onPrimary()
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: hovering)
    }
}

private struct AnimatedGreetingText: View {
    let text: String
    @State private var sweep = false

    var body: some View {
        Text(text)
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .overlay {
                GeometryReader { proxy in
                    let width = max(proxy.size.width, 1)
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.24),
                            Color.white.opacity(0.95),
                            Color.white.opacity(0.24),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: width * 0.9)
                    .offset(x: sweep ? width : -width)
                }
                .mask(
                    Text(text)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                )
                .allowsHitTesting(false)
            }
            .shadow(color: Color.white.opacity(0.24), radius: 8, x: 0, y: 0)
            .onAppear {
                withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
    }
}

// MARK: - Right click

/// Catches right-clicks without showing context menus.
struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void

    final class CatcherView: NSView {
        var action: (() -> Void)?
        private lazy var rightClickRecognizer: NSClickGestureRecognizer = {
            let recognizer = NSClickGestureRecognizer(target: self, action: #selector(handleRightClick))
            recognizer.buttonMask = 0x2
            recognizer.numberOfClicksRequired = 1
            return recognizer
        }()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = false
            addGestureRecognizer(rightClickRecognizer)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        @objc private func handleRightClick(_ sender: NSClickGestureRecognizer) {
            action?()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp:
                return self
            default:
                return nil
            }
        }

        override func menu(for event: NSEvent) -> NSMenu? { nil }
    }

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.action = action
    }
}

// MARK: - Card

struct GameCardView: View {
    let game: Game
    let isSelected: Bool
    let isIdling: Bool
    let isLaunching: Bool
    let onToggleSelect: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    private let imageAspect: CGFloat = 460.0 / 215.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            artwork
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    if !isIdling && isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor, .white)
                            .padding(8)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .font(.headline)
                    .foregroundStyle(isIdling ? Color.green : Color.primary)
                    .lineLimit(2)
                    .frame(height: 40, alignment: .topLeading)

                Text(String(format: "%.1f hrs played", game.playtimeHours))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                IdleHoursLabel(appid: game.appid)
            }
            .padding(.horizontal, 2)

            HStack {
                Spacer()
                if isLaunching {
                    Label("Launching", systemImage: "hourglass")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Launching \(game.name)")
                } else if isIdling {
                    Button("Stop", role: .destructive, action: onStop)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .accessibilityLabel("Stop idling \(game.name)")
                } else {
                    Button("Idle", action: onStart)
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Start idling \(game.name)")
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderColor, lineWidth: isIdling || isSelected ? 2 : 1)
        )
        .shadow(color: shadowColor, radius: isHovered ? 10 : 4, x: 0, y: isHovered ? 4 : 2)
        .scaleEffect(scale)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            guard !isIdling && !isLaunching else { return }
            onToggleSelect()
        }
        .overlay(
            RightClickCatcher {
                if isLaunching { return }
                if isIdling { onStop() } else { onStart() }
            }
            .allowsHitTesting(true)
        )
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 40, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isSelected)
        .animation(.easeInOut(duration: 0.18), value: isIdling)
        .animation(.easeInOut(duration: 0.18), value: isLaunching)
    }

    private var artwork: some View {
        CachedRemoteImage(url: game.headerImageURL, contentMode: .fill) {
            Rectangle()
                .fill(Color.gray.opacity(0.25))
                .aspectRatio(imageAspect, contentMode: .fit)
        }
        .aspectRatio(imageAspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private var scale: CGFloat {
        if isPressed { return 0.98 }
        if isHovered { return 1.02 }
        return 1
    }

    private var borderColor: Color {
        if isIdling { return .green }
        if isSelected { return .accentColor }
        if isHovered { return Color(nsColor: .separatorColor).opacity(0.6) }
        return Color(nsColor: .separatorColor).opacity(0.35)
    }

    private var shadowColor: Color {
        Color.black.opacity(isHovered ? 0.18 : 0.08)
    }
}
