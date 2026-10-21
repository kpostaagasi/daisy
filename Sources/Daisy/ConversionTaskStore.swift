// Daisy — active conversion/tool task store matching Tangerine's ConversionTaskStore.
import Combine
import Foundation

struct ConversionTaskRecord: Identifiable, Equatable {
    let id: UUID
    let sourceName: String
    let targetTitle: String

    init(id: UUID = UUID(), sourceName: String, targetTitle: String) {
        self.id = id
        self.sourceName = sourceName
        self.targetTitle = targetTitle
    }
}

final class ConversionTaskStore: ObservableObject {
    @Published private(set) var activeTasks: [ConversionTaskRecord] = [] {
        didSet {
            isBusy = !activeTasks.isEmpty
            onChange?()
        }
    }
    @Published var isBusy = false
    @Published var lastResult: String = ""
    @Published var succeeded = true

    var onChange: (() -> Void)?
    private let lock = NSLock()
    /// Off-main begins not yet appended to `activeTasks`. Guarded by `lock`.
    private var pendingBegins = Set<UUID>()
    /// Off-main begins that were ended before their append ran. Guarded by `lock`.
    private var pendingEnds = Set<UUID>()

    /// Registers a task and returns its id immediately. Off-main callers never block: the record is
    /// appended on the main queue, and an `endTask` that arrives first cancels the append.
    @discardableResult
    func beginTask(sourceName: String, targetTitle: String) -> UUID {
        let record = ConversionTaskRecord(sourceName: sourceName, targetTitle: targetTitle)
        if Thread.isMainThread {
            activeTasks.append(record)
        } else {
            lock.lock()
            pendingBegins.insert(record.id)
            lock.unlock()
            DispatchQueue.main.async { self.commitBegin(record) }
        }
        return record.id
    }

    func endTask(_ id: UUID, result: String? = nil, succeeded: Bool = true) {
        let apply = {
            guard self.activeTasks.contains(where: { $0.id == id }) || self.deferEnd(id) else { return }
            if let result {
                self.lastResult = result
                self.succeeded = succeeded
            }
            if let index = self.activeTasks.firstIndex(where: { $0.id == id }) {
                self.activeTasks.remove(at: index)
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    /// Runs on main. Appends a deferred begin unless it was already ended.
    private func commitBegin(_ record: ConversionTaskRecord) {
        lock.lock()
        pendingBegins.remove(record.id)
        let ended = pendingEnds.remove(record.id) != nil
        lock.unlock()
        if !ended {
            activeTasks.append(record)
        }
    }

    /// Returns true when `id` is a begin still in flight, recording that it has now ended.
    private func deferEnd(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard pendingBegins.contains(id) else { return false }
        pendingEnds.insert(id)
        return true
    }
}
