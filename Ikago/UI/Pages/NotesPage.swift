import Observation
import SwiftUI

/// A small personal scratchpad shared by every Notes tab in one browser profile.
struct NotesPage: View {
    let state: BrowserState
    @State private var store: NotesStore?
    static func flush() { NotesStore.flush() }
#if DEBUG
    static func storageChecksForTests(_ state: BrowserState) -> [String: Bool] {
        NotesStore.storageChecksForTests(state)
    }
#endif
    static func closePrivateNotes(_ profile: String) { NotesStore.closePrivate(profile) }

    var body: some View {
        let colors = state.palette
        PageScaffold(title: "Notes", colors: colors, subtitle: "Private to this browser") {
            if let store {
                if store.loaded {
                    TextEditor(text: Binding(get: { store.text }, set: store.update))
                        .font(.system(size: 14)).scrollContentBackground(.hidden).padding(12)
                        .frame(minHeight: 360, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.045)))
                        .disabled(store.error != nil)
                    if let error = store.error {
                        HStack {
                            Text(error).font(.system(size: 12)).foregroundStyle(.secondary)
                            Button("Retry") { store.retry() }.controlSize(.small)
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        Text(store.error ?? "Loading notes…").font(.system(size: 12)).foregroundStyle(.secondary)
                        if store.error != nil { Button("Retry") { store.retry() }.controlSize(.small) }
                    }.frame(maxWidth: .infinity, minHeight: 160)
                }
            }
        }
        .task { store = NotesStore.store(for: state) }
    }
}

@MainActor @Observable
private final class NotesStore {
    private static var stores: [String: NotesStore] = [:]
    private(set) var text = ""
    private(set) var loaded = false
    private(set) var error: String?
    private let isPrivate: Bool
    private var dirty = false
    private var saveTask: Task<Void, Never>?

    private init(isPrivate: Bool) {
        self.isPrivate = isPrivate
        load()
    }

    static func store(for state: BrowserState) -> NotesStore {
        let key = state.isPrivate ? state.privateProfileID : "regular"
        if let store = stores[key] { return store }
        let store = NotesStore(isPrivate: state.isPrivate)
        stores[key] = store
        return store
    }

    static func flush() {
        for store in stores.values where !store.isPrivate && store.loaded { store.saveTask?.cancel(); store.persist() }
    }

#if DEBUG
    static func storageChecksForTests(_ state: BrowserState) -> [String: Bool] {
        guard WebProfiles.isTestMode else { return ["notes checks use disposable storage": false] }
        let store = Self.store(for: state)
        let marker = "Notes encryption fixture " + UUID().uuidString
        store.update(marker); flush()
        let sealed = try? NotesStorage.read()
        let clear = sealed.flatMap { try? SealedStorage.open($0) }
        var results = ["notes persist encrypted": clear == Data(marker.utf8) && sealed?.range(of: Data(marker.utf8)) == nil]
        let privateState = BrowserState(privateFrom: state)
        let privateStore = Self.store(for: privateState)
        privateStore.update("private-only-note")
        flush()
        results["private notes never replace disk notes"] = (try? NotesStorage.read()) == sealed
        closePrivate(privateState.privateProfileID)
        results["private notes are cleared on close"] = stores[privateState.privateProfileID] == nil
        return results
    }
#endif

    static func closePrivate(_ profile: String) {
        stores[profile]?.saveTask?.cancel()
        stores.removeValue(forKey: profile)
    }

    func update(_ value: String) {
        guard loaded, error == nil, value != text else { return }
        text = value
        guard !isPrivate else { return }
        dirty = true
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    func retry() {
        if loaded { persist() }
        else { error = nil; load() }
    }

    private func load() {
        guard !isPrivate else { loaded = true; return }
        do {
            if let data = try NotesStorage.read() {
                let cleartext = try SealedStorage.open(data)
                guard let value = String(data: cleartext, encoding: .utf8) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                text = value
            }
            loaded = true
        } catch { self.error = "Couldn’t open notes: \(error.localizedDescription)" }
    }

    private func persist() {
        guard !isPrivate, dirty else { return }
        do { try NotesStorage.write(Data(text.utf8)); dirty = false; error = nil }
        catch { self.error = "Couldn’t save notes: \(error.localizedDescription)" }
    }
}

@MainActor
private enum NotesStorage {
    private static var file: URL {
        if WebProfiles.isTestMode {
            return SessionStore.testDirectory.appending(path: "Notes.sealed")
        }
        if let container = ProtectedStorage.container {
            return container.appending(path: "Ikago/Notes.sealed")
        }
        return AppIdentity.supportDirectory(home: FileManager.default.homeDirectoryForCurrentUser)
            .appending(path: "Notes.sealed")
    }

    static func read() throws -> Data? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try Data(contentsOf: file)
    }

    static func write(_ value: Data) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try SealedStorage.seal(value).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
