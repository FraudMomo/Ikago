import Foundation

/// Page zoom in 10 % steps, as the site card, View ▸ Zoom In/Out and the address bar's actions show it. Both engines
/// keep Chrome's zoom level (a factor of 1.2 per level); this converts to and from percent.
enum PageZoom {
    static let range = 30...300
    static let step = 10

    static func percent(level: Double) -> Int {
        let raw = (pow(1.2, level) * 100).rounded()
        return min(range.upperBound, max(range.lowerBound, Int((raw / Double(step)).rounded()) * step))
    }

    static func level(percent: Int) -> Double {
        log(Double(min(range.upperBound, max(range.lowerBound, percent))) / 100) / log(1.2)
    }

    /// The next 10 % step up or down from `percent`.
    static func stepped(_ percent: Int, by direction: Int) -> Int {
        let snapped = Int((Double(percent) / Double(step)).rounded()) * step
        return min(range.upperBound, max(range.lowerBound, snapped + direction * step))
    }
}

extension WebTab {
    var zoomPercent: Int {
        get { PageZoom.percent(level: zoomLevel) }
        set { zoomLevel = newValue == 100 ? 0 : PageZoom.level(percent: newValue) }
    }
}
