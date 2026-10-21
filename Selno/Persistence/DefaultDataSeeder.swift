import Foundation
import SwiftData

@MainActor
enum DefaultDataSeeder {
    static let seedKey = "default-categories-v1"

    static func seedIfNeeded(in context: ModelContext) throws {
        let key = seedKey
        let descriptor = FetchDescriptor<SeedRecord>(predicate: #Predicate { $0.key == key })
        guard try context.fetchCount(descriptor) == 0 else { return }

        let existingIDs = Set(try context.fetch(FetchDescriptor<TaskCategory>()).map(\.id))
        let defaults: [(UInt8, String, String, String)] = [
            (1, "学习", "book", "#4F7A69"),
            (2, "竞赛", "trophy", "#A27A3F"),
            (3, "校园", "building.2", "#647C91"),
            (4, "开发", "chevron.left.forwardslash.chevron.right", "#7E7391"),
            (5, "生活", "leaf", "#8B7865")
        ]

        do {
            for (index, entry) in defaults.enumerated() {
                let id = UUID(uuid: (0x53, 0x45, 0x4C, 0x4E, 0x4F, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, entry.0))
                guard !existingIDs.contains(id) else { continue }
                context.insert(TaskCategory(
                    id: id, name: entry.1, symbolName: entry.2,
                    colorHex: entry.3, sortOrder: index
                ))
            }
            context.insert(SeedRecord(key: key))
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
