import Foundation
import SwiftData
import Testing
@testable import Selno

@MainActor
struct Phase04BackupTests {
    private let base = Date(timeIntervalSince1970: 1_790_003_000.125)
    private let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))!

    private struct InjectedFailure: Error {}

    private struct Fixture {
        let projectID: UUID
        let tagAID: UUID
        let tagBID: UUID
        let templateID: UUID
        let activeTaskID: UUID
        let archivedTaskID: UUID
        let eventID: UUID
        let allDayEventID: UUID
        let dueReminderID: UUID
        let scheduledReminderID: UUID
        let stepIDs: [UUID]
        let milestoneIDs: [UUID]
        let definition: TemplateDefinition
        let payload: TemplatePayload
        let due: Date
        let scheduledReminderDate: Date
    }

    // MARK: - Fixtures

    private func populate(_ context: ModelContext) throws -> Fixture {
        let due = base.addingTimeInterval(2 * 86_400)
        let scheduledReminderDate = base.addingTimeInterval(4 * 3_600)

        let project = TodoProject(name: "毕业设计 🌿", notes: "第一行\n第二行 \"引用\"", now: base)
        context.insert(project)

        let tagA = TaskCategory(name: "学习📚", symbolName: "book", colorHex: "#3F6852", sortOrder: 3, now: base)
        tagA.emoji = "📚"
        let tagB = TaskCategory(name: "已归档标签", symbolName: "archivebox", colorHex: "#A33E3C", sortOrder: 9, now: base)
        tagB.isArchived = true
        context.insert(tagA)
        context.insert(tagB)

        var definition = TemplateDefinition()
        definition.defaultImportanceRaw = TaskImportance.high.rawValue
        definition.defaultTagIDs = [tagA.id]
        definition.fields = [
            TemplateField("报名截止", kind: .dateTime, semantic: .registrationEnds),
            TemplateField("备注")
        ]
        var payload = TemplatePayload(definition: definition)
        payload.answers[0].date = due
        payload.answers[0].showOnCalendar = true
        payload.answers[0].reminderMinutes = 1_440
        payload.answers[1].text = "材料\n准备 / ready"

        let template = TaskTemplate(name: "校园活动 🏫", emoji: "🏫", definition: definition)
        template.revision = 3
        context.insert(template)

        let task = TodoTask(
            id: UUID(), title: "中文任务—Phase04 ✨ \"引号\" / 斜杠",
            notes: "备注含 Emoji 🚀 与换行\n第二行\t制表符",
            status: .pending, importance: .high, now: base
        )
        task.updatedAt = base.addingTimeInterval(120)
        task.plannedStartAt = base.addingTimeInterval(3_600)
        task.plannedAt = base.addingTimeInterval(7_200)
        task.dueAt = due
        task.project = project
        task.category = tagA
        task.tags = [tagA, tagB]
        context.insert(task)

        let step1 = TaskStep(id: UUID(), title: "第一步 ✍️", sortOrder: 0, now: base)
        let step2 = TaskStep(id: UUID(), title: "第二步", sortOrder: 1, now: base.addingTimeInterval(10))
        step2.isCompleted = true
        step2.completedAt = base.addingTimeInterval(90)
        context.insert(step1)
        context.insert(step2)
        step1.parentTask = task
        step2.parentTask = task

        let instance = try TaskTemplateInstance(
            templateID: template.id, name: template.name, revision: template.revision, payload: payload
        )
        context.insert(instance)
        task.templateInstance = instance

        let milestone1 = TaskMilestone(fieldID: definition.fields[0].id, title: definition.fields[0].name,
                                       semantic: MilestoneSemantic.registrationEnds.rawValue, date: due)
        milestone1.isOnCalendar = true
        milestone1.reminderLeadMinutes = 1_440
        let milestone2 = TaskMilestone(fieldID: definition.fields[1].id, title: "一般时间节点",
                                       semantic: MilestoneSemantic.date.rawValue, date: base.addingTimeInterval(9_000))
        context.insert(milestone1)
        context.insert(milestone2)
        milestone1.task = task
        milestone2.task = task

        let archived = TodoTask(id: UUID(), title: "已归档任务", status: .completed,
                                importance: .normal, now: base)
        archived.completedAt = base.addingTimeInterval(500)
        archived.archivedAt = base.addingTimeInterval(600)
        archived.project = project
        context.insert(archived)

        let event = CalendarEvent(
            id: UUID(), title: "组会 📅", notes: "带上材料",
            startsAt: base.addingTimeInterval(10_000), endsAt: base.addingTimeInterval(13_600),
            isAllDay: false, location: "上海 · 徐汇 \"A\"", now: base
        )
        let allDay = CalendarEvent(
            id: UUID(), title: "全天活动", notes: "", startsAt: base.addingTimeInterval(86_400),
            endsAt: base.addingTimeInterval(86_400 * 2), isAllDay: true, location: nil, now: base
        )
        context.insert(event)
        context.insert(allDay)

        let dueReminder = TaskReminder(taskID: task.id, kind: .due, leadMinutes: 1_440, now: base)
        let scheduledReminder = TaskReminder(taskID: task.id, kind: .scheduled,
                                             scheduledAt: scheduledReminderDate, now: base)
        context.insert(dueReminder)
        context.insert(scheduledReminder)

        try context.save()
        return Fixture(
            projectID: project.id, tagAID: tagA.id, tagBID: tagB.id, templateID: template.id,
            activeTaskID: task.id, archivedTaskID: archived.id,
            eventID: event.id, allDayEventID: allDay.id,
            dueReminderID: dueReminder.id, scheduledReminderID: scheduledReminder.id,
            stepIDs: [step1.id, step2.id], milestoneIDs: [milestone1.id, milestone2.id],
            definition: definition, payload: payload, due: due,
            scheduledReminderDate: scheduledReminderDate
        )
    }

    private func verify(_ context: ModelContext, fixture: Fixture, source: String = #function) throws {
        let projects = try context.fetch(FetchDescriptor<TodoProject>())
        let tags = try context.fetch(FetchDescriptor<TaskCategory>())
        let templates = try context.fetch(FetchDescriptor<TaskTemplate>())
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        let events = try context.fetch(FetchDescriptor<CalendarEvent>())
        let reminders = try context.fetch(FetchDescriptor<TaskReminder>())

        #expect(projects.count == 1, "\(source): projects")
        #expect(tags.count == 2, "\(source): tags")
        #expect(templates.count == 1, "\(source): templates")
        #expect(tasks.count == 2, "\(source): tasks")
        #expect(events.count == 2, "\(source): events")
        #expect(reminders.count == 2, "\(source): reminders")

        let project = try #require(projects.first)
        #expect(project.id == fixture.projectID)
        #expect(project.name == "毕业设计 🌿")
        #expect(project.notes == "第一行\n第二行 \"引用\"")
        #expect(project.tasks?.count == 2)

        let task = try #require(tasks.first { $0.id == fixture.activeTaskID })
        #expect(task.title == "中文任务—Phase04 ✨ \"引号\" / 斜杠")
        #expect(task.notes == "备注含 Emoji 🚀 与换行\n第二行\t制表符")
        #expect(task.status == .pending)
        #expect(task.importance == .high)
        #expect(task.createdAt == base)
        #expect(task.updatedAt == base.addingTimeInterval(120))
        #expect(task.plannedStartAt == base.addingTimeInterval(3_600))
        #expect(task.plannedAt == base.addingTimeInterval(7_200))
        #expect(task.dueAt == fixture.due)
        #expect(task.archivedAt == nil)
        #expect(task.project?.id == fixture.projectID)
        #expect(task.category?.id == fixture.tagAID)
        #expect(Set((task.tags ?? []).map(\.id)) == [fixture.tagAID, fixture.tagBID])
        #expect(task.orderedSteps.map(\.id) == fixture.stepIDs)
        #expect(task.orderedSteps.map(\.isCompleted) == [false, true])
        #expect(task.orderedSteps[1].completedAt == base.addingTimeInterval(90))
        #expect(task.orderedSteps.allSatisfy { $0.parentTask?.id == fixture.activeTaskID })
        #expect(Set((task.milestones ?? []).map(\.id)) == Set(fixture.milestoneIDs))
        let milestone = try #require((task.milestones ?? []).first { $0.id == fixture.milestoneIDs[0] })
        #expect(milestone.fieldID == fixture.definition.fields[0].id)
        #expect(milestone.semanticRaw == MilestoneSemantic.registrationEnds.rawValue)
        #expect(milestone.date == fixture.due)
        #expect(milestone.isOnCalendar)
        #expect(milestone.reminderLeadMinutes == 1_440)

        let instance = try #require(task.templateInstance)
        #expect(instance.templateID == fixture.templateID)
        #expect(instance.templateName == "校园活动 🏫")
        #expect(instance.templateRevision == 3)
        #expect(instance.payload == fixture.payload)

        let archived = try #require(tasks.first { $0.id == fixture.archivedTaskID })
        #expect(archived.title == "已归档任务")
        #expect(archived.status == .completed)
        #expect(archived.completedAt == base.addingTimeInterval(500))
        #expect(archived.archivedAt == base.addingTimeInterval(600))

        let template = try #require(templates.first)
        #expect(template.id == fixture.templateID)
        #expect(template.name == "校园活动 🏫")
        #expect(template.emoji == "🏫")
        #expect(template.revision == 3)
        #expect(template.definition == fixture.definition)

        let event = try #require(events.first { $0.id == fixture.eventID })
        #expect(event.title == "组会 📅")
        #expect(event.notes == "带上材料")
        #expect(event.startsAt == base.addingTimeInterval(10_000))
        #expect(event.endsAt == base.addingTimeInterval(13_600))
        #expect(event.isAllDay == false)
        #expect(event.location == "上海 · 徐汇 \"A\"")

        let allDay = try #require(events.first { $0.id == fixture.allDayEventID })
        #expect(allDay.isAllDay)
        #expect(allDay.startsAt == base.addingTimeInterval(86_400))
        #expect(allDay.endsAt == base.addingTimeInterval(86_400 * 2))

        let dueReminder = try #require(reminders.first { $0.id == fixture.dueReminderID })
        #expect(dueReminder.taskID == fixture.activeTaskID)
        #expect(dueReminder.kind == .due)
        #expect(dueReminder.leadMinutes == 1_440)
        #expect(dueReminder.scheduledAt == nil)

        let scheduled = try #require(reminders.first { $0.id == fixture.scheduledReminderID })
        #expect(scheduled.taskID == fixture.activeTaskID)
        #expect(scheduled.kind == .scheduled)
        #expect(scheduled.scheduledAt == fixture.scheduledReminderDate)
    }

    private func exportDocument(from context: ModelContext) throws -> BackupDocument {
        try BackupExportService(context: context).makeDocument(now: base)
    }

    private func apply(_ document: BackupDocument, to context: ModelContext,
                       mode: BackupImportMode, directory: URL? = nil,
                       beforeSave: ((ModelContext) throws -> Void)? = nil) throws -> BackupImportResult {
        // Replace writes an automatic safety backup. Default it to a throwaway
        // directory so tests never leave artifacts in the real Application Support
        // backup folder. Tests that need the file pass their own directory.
        let resolved = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("SelnoPhase04TestBackups-\(UUID().uuidString)", isDirectory: true)
        defer {
            if directory == nil { try? FileManager.default.removeItem(at: resolved) }
        }
        return try BackupImportService(context: context, backupDirectory: resolved)
            .apply(document: document, mode: mode, now: base, beforeSave: beforeSave)
    }

    // MARK: - Export

    @Test func suggestedFileNameUsesStableDayStamp() {
        #expect(BackupExportService.suggestedFileName(now: day) == "Selno-Backup-2026-10-21.json")
        #expect(BackupExportService.automaticBackupFileName(now: day).hasPrefix("Selno-PreRestore-2026-10-21-"))
    }

    @Test func exportDoesNotModifyBusinessData() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let context = container.mainContext
        _ = try populate(context)
        #expect(context.hasChanges == false)

        let beforeTasks = try context.fetch(FetchDescriptor<TodoTask>())
        let beforeTitles = beforeTasks.map(\.title).sorted()
        let beforeUpdates = beforeTasks.map(\.updatedAt).sorted()
        let beforeCounts = try BackupImportService(context: context).currentCounts()

        let exported = try exportDocument(from: context)
        #expect(context.hasChanges == false)

        let afterTasks = try context.fetch(FetchDescriptor<TodoTask>())
        #expect(afterTasks.map(\.title).sorted() == beforeTitles)
        #expect(afterTasks.map(\.updatedAt).sorted() == beforeUpdates)
        #expect(try BackupImportService(context: context).currentCounts() == beforeCounts)
        #expect(exported.counts == beforeCounts)
    }

    @Test func emptyDatabaseExportsAValidDocumentAndReplaceKeepsSeedMarker() throws {
        let source = try PersistenceController.makeContainer(storage: .inMemory)
        let document = try exportDocument(from: source.mainContext)
        #expect(document.counts == .zero)

        let data = try BackupCodec.encode(document.backup)
        let decoded = try BackupCodec.decode(data)
        try BackupCodec.validate(decoded)
        #expect(decoded.data.projects.isEmpty)

        let target = try PersistenceController.makeContainer(storage: .inMemory)
        try DefaultDataSeeder.seedIfNeeded(in: target.mainContext)
        #expect(try target.mainContext.fetchCount(FetchDescriptor<TaskCategory>()) == 5)
        #expect(try target.mainContext.fetchCount(FetchDescriptor<SeedRecord>()) == 1)

        let result = try apply(document, to: target.mainContext, mode: .replace)
        #expect(result.inserted == .zero)
        #expect(try target.mainContext.fetchCount(FetchDescriptor<TaskCategory>()) == 0)
        #expect(try target.mainContext.fetchCount(FetchDescriptor<SeedRecord>()) == 1)
    }

    @Test func multipleProjectsTemplatesAndTasksSurviveRoundTrip() throws {
        let source = try PersistenceController.makeContainer(storage: .inMemory)
        let context = source.mainContext
        let alpha = TodoProject(name: "项目甲 🌿", notes: "甲说明", now: base)
        let beta = TodoProject(name: "项目乙", notes: "乙说明", now: base)
        context.insert(alpha)
        context.insert(beta)

        var firstDefinition = TemplateDefinition()
        firstDefinition.fields = [TemplateField("甲字段")]
        var secondDefinition = TemplateDefinition()
        secondDefinition.fields = [TemplateField("乙字段", kind: .multiline)]
        let firstTemplate = TaskTemplate(name: "模板甲", emoji: "🅰️", definition: firstDefinition)
        let secondTemplate = TaskTemplate(name: "模板乙", emoji: "🅱️", definition: secondDefinition)
        context.insert(firstTemplate)
        context.insert(secondTemplate)

        let firstTask = TodoTask(id: UUID(), title: "甲任务", notes: "", status: .pending,
                                 importance: .normal, now: base)
        let secondTask = TodoTask(id: UUID(), title: "乙任务", notes: "", status: .inProgress,
                                  importance: .high, now: base)
        context.insert(firstTask)
        context.insert(secondTask)
        firstTask.project = alpha
        secondTask.project = beta
        try context.save()
        let taskIDs = [firstTask.id: alpha.id, secondTask.id: beta.id]

        let document = try exportDocument(from: context)
        let decoded = try BackupCodec.decode(try BackupCodec.encode(document.backup))
        try BackupCodec.validate(decoded)
        let target = try PersistenceController.makeContainer(storage: .inMemory)
        _ = try apply(BackupDocument(backup: decoded, fileName: "multi.json"),
                      to: target.mainContext, mode: .replace)

        let projects = try target.mainContext.fetch(FetchDescriptor<TodoProject>())
        let templates = try target.mainContext.fetch(FetchDescriptor<TaskTemplate>())
        let tasks = try target.mainContext.fetch(FetchDescriptor<TodoTask>())
        #expect(projects.map(\.name).sorted() == ["项目乙", "项目甲 🌿"])
        #expect(templates.map(\.name).sorted() == ["模板乙", "模板甲"])
        #expect(tasks.count == 2)
        for task in tasks {
            #expect(task.project?.id == taskIDs[task.id])
        }
        #expect(templates.first { $0.name == "模板甲" }?.emoji == "🅰️")
        #expect(templates.first { $0.name == "模板甲" }?.definition?.fields.first?.name == "甲字段")
        #expect(templates.first { $0.name == "模板乙" }?.emoji == "🅱️")
    }

    // MARK: - Real persistence round trip

    @Test func fullBackupSurvivesRealDiskRoundTripWithRelationships() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelnoPhase04Backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("Source.store")
        let targetURL = root.appendingPathComponent("Target.store")
        let backupURL = root.appendingPathComponent("Selno-Backup-2026-10-21.json")
        var fixture: Fixture!
        var exportedCounts = BackupCounts.zero

        try autoreleasepool {
            let source = try PersistenceController.makeContainer(storage: .disk(sourceURL))
            fixture = try populate(source.mainContext)
            let service = BackupExportService(context: source.mainContext)
            let document = try service.makeDocument(now: day)
            exportedCounts = document.counts
            try service.write(document.backup, to: backupURL)
        }

        #expect(FileManager.default.fileExists(atPath: backupURL.path))
        let data = try Data(contentsOf: backupURL)
        #expect(data.count > 500)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("com.yexiaonan.selno.backup"))
        #expect(text.contains("\"schemaVersion\" : 2"))
        #expect(text.contains("中文任务—Phase04"))
        #expect(text.contains("\\n"))

        let decoded = try BackupCodec.decode(data)
        try BackupCodec.validate(decoded)
        let document = BackupDocument(backup: decoded, fileName: backupURL.lastPathComponent,
                                      sourceURL: backupURL, byteCount: data.count)
        #expect(document.counts == exportedCounts)

        try autoreleasepool {
            let target = try PersistenceController.makeContainer(storage: .disk(targetURL))
            let result = try apply(document, to: target.mainContext, mode: .replace,
                                   directory: root.appendingPathComponent("Backups"))
            #expect(result.inserted == exportedCounts)
            #expect(result.safetyBackupURL != nil)
            try verify(target.mainContext, fixture: fixture)
        }

        try autoreleasepool {
            let reopened = try PersistenceController.makeContainer(storage: .disk(targetURL))
            try verify(reopened.mainContext, fixture: fixture)
        }
    }

    // MARK: - Merge

    @Test func mergeKeepsLocalConflictsAndIsIdempotent() throws {
        let source = try PersistenceController.makeContainer(storage: .inMemory)
        let fixture = try populate(source.mainContext)
        let document = try exportDocument(from: source.mainContext)

        let target = try PersistenceController.makeContainer(storage: .inMemory)
        let context = target.mainContext
        let localProject = TodoProject(id: fixture.projectID, name: "本地项目名", notes: "本地说明", now: base)
        let localTag = TaskCategory(id: fixture.tagAID, name: "本地标签名", symbolName: "star",
                                    colorHex: "#808080", sortOrder: 0, now: base)
        let localTask = TodoTask(id: fixture.activeTaskID, title: "本地任务版本", notes: "本地内容",
                                 importance: .low, now: base)
        context.insert(localProject)
        context.insert(localTag)
        context.insert(localTask)
        localTask.project = localProject
        localTask.tags = [localTag]
        localTask.category = localTag
        try context.save()

        let service = BackupImportService(context: context)
        let preview = try service.makePreview(document: document)
        #expect(preview.mergeSkipped.projects == 1)
        #expect(preview.mergeSkipped.tags == 1)
        #expect(preview.mergeSkipped.tasks == 1)
        #expect(preview.mergeSkipped.steps == 2)
        #expect(preview.mergeSkipped.templateInstances == 1)
        #expect(preview.mergeSkipped.milestones == 2)
        #expect(preview.mergeSkipped.reminders == 2)
        #expect(preview.mergeInserted.templates == 1)
        #expect(preview.mergeInserted.tasks == 1)
        #expect(preview.mergeInserted.events == 2)

        let first = try service.apply(document: document, mode: .merge, now: base)
        #expect(first.skipped == preview.mergeSkipped)
        #expect(first.inserted == preview.mergeInserted)

        let tasksAfterFirst = try context.fetch(FetchDescriptor<TodoTask>())
        #expect(tasksAfterFirst.count == 2)
        let local = try #require(tasksAfterFirst.first { $0.id == fixture.activeTaskID })
        #expect(local.title == "本地任务版本")
        #expect(local.project?.name == "本地项目名")
        #expect(local.tags?.map(\.name) == ["本地标签名"])
        #expect(local.orderedSteps.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<TaskReminder>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CalendarEvent>()) == 2)

        let countsAfterFirst = try service.currentCounts()
        let second = try service.apply(document: document, mode: .merge, now: base)
        #expect(second.inserted == .zero)
        #expect(try service.currentCounts() == countsAfterFirst)
        #expect(try context.fetchCount(FetchDescriptor<TodoTask>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<CalendarEvent>()) == 2)
    }

    @Test func mergeSkipsWholeTaskWhenAnEmbeddedChildCollides() throws {
        let source = try PersistenceController.makeContainer(storage: .inMemory)
        let fixture = try populate(source.mainContext)
        let document = try exportDocument(from: source.mainContext)

        let target = try PersistenceController.makeContainer(storage: .inMemory)
        let context = target.mainContext
        let localTask = TodoTask(title: "另一个本地任务", now: base)
        let collidingStep = TaskStep(id: fixture.stepIDs[0], title: "本地同标识步骤", sortOrder: 0, now: base)
        context.insert(localTask)
        context.insert(collidingStep)
        collidingStep.parentTask = localTask
        try context.save()

        let result = try apply(document, to: context, mode: .merge)
        #expect(result.skipped.tasks == 1)
        #expect(result.skipped.steps == 2)
        #expect(result.inserted.tasks == 1) // the archived task has no children
        #expect(try context.fetchCount(FetchDescriptor<TodoTask>()) == 2)
        #expect(try context.fetch(FetchDescriptor<TodoTask>()).contains { $0.id == fixture.activeTaskID } == false)
        #expect(try context.fetchCount(FetchDescriptor<TaskReminder>()) == 0)
    }

    // MARK: - Replace and rollback

    @Test func replaceWritesRestorableSafetyBackupBeforeDeleting() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelnoPhase04Replace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try PersistenceController.makeContainer(storage: .inMemory)
        let sourceFixture = try populate(source.mainContext)
        let sourceDocument = try exportDocument(from: source.mainContext)

        let targetURL = root.appendingPathComponent("Target.store")
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        var safetyURL: URL?
        try autoreleasepool {
            let target = try PersistenceController.makeContainer(storage: .disk(targetURL))
            let context = target.mainContext
            try TaskService(context: context).createTask(title: "本地真实任务，不可丢失")
            context.insert(TodoProject(name: "本地项目"))
            try context.save()

            let result = try apply(sourceDocument, to: context, mode: .replace, directory: backups)
            safetyURL = result.safetyBackupURL
            #expect(try context.fetchCount(FetchDescriptor<TodoTask>()) == 2)
            #expect(try context.fetch(FetchDescriptor<TodoTask>()).contains { $0.title == "本地真实任务，不可丢失" } == false)
            try verify(context, fixture: sourceFixture)
        }

        let url = try #require(safetyURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let safety = try BackupCodec.decode(try Data(contentsOf: url))
        try BackupCodec.validate(safety)
        #expect(safety.data.tasks.contains { $0.title == "本地真实任务，不可丢失" })
        #expect(safety.data.projects.contains { $0.name == "本地项目" })

        try autoreleasepool {
            let reopened = try PersistenceController.makeContainer(storage: .disk(targetURL))
            try verify(reopened.mainContext, fixture: sourceFixture)
        }
    }

    @Test func replaceFailureRollsBackToTheOriginalDiskState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelnoPhase04Rollback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try PersistenceController.makeContainer(storage: .inMemory)
        let sourceFixture = try populate(source.mainContext)
        let sourceDocument = try exportDocument(from: source.mainContext)

        let targetURL = root.appendingPathComponent("Target.store")
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        var localTaskID = UUID()
        var localProjectID = UUID()
        var localStepID = UUID()
        var localTagID = UUID()

        try autoreleasepool {
            let target = try PersistenceController.makeContainer(storage: .disk(targetURL))
            let context = target.mainContext
            let project = TodoProject(name: "本地项目", notes: "保留我", now: base)
            let tag = TaskCategory(name: "本地标签", symbolName: "tag", colorHex: "#3F6852", sortOrder: 1, now: base)
            let task = TodoTask(title: "本地真实任务", notes: "回退后必须完整", importance: .high, now: base)
            let step = TaskStep(title: "本地步骤", sortOrder: 0, now: base)
            context.insert(project)
            context.insert(tag)
            context.insert(task)
            context.insert(step)
            task.project = project
            task.tags = [tag]
            task.category = tag
            step.parentTask = task
            try context.save()
            localTaskID = task.id
            localProjectID = project.id
            localStepID = step.id
            localTagID = tag.id

            let service = BackupImportService(context: context, backupDirectory: backups)
            do {
                _ = try service.apply(document: sourceDocument, mode: .replace, now: base,
                                      beforeSave: { _ in throw InjectedFailure() })
                Issue.record("替换应在保存前失败")
            } catch {
                #expect(error is BackupError)
            }

            let tasks = try context.fetch(FetchDescriptor<TodoTask>())
            #expect(tasks.count == 1)
            let restoredTask = try #require(tasks.first)
            #expect(restoredTask.id == localTaskID)
            #expect(restoredTask.title == "本地真实任务")
            #expect(restoredTask.notes == "回退后必须完整")
            #expect(restoredTask.project?.id == localProjectID)
            #expect(restoredTask.tags?.map(\.id) == [localTagID])
            #expect(restoredTask.orderedSteps.map(\.id) == [localStepID])
            #expect(try context.fetchCount(FetchDescriptor<TodoProject>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<TaskCategory>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<CalendarEvent>()) == 0)
        }

        let files = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
        #expect(files.contains { $0.lastPathComponent.hasPrefix("Selno-PreRestore-") })

        try autoreleasepool {
            let reopened = try PersistenceController.makeContainer(storage: .disk(targetURL))
            let context = reopened.mainContext
            let tasks = try context.fetch(FetchDescriptor<TodoTask>())
            #expect(tasks.count == 1)
            let task = try #require(tasks.first)
            #expect(task.id == localTaskID)
            #expect(task.project?.id == localProjectID)
            #expect(task.orderedSteps.map(\.id) == [localStepID])
            #expect(try context.fetchCount(FetchDescriptor<TodoTask>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<CalendarEvent>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<TaskReminder>()) == 0)
            _ = sourceFixture
        }
    }

    // MARK: - Validation

    @Test func futureSchemaIsRejectedBeforeTouchingData() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let context = container.mainContext
        let task = try TaskService(context: context).createTask(title: "现有数据")
        var backup = try BackupExportService(context: context).makeBackup(now: base)
        backup.schemaVersion = 3
        do {
            try BackupCodec.validate(backup)
            Issue.record("未来版本必须被拒绝")
        } catch let error as BackupError {
            #expect(error == .unsupportedVersion(found: 3, supported: 2))
        }
        let document = BackupDocument(backup: backup, fileName: "future.json")
        do {
            _ = try apply(document, to: context, mode: .replace)
            Issue.record("未来版本不得导入")
        } catch let error as BackupError {
            #expect(error == .unsupportedVersion(found: 3, supported: 2))
        }
        #expect(try context.fetch(FetchDescriptor<TodoTask>()).map(\.id) == [task.id])
    }

    @Test func invalidRelationsDatesAndDuplicateIDsAreRejected() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let context = container.mainContext
        let fixture = try populate(context)
        let good = try BackupExportService(context: context).makeBackup(now: base)
        try BackupCodec.validate(good)

        var brokenProject = good
        brokenProject.data.tasks[0].projectID = UUID()
        #expect(throws: BackupError.self) { try BackupCodec.validate(brokenProject) }

        var brokenTag = good
        brokenTag.data.tasks[0].tagIDs.append(UUID())
        #expect(throws: BackupError.self) { try BackupCodec.validate(brokenTag) }

        var brokenEvent = good
        brokenEvent.data.events[0].endsAt = brokenEvent.data.events[0].startsAt.addingTimeInterval(-1)
        #expect(throws: BackupError.self) { try BackupCodec.validate(brokenEvent) }

        var brokenDate = good
        brokenDate.data.events[0].startsAt = Date(timeIntervalSince1970: .nan)
        #expect(throws: BackupError.self) { try BackupCodec.validate(brokenDate) }

        var duplicateTask = good
        duplicateTask.data.tasks[1].id = duplicateTask.data.tasks[0].id
        #expect(throws: BackupError.self) { try BackupCodec.validate(duplicateTask) }

        var brokenReminder = good
        brokenReminder.data.reminders[0].taskID = UUID()
        #expect(throws: BackupError.self) { try BackupCodec.validate(brokenReminder) }

        var brokenLead = good
        brokenLead.data.reminders[0].leadMinutes = 525_601
        #expect(throws: BackupError.self) { try BackupCodec.validate(brokenLead) }

        #expect(try context.fetchCount(FetchDescriptor<TodoTask>()) == 2)
        _ = fixture
    }

    @Test func olderJSONWithoutOptionalCollectionsStillImports() throws {
        let taskID = UUID()
        let json = """
        {
          "format": "com.yexiaonan.selno.backup",
          "schemaVersion": 1,
          "exportedAt": "2026-10-21T04:00:00.123Z",
          "appVersion": "0.9",
          "timeZone": "Asia/Shanghai",
          "data": {
            "tasks": [
              { "id": "\(taskID.uuidString)", "title": "旧版任务", "status": "pending" }
            ],
            "unknownTopLevelKey": { "ignored": true }
          },
          "unknownField": 42
        }
        """
        let data = Data(json.utf8)
        let backup = try BackupCodec.decode(data)
        try BackupCodec.validate(backup)
        #expect(backup.data.tasks[0].notes == "")
        #expect(backup.data.tasks[0].importance == "normal")
        #expect(backup.data.tasks[0].steps.isEmpty)
        #expect(backup.data.projects.isEmpty)
        #expect(backup.timeZone == "Asia/Shanghai")

        let target = try PersistenceController.makeContainer(storage: .inMemory)
        let document = BackupDocument(backup: backup, fileName: "older.json")
        let result = try apply(document, to: target.mainContext, mode: .replace)
        #expect(result.inserted.tasks == 1)
        let task = try #require(try target.mainContext.fetch(FetchDescriptor<TodoTask>()).first)
        #expect(task.id == taskID)
        #expect(task.title == "旧版任务")
        #expect(task.status == .pending)
        #expect(task.importance == .normal)
        #expect(task.project == nil)
        #expect(task.tags?.isEmpty != false)
    }

    @Test func undecodableTemplateAndPayloadBytesArePreservedVerbatim() throws {
        let source = try PersistenceController.makeContainer(storage: .inMemory)
        let context = source.mainContext
        let task = try TaskService(context: context).createTask(title: "未来版本任务")
        let templateBytes = Data(#"{"version":2,"fields":[{"future":true}],"note":"中文"}"#.utf8)
        let payloadBytes = Data(#"{"version":9,"unknown":["保留我"]}"#.utf8)
        let template = TaskTemplate(name: "未来模板")
        template.definitionData = templateBytes
        context.insert(template)
        let instance = TaskTemplateInstance(id: UUID(), templateID: template.id, name: "未来模板",
                                            revision: 9, payloadData: payloadBytes)
        context.insert(instance)
        task.templateInstance = instance
        try context.save()

        let document = try exportDocument(from: context)
        let exportedTemplate = try #require(document.backup.data.templates.first)
        #expect(exportedTemplate.definition == nil)
        #expect(exportedTemplate.definitionRawBase64.flatMap { Data(base64Encoded: $0) } == templateBytes)
        let exportedInstance = try #require(document.backup.data.tasks.first?.templateInstance)
        #expect(exportedInstance.payload == nil)
        #expect(exportedInstance.payloadRawBase64.flatMap { Data(base64Encoded: $0) } == payloadBytes)

        let target = try PersistenceController.makeContainer(storage: .inMemory)
        _ = try apply(document, to: target.mainContext, mode: .replace)
        let reopenedTemplate = try #require(try target.mainContext.fetch(FetchDescriptor<TaskTemplate>()).first)
        #expect(reopenedTemplate.definitionData == templateBytes)
        let reopenedTask = try #require(try target.mainContext.fetch(FetchDescriptor<TodoTask>()).first)
        #expect(reopenedTask.templateInstance?.payloadData == payloadBytes)
        #expect(reopenedTask.templateInstance?.templateRevision == 9)
    }

    @Test func encodeDecodeKeepsTimeZoneIndependentDates() throws {
        let container = try PersistenceController.makeContainer(storage: .inMemory)
        let context = container.mainContext
        let localized = Calendar(identifier: .gregorian).date(from: DateComponents(
            timeZone: TimeZone(identifier: "Asia/Shanghai"),
            year: 2026, month: 10, day: 21, hour: 23, minute: 59, second: 30
        ))!.addingTimeInterval(0.750)
        let task = TodoTask(title: "时区测试", now: localized)
        task.dueAt = localized.addingTimeInterval(2 * 86_400)
        context.insert(task)
        try context.save()

        let document = try exportDocument(from: context)
        let data = try BackupCodec.encode(document.backup)
        let decoded = try BackupCodec.decode(data)
        try BackupCodec.validate(decoded)
        #expect(decoded.data.tasks[0].dueAt == task.dueAt)
        #expect(decoded.data.tasks[0].createdAt == localized)

        let target = try PersistenceController.makeContainer(storage: .inMemory)
        _ = try apply(BackupDocument(backup: decoded, fileName: "tz.json"), to: target.mainContext, mode: .replace)
        let restored = try #require(try target.mainContext.fetch(FetchDescriptor<TodoTask>()).first)
        #expect(restored.dueAt == task.dueAt)
        #expect(restored.createdAt == localized)
    }
}