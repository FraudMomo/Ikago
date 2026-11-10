import SwiftUI

/// Origin-labelled, fail-closed permission prompt. Every path except "Allow" denies:
/// Don't Allow, Esc, closing the tab, or the request being dropped (PermissionRequest
/// denies itself on dealloc).
struct PermissionPromptSheet: View {
    let request: PermissionRequest
    let onDecision: (PermissionRequest.Decision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(origin).font(.headline).textSelection(.enabled)
                    Text("wants to \(description)").foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Don't Allow", role: .cancel) { onDecision(.deny) }
                    .keyboardShortcut(.cancelAction)
                Button("Allow") { onDecision(.allow) }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var origin: String {
        URLComponents(string: request.origin)?.host ?? request.origin
    }

    private var description: String {
        switch (request.kinds.contains(.camera), request.kinds.contains(.microphone)) {
        case (true, true): "use your camera and microphone"
        case (true, false): "use your camera"
        default: "use your microphone"
        }
    }

    private var symbol: String { request.kinds.contains(.camera) ? "video.fill" : "mic.fill" }
}
