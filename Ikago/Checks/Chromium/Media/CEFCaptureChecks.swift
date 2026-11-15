import AVFoundation
import AppKit
import IKCEFBridge

/// Only called inside the disposable smoke profile; the runtime supplies fake devices.
@MainActor
enum CEFCaptureChecks {
    static func run(_ page: IKCEFPage, url: String) async throws {
        var request: IKCEFMediaRequest?
        var active = false
        let previous = page.eventHandler
        page.eventHandler = { event, payload in
            previous?(event, payload)
            if event == "capture" { active = payload["camera"] as? Bool == true || payload["microphone"] as? Bool == true }
        }
        page.mediaPermissionHandler = { request = $0 }
        defer { page.mediaPermissionHandler = nil; page.eventHandler = previous }
        let script = "navigator.mediaDevices.getUserMedia({audio:true,video:true}).then(s=>{window.fixtureStream=s;window.fixtureCapture='allowed'},e=>{window.fixtureCapture='denied';window.fixtureCaptureError=e.name+': '+e.message});true"
        _ = try await CEFSmoke.method(page, "Runtime.evaluate", ["expression": script])
        try await wait { request != nil }
        guard request?.camera == true, request?.microphone == true else { throw CEFError.script("Capture request lost device kinds.") }
        request?.resolve(false)
        try await flag(page, equals: "denied")
        guard !active else { throw CEFError.script("Denied capture became active.") }
        request = nil
        // Even fake devices need macOS authorization, and requesting it shows a real
        // system prompt, so an unattended fixture only exercises allow when already granted.
        let authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if authorized {
        _ = try await CEFSmoke.method(page, "Runtime.evaluate", ["expression": script])
        try await wait { request != nil }
        request?.resolve(true)
        try await flag(page, equals: "allowed")
        try await wait { active }
        page.stopCaptureAndReload()
        try await wait { !active && !page.loading }
        request = nil
        _ = try await CEFSmoke.method(page, "Runtime.evaluate", ["expression": script])
        try await flag(page, equals: "denied")
        guard request == nil, !active else { throw CEFError.script("Stopped capture restarted without a manual reload.") }
        }
        page.loadURL(url)
        try await Task.sleep(for: .milliseconds(200))
        try await wait { !page.loading }
        _ = try await CEFSmoke.method(page, "Runtime.evaluate", ["expression": script])
        try await wait { request != nil }
        let pending = request!
        var cancelled = false
        pending.cancellationHandler = { cancelled = true }
        page.loadURL(url)
        try await wait { cancelled && pending.resolved && !page.loading }
        pending.resolve(true) // Stale UI must not grant the new document anything.
        guard !active else { throw CEFError.script("A stale capture request survived navigation.") }
        print(authorized ? "CEF_CAPTURE_OK fake-devices deny allow active stop-reload restart-blocked navigation-cancel"
            : "CEF_CAPTURE_PARTIAL deny navigation-cancel; allow/stop not exercised, macOS capture authorization not granted")
    }
    private static func flag(_ page: IKCEFPage, equals value: String) async throws {
        for _ in 0..<100 {
            let result = try? await CEFSmoke.method(page, "Runtime.evaluate", ["expression": "window.fixtureCapture", "returnByValue": true])
            if (result?["result"] as? [String: Any])?["value"] as? String == value { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        let failure = try? await CEFSmoke.method(page, "Runtime.evaluate", ["expression": "String(window.fixtureCaptureError)", "returnByValue": true])
        let reason = (failure?["result"] as? [String: Any])?["value"] as? String ?? "unknown"
        throw CEFError.script("Fake capture did not reach \(value): \(reason); macOS camera=\(AVCaptureDevice.authorizationStatus(for: .video).rawValue), microphone=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue).")
    }
    private static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(for: .milliseconds(50)) }
        throw CEFError.script("Capture fixture timed out.")
    }
}
