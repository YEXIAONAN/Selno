import Foundation
import SwiftData
import Testing
@testable import Selno

@MainActor private final class Phase04Gateway: ReminderGateway {
    var isAuthorized = true
    var scheduled: [String: MilestoneReminder] = [:]
    var additions = 0
    var failing: Set<String> = []

    func authorized() async -> Bool { isAuthorized }

    func pending() async -> [String: String] {
        scheduled.mapValues(\.signature)
    }

    func remove(_ identifiers: [String]) {
        for id in identifiers { scheduled.removeValue(forKey: id) }
    }

    func add(_ reminder: MilestoneReminder) async throws {
        if failing.contains(reminder.id) { throw ReminderError.invalidLead }
        scheduled[reminder.id] = reminder
        additions += 1
    }
}

@MainActor struct Phase04ReminderTests {
    private func make() throws -> (ModelContainer, ModelContext) {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        return (container, container.mainContext)
    }

    private func rows(_ context: ModelContext) throws -> [TaskReminder] {
        try context.fetch(FetchDescriptor<TaskReminder>())
    }

    private func only(_ context: ModelContext, kind: TaskReminderKind) throws -> TaskReminder {
        try #require(try rows(context).first { $0.kind == kind })
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func date(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int,
                      _ hour: Int, _ minute: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )))
    }

    private func taskDraft(now: Date, due: Date? = nil, lead: Int? = nil,
                           scheduled: Date? = nil, title: String = "提醒任务") -> TaskDraft {
        var draft = TaskDraft(plannedAt: now)
        draft.title = title
        draft.dueAt = due
        draft.dueReminderLeadMinutes = lead
        draft.scheduledReminderAt = scheduled
        return draft
    }

    @Test func dueReminderFollowsTaskLifecycle() async throws {
        let (container, context) = try make()
        _ = container
        let calendar = utcCalendar()
        let gateway = Phase04Gateway()
        let now = try date(calendar, 2026, 10, 21, 9, 0)
        let due = now.addingTimeInterval(7_200)
        let service = ReminderService(context: context, gateway: gateway, calendar: calendar)

        let task = try TaskService(context: context).createTask(
            draft: taskDraft(now: now, due: due, lead: 60), now: now
        )
        let row = try only(context, kind: .due)
        #expect(row.taskID == task.id && row.leadMinutes == 60)

        try await service.reconcile(now: now)
        #expect(gateway.scheduled.count == 1)
        #expect(gateway.scheduled[row.notificationID]?.firesAt == due.addingTimeInterval(-3_600))
        #expect(row.state == .scheduled)

        try await service.reconcile(now: now)
        #expect(gateway.additions == 1)

        var edit = TaskDraft(task: task, reminders: try rows(context))
        edit.dueAt = due.addingTimeInterval(3_600)
        try TaskService(context: context).update(task, draft: edit, now: now.addingTimeInterval(60))
        try await service.reconcile(now: now.addingTimeInterval(60))
        #expect(gateway.scheduled.count == 1)
        #expect(gateway.scheduled[row.notificationID]?.firesAt == due)
        #expect(gateway.additions == 2)

        try TaskService(context: context).setStatus(.completed, for: task, now: now.addingTimeInterval(120))
        try await service.reconcile(now: now.addingTimeInterval(120))
        #expect(gateway.scheduled.isEmpty)
        #expect(row.state == .paused)

        try TaskService(context: context).setStatus(.pending, for: task, now: now.addingTimeInterval(180))
        try await service.reconcile(now: now.addingTimeInterval(180))
        #expect(gateway.scheduled.count == 1)

        task.archivedAt = now.addingTimeInterval(240)
        try context.save()
        try await service.reconcile(now: now.addingTimeInterval(240))
        #expect(gateway.scheduled.isEmpty)
        #expect(row.state == .paused)

        task.archivedAt = nil
        try context.save()
        try await service.reconcile(now: now.addingTimeInterval(300))
        #expect(gateway.scheduled.count == 1)

        try TaskService(context: context).delete(task)
        #expect(try rows(context).isEmpty)
        try await service.reconcile(now: now.addingTimeInterval(360))
        #expect(gateway.scheduled.isEmpty)
    }

    @Test func scheduledReminderSnoozeOverridesOriginalAndNeverFallsBack() async throws {
        let (container, context) = try make()
        _ = container
        let calendar = utcCalendar()
        let gateway = Phase04Gateway()
        let now = try date(calendar, 2026, 10, 21, 9, 0)
        let fire = now.addingTimeInterval(3_600)
        let service = ReminderService(context: context, gateway: gateway, calendar: calendar)

        _ = try TaskService(context: context).createTask(
            draft: taskDraft(now: now, scheduled: fire), now: now
        )
        let row = try only(context, kind: .scheduled)
        try await service.reconcile(now: now)
        #expect(gateway.scheduled[row.notificationID]?.firesAt == fire)
        #expect(gateway.additions == 1)

        row.snoozeUntil = now.addingTimeInterval(600)
        row.stateRaw = TaskReminderState.pending.rawValue
        row.updatedAt = now.addingTimeInterval(10)
        try context.save()
        try await service.reconcile(now: now.addingTimeInterval(10))
        #expect(gateway.scheduled.count == 1)
        #expect(gateway.scheduled[row.notificationID]?.firesAt == now.addingTimeInterval(600))
        #expect(gateway.additions == 2)

        // The snoozed time passes while the original reminder time is still ahead.
        // The reminder expires instead of falling back and firing twice.
        try await service.reconcile(now: now.addingTimeInterval(601))
        #expect(gateway.scheduled.isEmpty)
        #expect(row.state == .expired)

        row.snoozeUntil = now.addingTimeInterval(7_200)
        row.stateRaw = TaskReminderState.pending.rawValue
        row.updatedAt = now.addingTimeInterval(602)
        try context.save()
        try await service.reconcile(now: now.addingTimeInterval(602))
        #expect(gateway.scheduled.count == 1)
        #expect(gateway.scheduled[row.notificationID]?.firesAt == now.addingTimeInterval(7_200))
        #expect(gateway.additions == 3)

        try await service.reconcile(now: now.addingTimeInterval(603))
        #expect(gateway.additions == 3)
        #expect(gateway.scheduled.count == 1)
    }

    @Test func quietHoursShiftAcrossMidnightAndDoNotRevivePastReminders() async throws {
        let calendar = utcCalendar()
        let hours = QuietHours(isEnabled: true, startMinute: 22 * 60, endMinute: 8 * 60)
        let evening = try date(calendar, 2026, 10, 21, 23, 0)
        let nextMorning = try date(calendar, 2026, 10, 22, 8, 0)
        let earlyMorning = try date(calendar, 2026, 10, 21, 7, 0)
        let noon = try date(calendar, 2026, 10, 21, 12, 0)
        #expect(hours.adjusted(evening, calendar: calendar) == nextMorning)
        let morningEnd = try date(calendar, 2026, 10, 21, 8, 0)
        #expect(hours.adjusted(earlyMorning, calendar: calendar) == morningEnd)
        #expect(hours.adjusted(noon, calendar: calendar) == noon)

        let daytime = QuietHours(isEnabled: true, startMinute: 13 * 60, endMinute: 14 * 60)
        let daytimeStart = try date(calendar, 2026, 10, 21, 13, 30)
        let daytimeEnd = try date(calendar, 2026, 10, 21, 14, 0)
        #expect(daytime.adjusted(daytimeStart, calendar: calendar) == daytimeEnd)

        let (container, context) = try make()
        _ = container
        let gateway = Phase04Gateway()
        _ = try TaskService(context: context).createTask(
            draft: taskDraft(now: noon, scheduled: evening), now: noon
        )
        let row = try only(context, kind: .scheduled)
        let shiftedService = ReminderService(context: context, gateway: gateway,
                                             quietHours: hours, calendar: calendar)
        try await shiftedService.reconcile(now: try date(calendar, 2026, 10, 21, 21, 0))
        #expect(gateway.scheduled[row.notificationID]?.firesAt == nextMorning)

        let (lateContainer, lateContext) = try make()
        _ = lateContainer
        let lateGateway = Phase04Gateway()
        let previousNight = try date(calendar, 2026, 10, 20, 23, 0)
        _ = try TaskService(context: lateContext).createTask(
            draft: taskDraft(now: previousNight, scheduled: previousNight), now: previousNight
        )
        let lateRow = try only(lateContext, kind: .scheduled)
        let lateService = ReminderService(context: lateContext, gateway: lateGateway,
                                          quietHours: hours, calendar: calendar)
        try await lateService.reconcile(now: earlyMorning)
        #expect(lateGateway.scheduled.isEmpty)
        #expect(lateRow.state == .expired)
    }

    @Test func permissionChangesBlockAndRestoreWithoutDuplicateRequests() async throws {
        let (container, context) = try make()
        _ = container
        let calendar = utcCalendar()
        let gateway = Phase04Gateway()
        let now = try date(calendar, 2026, 10, 21, 9, 0)
        let service = ReminderService(context: context, gateway: gateway, calendar: calendar)

        _ = try TaskService(context: context).createTask(
            draft: taskDraft(now: now, due: now.addingTimeInterval(7_200), lead: 60), now: now
        )
        let row = try only(context, kind: .due)

        gateway.isAuthorized = false
        try await service.reconcile(now: now)
        #expect(gateway.scheduled.isEmpty)
        #expect(row.state == .blocked)

        gateway.isAuthorized = true
        try await service.reconcile(now: now.addingTimeInterval(10))
        #expect(gateway.scheduled.count == 1)
        #expect(row.state == .scheduled)
        #expect(gateway.additions == 1)

        gateway.isAuthorized = false
        try await service.reconcile(now: now.addingTimeInterval(20))
        #expect(gateway.scheduled.isEmpty)
        #expect(row.state == .blocked)

        gateway.isAuthorized = true
        try await service.reconcile(now: now.addingTimeInterval(30))
        #expect(gateway.scheduled.count == 1)
        #expect(gateway.additions == 2)
        try await service.reconcile(now: now.addingTimeInterval(40))
        #expect(gateway.additions == 2)
    }

    @Test func duplicatesAndOrphansNeverRegisterExtraNotifications() async throws {
        let (container, context) = try make()
        _ = container
        let calendar = utcCalendar()
        let gateway = Phase04Gateway()
        let now = try date(calendar, 2026, 10, 21, 9, 0)
        let fire = now.addingTimeInterval(3_600)
        let service = ReminderService(context: context, gateway: gateway, calendar: calendar)

        let task = try TaskService(context: context).createTask(
            draft: taskDraft(now: now, scheduled: fire), now: now
        )
        let preferred = try only(context, kind: .scheduled)
        let older = TaskReminder(taskID: task.id, kind: .scheduled, scheduledAt: fire,
                                 now: now.addingTimeInterval(-1_000))
        older.updatedAt = now.addingTimeInterval(-1_000)
        context.insert(older)
        let orphan = TaskReminder(taskID: UUID(), kind: .scheduled,
                                  scheduledAt: now.addingTimeInterval(1_800), now: now)
        context.insert(orphan)
        try context.save()

        try await gateway.add(MilestoneReminder(
            id: older.notificationID, title: "旧提醒", body: "stale", firesAt: fire,
            taskID: task.id, categoryIdentifier: SelnoNotifications.taskCategory
        ))
        #expect(gateway.scheduled[older.notificationID] != nil)

        try await service.reconcile(now: now)
        #expect(gateway.scheduled[older.notificationID] == nil)
        #expect(gateway.scheduled[orphan.notificationID] == nil)
        #expect(gateway.scheduled[preferred.notificationID] != nil)
        #expect(gateway.scheduled.count == 1)
        #expect(older.state == .duplicate)
        #expect(orphan.state == .unconfigured)
        #expect(preferred.state == .scheduled)

        let additions = gateway.additions
        try await service.reconcile(now: now)
        #expect(gateway.additions == additions)
        #expect(gateway.scheduled.count == 1)
    }

    @Test func failedRegistrationIsReportedAndRetriedOnNextReconcile() async throws {
        let (container, context) = try make()
        _ = container
        let calendar = utcCalendar()
        let gateway = Phase04Gateway()
        let now = try date(calendar, 2026, 10, 21, 9, 0)
        let service = ReminderService(context: context, gateway: gateway, calendar: calendar)

        _ = try TaskService(context: context).createTask(
            draft: taskDraft(now: now, due: now.addingTimeInterval(7_200), lead: 60), now: now
        )
        let row = try only(context, kind: .due)
        gateway.failing = [row.notificationID]

        try await service.reconcile(now: now)
        #expect(gateway.scheduled.isEmpty)
        #expect(row.state == .failed)

        gateway.failing = []
        try await service.reconcile(now: now.addingTimeInterval(10))
        #expect(gateway.scheduled.count == 1)
        #expect(row.state == .scheduled)
    }

    @Test func missedRemindersExpireWithoutRetroactiveDelivery() async throws {
        let (container, context) = try make()
        _ = container
        let calendar = utcCalendar()
        let gateway = Phase04Gateway()
        let now = try date(calendar, 2026, 10, 21, 9, 0)
        let service = ReminderService(context: context, gateway: gateway, calendar: calendar)

        _ = try TaskService(context: context).createTask(
            draft: taskDraft(now: now.addingTimeInterval(-3_600),
                             scheduled: now.addingTimeInterval(-60),
                             title: "已经错过的提醒"),
            now: now.addingTimeInterval(-3_600)
        )
        let row = try only(context, kind: .scheduled)
        try await service.reconcile(now: now)
        #expect(gateway.scheduled.isEmpty)
        #expect(row.state == .expired)
        #expect(gateway.additions == 0)

        try await service.reconcile(now: now.addingTimeInterval(3_600))
        #expect(gateway.scheduled.isEmpty)
        #expect(gateway.additions == 0)

        let dueContext = try make()
        _ = dueContext.0
        let dueGateway = Phase04Gateway()
        let dueService = ReminderService(context: dueContext.1, gateway: dueGateway, calendar: calendar)
        _ = try TaskService(context: dueContext.1).createTask(
            draft: taskDraft(now: now, due: now.addingTimeInterval(1_800), lead: 60,
                             title: "截止提醒已错过"),
            now: now
        )
        let dueRow = try only(dueContext.1, kind: .due)
        try await dueService.reconcile(now: now)
        #expect(dueGateway.scheduled.isEmpty)
        #expect(dueRow.state == .expired)
    }

    @Test func taskServiceKeepsOneReminderPerKindAndRemovesDisabledOnes() throws {
        let (container, context) = try make()
        _ = container
        let calendar = utcCalendar()
        let now = try date(calendar, 2026, 10, 21, 9, 0)
        let task = try TaskService(context: context).createTask(
            draft: taskDraft(now: now, due: now.addingTimeInterval(7_200), lead: 60,
                             scheduled: now.addingTimeInterval(3_600)),
            now: now
        )
        #expect(try rows(context).count == 2)

        let duplicate = TaskReminder(taskID: task.id, kind: .due, leadMinutes: 30,
                                     now: now.addingTimeInterval(-500))
        duplicate.updatedAt = now.addingTimeInterval(-500)
        context.insert(duplicate)
        try context.save()
        #expect(try rows(context).count == 3)

        var edit = TaskDraft(task: task, reminders: try rows(context))
        edit.dueReminderLeadMinutes = 120
        try TaskService(context: context).update(task, draft: edit, now: now.addingTimeInterval(10))
        let afterDedupe = try rows(context)
        #expect(afterDedupe.count == 2)
        #expect(afterDedupe.filter { $0.kind == .due }.count == 1)
        #expect(afterDedupe.first { $0.kind == .due }?.leadMinutes == 120)

        var removed = TaskDraft(task: task, reminders: afterDedupe)
        removed.dueReminderLeadMinutes = nil
        removed.scheduledReminderAt = nil
        try TaskService(context: context).update(task, draft: removed, now: now.addingTimeInterval(20))
        #expect(try rows(context).isEmpty)

        let noDue = try TaskService(context: context).createTask(
            draft: taskDraft(now: now, due: nil, lead: 60, title: "没有截止日期"), now: now
        )
        #expect(try rows(context).allSatisfy { $0.taskID != noDue.id })
    }

    @Test func importedRemindersScheduleOnceAndRepeatedMergeIsIdempotent() async throws {
        let (sourceContainer, source) = try make()
        _ = sourceContainer
        let calendar = utcCalendar()
        let now = try date(calendar, 2026, 10, 21, 9, 0)
        _ = try TaskService(context: source).createTask(
            draft: taskDraft(now: now, due: now.addingTimeInterval(7_200), lead: 60,
                             scheduled: now.addingTimeInterval(3_600), title: "导入的提醒任务"),
            now: now
        )
        let document = try BackupExportService(context: source).makeDocument(now: now)
        #expect(document.backup.data.reminders.count == 2)

        let (targetContainer, target) = try make()
        _ = targetContainer
        let importer = BackupImportService(context: target)
        let first = try importer.apply(document: document, mode: .merge)
        #expect(first.inserted.tasks == 1 && first.inserted.reminders == 2)

        let gateway = Phase04Gateway()
        let service = ReminderService(context: target, gateway: gateway, calendar: calendar)
        try await service.reconcile(now: now)
        #expect(gateway.scheduled.count == 2)
        let additions = gateway.additions

        let second = try importer.apply(document: document, mode: .merge,
                                       now: now.addingTimeInterval(30))
        #expect(second.inserted.reminders == 0 && second.skipped.reminders == 2)
        #expect(try rows(target).count == 2)
        try await service.reconcile(now: now.addingTimeInterval(30))
        #expect(gateway.additions == additions)
        #expect(gateway.scheduled.count == 2)
    }

    @Test func taskAndMilestoneRemindersUseDistinctIdentifiersAndBothPauseOnCompletion() async throws {
        let (container, context) = try make()
        _ = container
        let calendar = utcCalendar()
        let gateway = Phase04Gateway()
        let now = try date(calendar, 2026, 10, 21, 9, 0)
        let task = try TaskService(context: context).createTask(
            draft: taskDraft(now: now, due: now.addingTimeInterval(7_200), lead: 60), now: now
        )
        let node = TaskMilestone(fieldID: UUID(), title: "截止节点", semantic: "deadline",
                                 date: now.addingTimeInterval(10_800))
        context.insert(node)
        node.task = task
        node.reminderLeadMinutes = 30
        try context.save()

        let service = ReminderService(context: context, gateway: gateway, calendar: calendar)
        try await service.reconcile(now: now)
        #expect(gateway.scheduled.count == 2)
        #expect(Set(gateway.scheduled.keys).count == 2)
        #expect(Set(gateway.scheduled.values.map(\.categoryIdentifier))
                == [SelnoNotifications.taskCategory, SelnoNotifications.milestoneCategory])

        try TaskService(context: context).setStatus(.completed, for: task, now: now.addingTimeInterval(10))
        try await service.reconcile(now: now.addingTimeInterval(10))
        #expect(gateway.scheduled.isEmpty)
        #expect(try only(context, kind: .due).state == .paused)
        #expect(node.reminderStateRaw == TaskReminderState.paused.rawValue)
    }
}