import SwiftUI

/// One gesture handles both a tap on the track and dragging the thumb. Only
/// committing the gesture seeks audio; playback ticks cannot override a drag.
struct SeekBar: View {
    @Binding var value: Double
    let duration: Double
    let tint: Color
    let onEditingChanged: (Bool) -> Void
    @State private var dragging = false
    private let thumbSize: CGFloat = 24
    private var limit: Double { duration.isFinite ? max(0, duration) : 0 }
    private var fraction: Double { limit > 0 ? min(1, max(0, value / limit)) : 0 }

    var body: some View {
        GeometryReader { geometry in
            let travel = max(1, geometry.size.width - thumbSize)
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.22)).frame(height: 5).padding(.horizontal, thumbSize / 2)
                Capsule().fill(tint).frame(width: travel * CGFloat(fraction), height: 5).offset(x: thumbSize / 2)
                Circle().fill(tint).frame(width: thumbSize, height: thumbSize).offset(x: travel * CGFloat(fraction))
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !dragging { dragging = true; onEditingChanged(true) }
                        value = position(at: gesture.location.x, travel: travel)
                    }
                    .onEnded { gesture in
                        value = position(at: gesture.location.x, travel: travel)
                        dragging = false; onEditingChanged(false)
                    })
        }.frame(height: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("再生位置")
            .accessibilityIdentifier("seek-bar")
            .accessibilityValue("\(Int(fraction * 100))%")
            .accessibilityAdjustableAction { direction in
                guard limit > 0 else { return }
                onEditingChanged(true)
                switch direction {
                case .increment: value = min(limit, value + 10)
                case .decrement: value = max(0, value - 10)
                @unknown default: break
                }
                onEditingChanged(false)
            }
            .allowsHitTesting(limit > 0)
    }

    private func position(at x: CGFloat, travel: CGFloat) -> Double {
        Double(min(1, max(0, (x - thumbSize / 2) / travel))) * limit
    }
}
