import Foundation
import SwiftData

enum ProjectValidationError: LocalizedError {
    case emptyName
    var errorDescription: String? { "请输入项目名称。" }
}

@MainActor
struct ProjectService {
    let context: ModelContext

    @discardableResult
    func save(project: TodoProject? = nil, name: String, notes: String, now: Date = .now) throws -> TodoProject {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ProjectValidationError.emptyName }
        let result: TodoProject
        if let project {
            result = project
            result.name = name
            result.notes = notes
            result.updatedAt = now
        } else {
            result = TodoProject(name: name, notes: notes, now: now)
            context.insert(result)
        }
        do { try context.save() }
        catch { context.rollback(); throw error }
        return result
    }
}
