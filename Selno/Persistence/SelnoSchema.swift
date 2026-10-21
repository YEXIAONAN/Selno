import SwiftData

enum SelnoSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [TodoProject.self, TodoTask.self, TaskStep.self, TaskCategory.self, SeedRecord.self]
    }
}

enum SelnoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SelnoSchemaV1.self, SelnoSchemaV2.self, SelnoSchemaV3.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SelnoSchemaV1.self, toVersion: SelnoSchemaV2.self),
         .custom(fromVersion: SelnoSchemaV2.self, toVersion: SelnoSchemaV3.self, willMigrate: nil, didMigrate: { context in
             for task in try context.fetch(FetchDescriptor<TodoTask>()) {
                 if let category = task.category, !(task.tags ?? []).contains(where: { $0.id == category.id }) {
                     task.tags = (task.tags ?? []) + [category]
                 }
             }
             try context.save()
         })]
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
