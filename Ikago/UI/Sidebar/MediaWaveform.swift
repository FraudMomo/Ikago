import SwiftUI

/// The Dynamic Island's wave: fine bars in the artwork's color, following the real sound's voice and music bands.
///
/// Only drawn when there are real levels: Chromium pages, whose sound Ikago plays itself (`IKCEFAudio`). WebKit plays
/// its sound out of Ikago's reach, so there is no wave at all rather than a made-up one.
struct MediaWaveform: View {
    /// Reads the current band levels, or nil when there is no source for them.
    let levels: () -> [CGFloat]?
    let active: Bool
    let color: Color
    var height: CGFloat = 14

    /// Low to high, left to right: the middle bars carry the bands voices and melodies live in, so the wave peaks in
    /// the centre like the iPhone's.
    private static let order = [0, 1, 2, 3, 4]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { _ in
            if let live = levels() {
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<Self.order.count, id: \.self) { index in
                        Capsule()
                            .fill(color.opacity(0.92))
                            .frame(width: 2, height: barHeight(live, band: Self.order[index]))
                    }
                }
                .frame(height: height)
                .animation(.linear(duration: 1.0 / 30), value: live)
                .transition(.opacity)
            }
        }
        .accessibilityHidden(true)
    }

    private func barHeight(_ live: [CGFloat], band: Int) -> CGFloat {
        let rest: CGFloat = 2
        guard active, live.indices.contains(band) else { return rest }
        return rest + (height - rest) * min(1, max(0, live[band]))
    }
}
