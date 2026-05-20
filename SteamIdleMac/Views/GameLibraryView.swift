import AppKit
import SwiftUI

private enum LibraryGridMetrics {
    static let cardMinWidth: CGFloat = 220
    static let spacing: CGFloat = 16
    static let horizontalPadding: CGFloat = 20
}

struct GameLibraryView: View {
    @EnvironmentObject private var appState: AppState
    @Namespace private var cardNamespace
    @State private var appear = false

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: LibraryGridMetrics.cardMinWidth), spacing: LibraryGridMetrics.spacing)]
    }

    var body: some View {
        GeometryReader { proxy in
            let showRail = proxy.size.width >= 1220

            ZStack {
                DashboardBackground()

                if appState.isLoadingLibrary && appState.games.isEmpty {
                    ProgressView("Loading library...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if appState.games.isEmpty {
                    emptyState
                } else {
                    contentLayout(showRail: showRail)
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) {
                    appear = true
                }
            }
        }
    }

    private func contentLayout(showRail: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroHeader
                        .padding(.horizontal, LibraryGridMetrics.horizontalPadding)
                        .offset(y: appear ? 0 : -16)
                        .opacity(appear ? 1 : 0.5)

                    controlBar
                        .padding(.horizontal, LibraryGridMetrics.horizontalPadding)

                    if !spotlightGames.isEmpty {
                        sectionCard(title: "Continue Playing", subtitle: "Recent and currently active titles") {
                            spotlightStrip
                        }
                        .padding(.horizontal, LibraryGridMetrics.horizontalPadding)
                    }

                    if !idlingGames.isEmpty {
                        sectionCard(title: "Idling", subtitle: "\(idlingGames.count) games actively earning time") {
                            libraryGrid(games: idlingGames)
                        }
                        .padding(.horizontal, LibraryGridMetrics.horizontalPadding)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    sectionCard(title: "Library", subtitle: "\(libraryGames.count) games available") {
                        libraryGrid(games: libraryGames)
                    }
                    .padding(.horizontal, LibraryGridMetrics.horizontalPadding)
                }
                .padding(.vertical, 18)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: idlingGames.map(\.appid))
            }

            if showRail {
                utilityRail
                    .frame(width: 300)
                    .padding(.trailing, 20)
                    .padding(.top, 18)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
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
            AsyncImage(url: appState.profileAvatarURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.10))
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text("Hello, \(appState.greetingName)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
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
                    Task {
                        await appState.refreshLibrary(force: true)
                        await appState.refreshProfile(force: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(appState.isLoadingLibrary || appState.isLoadingProfile)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
    }

    private var controlBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search games", text: $appState.searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
                )
                .frame(maxWidth: 280)

                Picker("", selection: $appState.sortOrder) {
                    ForEach(GameSortOrder.allCases) { order in
                        Text(order.displayLabel).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        appState.toggleSortDirection()
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(appState.sortAscending ? 0 : 180))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .help(appState.sortOrder.directionHelp(ascending: appState.sortAscending))

                Spacer()

                if !appState.selectedAppIDs.isEmpty {
                    Text("\(appState.selectedAppIDs.count) selected")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                        .transition(.scale.combined(with: .opacity))
                }

                Button {
                    appState.showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(.bordered)
                .help("Settings")
            }

            Text("Steam profile status can take a few seconds to update after start/stop.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: appState.selectedAppIDs.count)
    }

    private func sectionCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    private var spotlightStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(spotlightGames) { game in
                    MiniSpotlightCard(
                        game: game,
                        isIdling: appState.idleManager.activeAppIDs.contains(game.appid),
                        isLaunching: appState.launchingAppIDs.contains(game.appid),
                        idleHoursLabel: appState.idleTimeStore.formattedHours(for: game.appid),
                        onPrimary: {
                            if appState.idleManager.activeAppIDs.contains(game.appid) {
                                appState.stopIdle(game: game)
                            } else {
                                appState.startIdle(game: game)
                            }
                        }
                    )
                    .frame(width: 230)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func libraryGrid(games: [Game]) -> some View {
        LazyVGrid(columns: columns, spacing: LibraryGridMetrics.spacing) {
            ForEach(games) { game in
                gameCard(for: game)
                    .matchedGeometryEffect(id: game.appid, in: cardNamespace)
            }
        }
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    private var compactUtilityPills: some View {
        HStack(spacing: 8) {
            UtilityPill(text: "\(appState.idleManager.activeSessions.count) idling")
            UtilityPill(text: "\(appState.selectedAppIDs.count) selected")
            UtilityPill(text: totalIdleHoursLabel)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No games loaded")
                .font(.title3)
            Text("Add your API key and refresh.")
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
            isLaunching: appState.launchingAppIDs.contains(game.appid),
            idleHoursLabel: appState.idleTimeStore.formattedHours(for: game.appid)
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
        let sortedByRecent = appState.games.sorted { ($0.lastPlayedAt ?? 0) > ($1.lastPlayedAt ?? 0) }
        let activeFirst = sortedByRecent.sorted { lhs, rhs in
            let la = active.contains(lhs.appid)
            let ra = active.contains(rhs.appid)
            if la != ra { return la && !ra }
            return (lhs.lastPlayedAt ?? 0) > (rhs.lastPlayedAt ?? 0)
        }
        return Array(activeFirst.prefix(10))
    }

    private var heroSubtitle: String {
        if appState.idleManager.activeSessions.isEmpty {
            return "Ready to idle your next game."
        }
        return "\(appState.idleManager.activeSessions.count) game(s) currently idling."
    }

    private var totalIdleHoursLabel: String {
        let appids = Set(appState.games.map(\.appid)).union(appState.idleTimeStore.hoursByAppID.keys)
        let total = appids.reduce(0.0) { partial, appid in
            partial + appState.idleTimeStore.hours(for: appid)
        }
        if total < 10 {
            return String(format: "%.1fh", total)
        }
        return String(format: "%.0fh", total)
    }
}

private struct DashboardBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.12),
                    Color(red: 0.08, green: 0.14, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.blue.opacity(0.18))
                .frame(width: 360, height: 360)
                .blur(radius: 40)
                .offset(x: animate ? 180 : -160, y: animate ? -130 : 140)

            Circle()
                .fill(Color.green.opacity(0.14))
                .frame(width: 280, height: 280)
                .blur(radius: 34)
                .offset(x: animate ? -220 : 180, y: animate ? 130 : -140)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animate = true
            }
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

private struct MiniSpotlightCard: View {
    let game: Game
    let isIdling: Bool
    let isLaunching: Bool
    let idleHoursLabel: String
    let onPrimary: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: game.headerImageURL) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .aspectRatio(460.0 / 215.0, contentMode: .fill)
                } else {
                    Rectangle().fill(Color.gray.opacity(0.25))
                }
            }
            .frame(height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(game.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(isIdling ? Color.green : Color.primary)

            if !idleHoursLabel.isEmpty {
                Text(idleHoursLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button(isIdling ? "Stop" : (isLaunching ? "Launching..." : "Idle")) {
                onPrimary()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isLaunching)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isIdling ? Color.green.opacity(0.8) : Color.white.opacity(0.08), lineWidth: 1.5)
        )
        .scaleEffect(hovering ? 1.02 : 1.0)
        .shadow(color: .black.opacity(hovering ? 0.18 : 0.08), radius: hovering ? 8 : 4, y: hovering ? 4 : 2)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: hovering)
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
    let idleHoursLabel: String
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
                            .transition(.scale.combined(with: .opacity))
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .font(.headline)
                    .foregroundStyle(isIdling ? Color.green : Color.primary)
                    .lineLimit(2)
                    .frame(height: 40, alignment: .topLeading)
                    .animation(.easeInOut(duration: 0.2), value: isIdling)

                Text(String(format: "%.1f hrs played", game.playtimeHours))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !idleHoursLabel.isEmpty {
                    Text("(\(idleHoursLabel))")
                        .font(.caption)
                        .foregroundStyle(.green.opacity(0.85))
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 2)

            HStack {
                Spacer()
                if isLaunching {
                    Label("Launching", systemImage: "hourglass")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                } else if isIdling {
                    Button("Stop", role: .destructive, action: onStop)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .tint(.red)
                } else {
                    Button("Idle", action: onStart)
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
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
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
        .animation(.easeInOut(duration: 0.2), value: isIdling)
    }

    private var artwork: some View {
        AsyncImage(url: game.headerImageURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(imageAspect, contentMode: .fill)
            default:
                Rectangle()
                    .fill(Color.gray.opacity(0.25))
                    .aspectRatio(imageAspect, contentMode: .fit)
            }
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
