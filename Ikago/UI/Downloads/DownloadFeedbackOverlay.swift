import AppKit
import SwiftUI

/// Visual feedback lives above the page and never participates in hit testing or download work.
struct DownloadFeedbackOverlay: View {
    /// The Downloads button and the page, in this overlay's coordinates.
    let toolbar: CGRect?
    let page: CGRect?
    let colors: Palette
    let content: NSView
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flights: [Flight] = []
    @State private var pendingID: UUID?

    private struct Flight: Identifiable {
        let id: UUID
        let start: CGPoint
        let end: CGPoint
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(flights) { flight in
                    DownloadFlight(start: flight.start, end: flight.end, colors: colors) {
                        flights.removeAll { $0.id == flight.id }
                    }
                }
            }
            .onChange(of: DownloadCenter.shared.items.map(\.id)) { old, new in
                guard !reduceMotion, content.window?.isKeyWindow == true else { return }
                let added = Set(new).subtracting(old)
                // Coalesce simultaneous downloads into one cue instead of covering the page.
                if let id = new.first(where: { added.contains($0) }) { pendingID = id }
                launch(in: geometry)
            }
            // The automatic button may be inserted by the same update that starts a download.
            .onChange(of: toolbar) { _, _ in launch(in: geometry) }
            .onChange(of: pendingID) { _, _ in launch(in: geometry) }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced { flights.removeAll(); pendingID = nil }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func launch(in geometry: GeometryProxy) {
        guard let id = pendingID, let destination = toolbar, let source = page else { return }
        flights.append(Flight(id: id,
            start: CGPoint(x: source.midX, y: source.minY + min(180, source.height * 0.3)),
            end: CGPoint(x: destination.midX, y: destination.midY)))
        pendingID = nil
    }
}

private struct DownloadFlight: View {
    let start: CGPoint
    let end: CGPoint
    let colors: Palette
    let finished: () -> Void
    @State private var progress: CGFloat = 0

    var body: some View {
        Image(systemName: "doc.fill")
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(colors.accent)
            .frame(width: 40, height: 40)
            .background(.background, in: .rect(cornerRadius: 10))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .modifier(DownloadFlightPath(progress: progress, start: start, end: end))
            .task {
                withAnimation(.easeInOut(duration: 0.6)) { progress = 1 }
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled else { return }
                finished()
            }
    }
}

private struct DownloadFlightPath: AnimatableModifier {
    nonisolated var progress: CGFloat
    let start: CGPoint
    let end: CGPoint
    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let arc = sin(progress * .pi) * 40
        content
            .scaleEffect(1 - progress * 0.75)
            .opacity(Double(min(1, progress * 12) * min(1, (1 - progress) * 8)))
            .position(x: start.x + (end.x - start.x) * progress,
                      y: start.y + (end.y - start.y) * progress - arc)
    }
}
