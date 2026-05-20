import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var step: OnboardingStep = .welcome
    @State private var apiKeyInput: String = ""
    @State private var testStatus: TestStatus = .idle
    @State private var pulse = false

    enum TestStatus: Equatable {
        case idle
        case testing
        case success(Int)
        case failure(String)
    }

    var body: some View {
        ZStack {
            AnimatedBackground()

            VStack(spacing: 0) {
                header
                ZStack {
                    switch step {
                    case .welcome:
                        onboardingCard { welcomeStep }
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    case .apiKey:
                        onboardingCard { apiKeyStep }
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    case .stylePicker:
                        onboardingCard { stylePickerStep }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 28)
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: step)
            }
            .padding(.top, 16)
        }
        .frame(minWidth: 760, minHeight: 560)
        .onAppear { pulse = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Steam Idle Mac Setup")
                        .font(.title.bold())
                    Text("Fast setup, smooth idling, done in 3 steps.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(step.rawValue >= s.rawValue ? Color.accentColor : Color.white.opacity(0.18))
                        .frame(height: 6)
                        .scaleEffect(step.rawValue == s.rawValue && pulse ? 1.06 : 1.0)
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: step)
                }
            }
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 18)
    }

    private func onboardingCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(26)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Welcome to Steam Idle Mac")
                .font(.largeTitle.bold())

            Text("Idle multiple Steam games with lightweight helper processes without launching full games.")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                FeatureTile(title: "Up to 32 games", symbol: "rectangle.3.group.fill")
                FeatureTile(title: "Steam signed in", symbol: "person.crop.circle.badge.checkmark")
                FeatureTile(title: "Safe choices", symbol: "shield.lefthalf.filled")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Avoid VAC-protected multiplayer games.", systemImage: "exclamationmark.triangle.fill")
                    Label("You can tweak visual style later in Settings.", systemImage: "paintpalette.fill")
                }
                .font(.subheadline)
            } label: {
                Label("Quick notes", systemImage: "sparkles")
                    .font(.headline)
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Get started") { step = .apiKey }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add your Steam Web API key")
                .font(.title.bold())
            Text("Used to load your owned games. Stored locally in macOS Keychain only.")
                .foregroundStyle(.secondary)

            HStack {
                Link("Open Steam API key page", destination: URL(string: "https://steamcommunity.com/dev/apikey")!)
                    .buttonStyle(.bordered)
                Spacer()
            }

            SecureField("Paste API key here", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Button("Test key") { validateAPIKey() }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                statusView
                Spacer()
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
            HStack {
                Button("Back") { step = .welcome }
                Spacer()
                Button("Continue") {
                    Task {
                        try? appState.saveSettings()
                        await appState.refreshLibrary(force: true)
                        step = .stylePicker
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled({
                    if case .success = testStatus { return false }
                    return true
                }())
            }
        }
        .onAppear {
            apiKeyInput = appState.apiKey
            appState.apiKey = apiKeyInput
            let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                validateAPIKey()
            }
        }
        .onChange(of: apiKeyInput) { new in
            appState.apiKey = new
            testStatus = .idle
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
            Label("\(count) games found", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
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
        testStatus = .testing
        Task {
            do {
                try appState.saveSettings()
                await appState.refreshLibrary(force: true)
                if let err = appState.errorMessage, appState.games.isEmpty {
                    testStatus = .failure(err)
                    appState.errorMessage = nil
                } else {
                    testStatus = .success(appState.games.count)
                }
            } catch {
                testStatus = .failure(error.localizedDescription)
            }
        }
    }

    private var stylePickerStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose your idle look")
                .font(.title.bold())
            Text("Pick the floating style used while a game is idling.")
                .foregroundStyle(.secondary)

            if let game = appState.topPlaytimeGame {
                HStack(spacing: 22) {
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
            } else if appState.isLoadingLibrary {
                ProgressView("Loading your library...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Couldn't load your games. Make sure your API key is correct.")
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)
            HStack {
                Button("Back") { step = .apiKey }
                Spacer()
                Button("Finish") {
                    appState.completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct FeatureTile: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
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
            }
            .padding(12)
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor).opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 2)
            )
            .shadow(color: .black.opacity(hovering ? 0.22 : 0.08), radius: hovering ? 14 : 6, y: hovering ? 6 : 3)
            .scaleEffect(hovering ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: hovering)
    }
}
