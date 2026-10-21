import SwiftData

enum SelnoSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [TodoProject.self, TodoTask.self, TaskStep.self, TaskCategory.self, SeedRecord.self]
    }
}

enum SelnoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SelnoSchemaV1.self, SelnoSchemaV2.self, SelnoSchemaV3.self, SelnoSchemaV4.self, SelnoSchemaV5.self]
    }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SelnoSchemaV1.self, toVersion: SelnoSchemaV2.self),
         .custom(fromVersion: SelnoSchemaV2.self, toVersion: SelnoSchemaV3.self, willMigrate: nil, didMigrate: { context in
             // This closure runs against the frozen V3 destination schema. Its only job is to
             // mirror the legacy single category into the multi-tag relationship. Failing to
             // save here aborts the migration instead of leaving a half-upgraded store.
             for task in try context.fetch(FetchDescriptor<SelnoSchemaV3.TodoTask>()) {
                 if let category = task.category, !(task.tags ?? []).contains(where: { $0.id == category.id }) {
                     task.tags = (task.tags ?? []) + [category]
                 }
             }
             try context.save()
         }),
         // V4 is purely additive: TodoTask gains an optional archivedAt column and a new
         // TaskReminder entity is introduced. Lightweight migration preserves every row.
         .lightweight(fromVersion: SelnoSchemaV3.self, toVersion: SelnoSchemaV4.self),
         // V5 is also additive: workspace configuration lives in new entities and no
         // historical business entity is modified. The default global workspace is
         // inserted by WorkspaceSeeder after the store opens.
         .lightweight(fromVersion: SelnoSchemaV4.self, toVersion: SelnoSchemaV5.self)]
    }
}

enum SelnoSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [TodoProject.self, TodoTask.self, TaskStep.self, TaskCategory.self, SeedRecord.self, CalendarEvent.self]
    }
}

enum SelnoSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [TodoProject.self, TodoTask.self, TaskStep.self, TaskCategory.self, SeedRecord.self, CalendarEvent.self,
         TaskTemplate.self, TaskTemplateInstance.self, TaskMilestone.self]
    }
}

enum SelnoSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [TodoProject.self, TodoTask.self, TaskStep.self, TaskCategory.self, SeedRecord.self, CalendarEvent.self,
         TaskTemplate.self, TaskTemplateInstance.self, TaskMilestone.self, TaskReminder.self]
    }
}

enum SelnoSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [TodoProject.self, TodoTask.self, TaskStep.self, TaskCategory.self, SeedRecord.self, CalendarEvent.self,
         TaskTemplate.self, TaskTemplateInstance.self, TaskMilestone.self, TaskReminder.self,
         Workspace.self, WorkspaceModule.self, SavedTaskView.self]
    }
}