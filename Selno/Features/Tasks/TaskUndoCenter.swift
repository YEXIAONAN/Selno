import Foundation
import Observation
import SwiftData

/// Holds the most recent task deletion so the main window can offer an immediate
/// undo without keeping deleted SwiftData objects alive. Only one deletion is
/// undoable at a time; starting another deletion replaces the snapshot.
@MainActor
@Observable
final class TaskUndoCenter {
    static let shared = TaskUndoCenter()

    private(set) var snapshot: TaskDeletionSnapshot?
    private(set) var message: String?
    private var expiry: Task<Void, Never>?

    private init() {}

    func offer(_ snapshot: TaskDeletionSnapshot) {
        guard snapshot.count > 0 else { return }
        self.snapshot = snapshot
        message = snapshot.message
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            self?.clear()
        }
    }

    func undo(context: ModelContext) throws {
        guard let snapshot else { return }
        try TaskService(context: context).restore(snapshot)
        clear()
    }

    func clear() {
        expiry?.cancel()
        expiry = nil
        snapshot = nil
        message = nil
    }
}