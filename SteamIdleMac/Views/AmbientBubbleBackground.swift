import AppKit
import SwiftUI

struct AmbientBubbleBackground: View {
    let specs: [AmbientBubbleSpec]
    var dimWhenInactive: Bool = false

    @State private var isWindowActive = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.07, blue: 0.11),
                        Color(red: 0.07, green: 0.13, blue: 0.17)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ForEach(Array(specs.enumerated()), id: \.element.id) { idx, spec in
                    let orbitX = sin((t * spec.speed) + spec.phase) * spec.drift.width
                    let orbitY = cos((t * (spec.speed * 0.83)) + (spec.phase * 1.17)) * spec.drift.height
                    let interaction = sin((t * 0.9) + (Double(idx) * 1.35)) * CGFloat(8 + specs.count * 2)
                    let x = spec.offset.width + orbitX + interaction
                    let y = spec.offset.height + orbitY - (interaction * 0.55)

                    ZStack {
                        Circle()
                            .fill(spec.color.opacity(spec.intensity))
                            .frame(width: spec.diameter, height: spec.diameter)
                            .blur(radius: max(24, spec.diameter * 0.10))

                        Circle()
                            .fill(spec.color.opacity(spec.intensity * 0.55))
                            .frame(width: spec.diameter * 0.58, height: spec.diameter * 0.58)
                            .blur(radius: max(14, spec.diameter * 0.05))
                    }
                    .blendMode(.plusLighter)
                    .offset(x: x, y: y)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            guard dimWhenInactive else { return }
            isWindowActive = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            guard dimWhenInactive else { return }
            isWindowActive = true
        }
        .drawingGroup(opaque: false)
        .opacity(dimWhenInactive ? (isWindowActive ? 1 : 0.6) : 1)
    }
}
