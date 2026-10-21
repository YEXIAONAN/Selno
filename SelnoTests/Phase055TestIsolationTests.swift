import Foundation
import Testing
@testable import Selno

@MainActor
struct Phase055TestIsolationTests {
    @Test func xctestHostUsesAnInMemoryStoreWithoutDebugGuard() throws {
        let storage = try PersistenceController.launchStorage(
            arguments: ["Selno"],
            environment: ["XCTestConfigurationFilePath": "/tmp/SelnoTests.xctestconfiguration"]
        )
        guard case .inMemory = storage else {
            Issue.record("An XCTest host must never fall through to the local store")
            return
        }
    }

    @Test func uiTestLaunchWithoutStoreIdentifierFailsClosed() {
        #expect(throws: PersistenceError.self) {
            try PersistenceController.launchStorage(
                arguments: ["Selno", "--selno-ui-testing"],
                environment: [:]
            )
        }
    }

    @Test func uiTestStoreStaysInsideItsIsolatedDirectory() throws {
        let id = UUID()
        let storage = try PersistenceController.launchStorage(
            arguments: ["Selno", "--selno-ui-testing"],
            environment: ["SELNO_UI_TEST_STORE_ID": id.uuidString]
        )
        guard case .disk(let url) = storage else {
            Issue.record("UI tests must use a dedicated disk store")
            return
        }
        #expect(url.path.contains("/UITests/\(id.uuidString)/Selno.store"))
    }

    @Test func ordinaryLaunchUsesTheLocalStore() throws {
        let storage = try PersistenceController.launchStorage(arguments: ["Selno"], environment: [:])
        guard case .local = storage else {
            Issue.record("A normal launch must keep using the local store")
            return
        }
    }
}