import Foundation
import SwiftData

// Stored alongside the seeded rows so initialization commits atomically per store.
@Model
final class SeedRecord {
    var id: UUID = UUID()
    var key: String = ""
    var createdAt: Date = Date()

    init(key: String, now: Date = .now) {
        self.key = key
        self.createdAt = now
    }
}
