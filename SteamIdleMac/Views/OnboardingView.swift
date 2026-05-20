import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var apiKeyInput: String = ""
    @State private var testStatus: TestStatus = .idle
    @State private var validationTask: Task<Void, Never>?
    @State private var finishTask: Task<Void, Never>?
    @State private var previewGames: [Game] = []
    @State private var previewIndex = 0
    @State private var rotatePreview = false
    @State private var previewRotationTask: Task<Void, Never>?

    enum TestStatus: Equatable {
        case idle
        case testing
        case success(Int)
        case failure(String)
    }

    var body: some View {
        ZStack {
            AnimatedBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    sectionCard(title: "Steam API key", subtitle: "Load your library and profile") {
                        apiKeySection
                    }
                    sectionCard(title: "Banner style", subtitle: "Pick your floating idle look") {
                        stylePickerSection
                    }
                    finishRow
                        .padding(.horizontal, 2)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 36)
                .padding(.top, 22)
                .padding(.bottom, 28)
            }
        }
        .frame(minWidth: 840, minHeight: 620)
        .onAppear {
            apiKeyInput = appState.apiKey
            appState.apiKey = apiKeyInput
            rebuildPreviewGames()
            startPreviewRotation()
            let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                validateAPIKey()
            }
        }
        .onChange(of: appState.games) { _ in
            rebuildPreviewGames()
            startPreviewRotation()
        }
        .onDisappear {
            validationTask?.cancel()
            finishTask?.cancel()
            previewRotationTask?.cancel()
            rotatePreview = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlowingTitleText(text: "Setup")
        }
        .padding(.horizontal, 2)
    }

    private func sectionCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content()
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

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let url = AppLinks.steamAPIKey {
                Link(destination: url) {
                    HStack(spacing: 8) {
                        Image(systemName: "safari")
                        Text("Open API key page")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            SecureField("Paste API key", text: $apiKeyInput)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
                .onChange(of: apiKeyInput) { new in
                    appState.apiKey = new
                    testStatus = .idle
                }

            HStack(spacing: 10) {
                Button("Test key") { validateAPIKey() }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                statusView
                Spacer()
            }
        }
    }

    private var stylePickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let game = currentPreviewGame {
                HStack(spacing: 16) {
                    ForEach(BannerStyle.allCases) { style in
                        StylePreviewCard(
                            game: game,
                            style: style,
                            selected: appState.bannerStyle == style
                        ) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                                appState.bannerStyle = style
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.22), value: previewIndex)
            } else if appState.isLoadingLibrary {
                ProgressView("Loading your library...")
                    .frame(maxWidth: .infinity)
            } else {
                Text("Test your API key to load preview games.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var finishRow: some View {
        HStack {
            Spacer()
            Button("Finish setup") { finishSetup() }
                .buttonStyle(.plain)
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.accentColor.opacity(0.9)))
                .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                .disabled({
                    if case .success = testStatus { return false }
                    return true
                }())
                .keyboardShortcut(.defaultAction)
        }
    }

    private var currentPreviewGame: Game? {
        guard !previewGames.isEmpty else { return nil }
        let index = max(0, min(previewIndex, previewGames.count - 1))
        return previewGames[index]
    }

    private func rebuildPreviewGames() {
        let source = appState.games.shuffled()
        if source.isEmpty {
            previewGames = []
            previewIndex = 0
            return
        }
        previewGames = Array(source.prefix(24))
        previewIndex = 0
    }

    private func startPreviewRotation() {
        rotatePreview = true
        previewRotationTask?.cancel()
        previewRotationTask = Task { @MainActor in
            while rotatePreview {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard rotatePreview, !previewGames.isEmpty else { continue }
                let nextIndex = (previewIndex + 1) % previewGames.count
                let nextGame = previewGames[nextIndex]
                let ready = await areAssetsReady(for: nextGame)
                guard rotatePreview, !Task.isCancelled else { return }
                guard ready else { continue }
                withAnimation(.easeInOut(duration: 0.22)) {
                    previewIndex = nextIndex
                }
            }
        }
    }

    private func areAssetsReady(for game: Game?) async -> Bool {
        guard let game else { return false }
        guard let headerURL = game.headerImageURL else { return false }
        let iconURL = game.widgetIconURL ?? game.iconImageURL
        guard let iconURL else { return false }

        var headerReady = RemoteImageCache.shared.image(for: headerURL) != nil
        var iconReady = RemoteImageCache.shared.image(for: iconURL) != nil
        if !headerReady {
            headerReady = await RemoteImageCache.shared.load(headerURL) != nil
        }
        if !iconReady {
            iconReady = await RemoteImageCache.shared.load(iconURL) != nil
        }
        return headerReady && iconReady
    }

    private func finishSetup() {
        finishTask?.cancel()
        finishTask = Task { @MainActor in
            do {
                try appState.saveSettings()
                await appState.refreshLibrary(force: true)
                appState.completeOnboarding()
            } catch {
                testStatus = .failure(error.localizedDescription)
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch testStatus {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView()
                .controlSize(.small)
            Text("Testing...")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .success(let count):
            Label("\(count) games", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption.weight(.semibold))
        case .failure(let msg):
            Label(msg, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(2)
        }
    }

    private func validateAPIKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        validationTask?.cancel()
        testStatus = .testing
        validationTask = Task { @MainActor in
            do {
                try appState.saveSettings()
                await appState.refreshLibrary(force: true)
                guard !Task.isCancelled else { return }
                rebuildPreviewGames()
                if let err = appState.errorMessage, appState.games.isEmpty {
                    testStatus = .failure(err)
                    appState.errorMessage = nil
                } else {
                    testStatus = .success(appState.games.count)
                }
            } catch {
                guard !Task.isCancelled else { return }
                testStatus = .failure(error.localizedDescription)
            }
        }
    }
}

private struct GlowingTitleText: View {
    let text: String
    @State private var sweep = false

    var body: some View {
        Text(text)
            .font(.system(size: 48, weight: .bold, design: .rounded))
            .overlay {
                GeometryReader { proxy in
                    let width = max(proxy.size.width, 1)
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.20),
                            Color.white.opacity(0.75),
                            Color.white.opacity(0.20),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: width * 0.85)
                    .offset(x: sweep ? width : -width * 0.9)
                }
                .mask(
                    Text(text)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                )
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 3.6).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
    }
}

