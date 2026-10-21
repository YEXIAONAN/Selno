import Foundation
import SwiftData
import Testing
@testable import Selno

@MainActor
struct Phase055TaskQueryTests {
    private let base = Date(timeIntervalSince1970: 1_790_003_000)

    @Test func inboxDescriptorMatchesInboxRuleAndDropsArchivedRows() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let context = container.mainContext
        let inbox = TodoTask(title: "待整理", now: base)
        let completedInbox = TodoTask(title: "已完成但仍未安排", status: .completed, now: base)
        let project = TodoProject(name: "项目", now: base)
        let projectTask = TodoTask(title: "项目任务", now: base)
        projectTask.project = project
        let planned = TodoTask(title: "已计划", now: base)
        planned.plannedAt = base.addingTimeInterval(86_400)
        let archived = TodoTask(title: "已归档", now: base)
        archived.archivedAt = base.addingTimeInterval(86_400)
        context.insert(project)
        for task in [inbox, completedInbox, projectTask, planned, archived] { context.insert(task) }
        try context.save()

        let fetched = try context.fetch(TaskWorkspaceQuery.tasks(for: .inbox))
        #expect(Set(fetched.map(\.id)) == Set([inbox.id, completedInbox.id]))
        #expect(fetched.allSatisfy { $0.isInInbox })

        let all = try context.fetch(TaskWorkspaceQuery.tasks(for: .all))
        #expect(all.count == 4)
        #expect(all.allSatisfy { !$0.isArchived })
    }

    @Test func allAndTodayDescriptorsNeverReturnArchivedRows() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let context = container.mainContext
        let active = TodoTask(title: "活动", now: base)
        let archived = TodoTask(title: "归档", now: base)
        archived.archivedAt = base.addingTimeInterval(1)
        context.insert(active)
        context.insert(archived)
        try context.save()

        for scope in [TaskListScope.all, .today] {
            let fetched = try context.fetch(TaskWorkspaceQuery.tasks(for: scope))
            #expect(fetched.map(\.id) == [active.id])
        }
    }
}