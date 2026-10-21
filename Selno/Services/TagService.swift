import Foundation
import SwiftData

@MainActor struct TagService {
    let context: ModelContext
    @discardableResult func save(_ tag: TaskCategory? = nil, name: String, emoji: String, color: String) throws -> TaskCategory {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw TemplateError.missing("标签名称") }
        let result = tag ?? TaskCategory(name: name, symbolName: "tag", colorHex: color, sortOrder: 100)
        if tag == nil { context.insert(result) }
        result.name = name; result.emoji = String(emoji.prefix(3)); result.colorHex = color
        try commit(); return result
    }
    func delete(_ tag: TaskCategory) throws { context.delete(tag); try commit() }
    private func commit() throws { do { try context.save() } catch { context.rollback(); throw error } }
}
