import Foundation

struct PresentedError: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(_ title: String, error: Error) {
        self.title = title
        message = error.localizedDescription
    }
}
