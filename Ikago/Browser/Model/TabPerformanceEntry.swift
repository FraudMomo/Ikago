import Foundation

struct TabPerformanceEntry: Identifiable {
    let id: String
    let title: String
    let engine: String
    let status: String
    let pid: Int32?
    let parked: Int
}
