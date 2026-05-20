import SwiftUI
import WidgetKit

struct IdleWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: IdleSnapshot
}

struct SteamIdleMacWidget: Widget {
    let kind = "SteamIdleMacWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: IdleWidgetProvider()) { entry in
            IdleWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Steam Idle")
        .description("Shows games you are currently idling.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct IdleWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> IdleWidgetEntry {
        IdleWidgetEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (IdleWidgetEntry) -> Void) {
        completion(IdleWidgetEntry(date: Date(), snapshot: IdleSnapshotReader.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<IdleWidgetEntry>) -> Void) {
        let snapshot = IdleSnapshotReader.load()
        let entry = IdleWidgetEntry(date: Date(), snapshot: snapshot)
        let next = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date().addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
