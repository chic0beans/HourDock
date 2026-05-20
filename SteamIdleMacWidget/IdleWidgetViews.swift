import SwiftUI
import WidgetKit

struct IdleWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: IdleWidgetEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumBody
        default:
            smallBody
        }
    }

    private var smallBody: some View {
        let count = entry.snapshot.sessions.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: count > 0 ? "bolt.fill" : "moon.zzz")
                    .foregroundStyle(count > 0 ? .green : .secondary)
                Text("Steam Idle")
                    .font(.caption.bold())
            }
            Text(count == 0 ? "No idles" : "\(count) idling")
                .font(.title2.bold())
            if count > 0, let first = entry.snapshot.sessions.first {
                Text(first.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }

    private var mediumBody: some View {
        let sessions = entry.snapshot.sessions
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: sessions.isEmpty ? "moon.zzz" : "bolt.fill")
                    .foregroundStyle(sessions.isEmpty ? .secondary : .green)
                Text(sessions.isEmpty ? "No active idles" : "\(sessions.count)/32 idling")
                    .font(.headline)
            }

            if sessions.isEmpty {
                Text("Start idling in HourDock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions.prefix(6)) { session in
                    HStack(spacing: 8) {
                        WidgetGameIcon(url: session.iconURL)
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(session.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                if sessions.count > 6 {
                    Text("+\(sessions.count - 6) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

private struct WidgetGameIcon: View {
    let url: URL?

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle().fill(Color.gray.opacity(0.25))
    }
}
