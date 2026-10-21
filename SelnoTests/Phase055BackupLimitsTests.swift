import Foundation
import Testing
@testable import Selno

@MainActor
struct Phase055BackupLimitsTests {
    @Test func rejectsTaskCollectionsAboveTheImportCeiling() {
        let date = Date(timeIntervalSince1970: 1_790_003_000)
        let task = BackupTask(
            id: UUID(), title: "Synthetic", notes: "",
            status: TaskStatus.pending.rawValue,
            importance: TaskImportance.normal.rawValue,
            createdAt: date, updatedAt: date, completedAt: nil,
            plannedStartAt: nil, plannedAt: nil, dueAt: nil, archivedAt: nil,
            projectID: nil, categoryID: nil, tagIDs: [],
            steps: [], templateInstance: nil, milestones: []
        )
        let backup = SelnoBackup(
            exportedAt: date,
            data: SelnoBackupData(
                projects: [], tags: [], templates: [],
                tasks: Array(repeating: task, count: 100_001),
                events: [], reminders: []
            )
        )

        do {
            try BackupCodec.validate(backup)
            Issue.record("Expected the import ceiling to reject the task collection.")
        } catch let error as BackupError {
            guard case .invalidData(let message) = error else {
                Issue.record("Unexpected BackupError: \(error)")
                return
            }
            #expect(message.contains("任务数量"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}