private struct AnimatedBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.16), Color(red: 0.06, green: 0.18, blue: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.accentColor.opacity(0.20))
                .frame(width: 420, height: 420)
                .blur(radius: 40)
                .offset(x: animate ? 220 : -180, y: animate ? -150 : 140)

            Circle()
                .fill(Color.purple.opacity(0.18))
                .frame(width: 300, height: 300)
                .blur(radius: 36)
                .offset(x: animate ? -220 : 200, y: animate ? 180 : -130)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

private struct StylePreviewCard: View {
    let game: Game
    let style: BannerStyle
    let selected: Bool
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                IdleBannerView(game: game, style: style)
                    .allowsHitTesting(false)
                    .scaleEffect(style == .landscape ? 0.6 : 0.8)
                    .frame(width: 280, height: 200)
                Text(style.displayName)
                    .font(.subheadline.bold())
                    .foregroundStyle(selected ? Color.white : Color.primary)
            }
            .padding(12)
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: selected
                                ? [Color.accentColor.opacity(0.34), Color.purple.opacity(0.24)]
                                : [Color.white.opacity(0.10), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.20), lineWidth: selected ? 2 : 1)
            )
            .shadow(color: .black.opacity(hovering ? 0.22 : 0.09), radius: hovering ? 14 : 7, y: hovering ? 6 : 3)
            .scaleEffect(hovering ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: hovering)
    }
}
