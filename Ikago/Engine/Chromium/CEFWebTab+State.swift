import AppKit
import WebKit

extension CEFWebTab {
    func reportMedia() {
        delegate?.webTab(self, didChangeMedia: isAudible, camera: cameraActive ? .active : .none,
                         microphone: microphoneActive ? .active : .none)
    }
    /// In a window and not parked; background tabs check less often for new playback.
    var isPageShown: Bool { page.window != nil && !page.isHiddenOrHasHiddenAncestor }

    func observePageState() {
        guard stateTask == nil, !isTornDown else { return }
        stateTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let delay = self?.isPageShown == true || self?.playback.available == true ? 1 : 3
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self, !isTornDown else { return }
                let generation = documentGeneration
                let reports = await mediaFrames()
                guard generation == documentGeneration, !isTornDown else { continue }
                updatePlayback(reports)
                guard page.ready, let state = try? await evaluate("""
                    (() => {
                      const meta = document.querySelector('meta[name="theme-color"]');
                      let color = null;
                      if (meta && CSS.supports('color', meta.content)) {
                        const c = document.createElement('canvas'); c.width = c.height = 1;
                        const x = c.getContext('2d'); x.fillStyle = meta.content; x.fillRect(0,0,1,1);
                        color = [...x.getImageData(0,0,1,1).data];
                      }
                      return {color};
                    })()
                    """) as? [String: Any] else { continue }
                let color = (state["color"] as? [Double]).flatMap { parts -> NSColor? in
                    guard parts.count == 4 else { return nil }
                    return NSColor(srgbRed: parts[0]/255, green: parts[1]/255, blue: parts[2]/255, alpha: parts[3]/255)
                }
                if color != lastPolledThemeColor {
                    lastPolledThemeColor = color
                    delegate?.webTab(self, didChangeThemeColor: color)
                }
            }
        }
    }
}
