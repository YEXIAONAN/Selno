//
//  SelnoUITestsLaunchTests.swift
//  SelnoUITests
//
//  Created by Waiting on 2026/10/20.
//

import XCTest

final class SelnoUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--selno-ui-testing", "-NSTreatUnknownArgumentsAsOpen", "NO", "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SELNO_UI_TEST_STORE_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.descendants(matching: .any)["dashboard.heading"].firstMatch.waitForExistence(timeout: 10))

        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
