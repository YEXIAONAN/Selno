import XCTest

final class SelnoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testInboxCreationCompletionAndPersistenceAcrossAppRelaunch() throws {
        let app = makeApp()
        app.launch()
        openInbox(app)
        defer { app.terminate() }

        let inbox = app.descendants(matching: .any)["sidebar.inbox"].firstMatch
        XCTAssertTrue(inbox.waitForExistence(timeout: 10))
        inbox.click()
        let input = app.textFields["task.quickAdd"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        input.typeText("准备人工智能竞赛材料\n")
        XCTAssertTrue(app.staticTexts["准备人工智能竞赛材料"].firstMatch.waitForExistence(timeout: 5))

        let completion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task.complete.")).firstMatch
        XCTAssertTrue(completion.waitForExistence(timeout: 5))
        let completionID = completion.identifier
        completion.click()
        XCTAssertTrue(waitForLabel("恢复为未完成", on: app.buttons[completionID]))
        attachScreenshot(app, name: "完成任务")

        app.terminate()
        app.launch()
        openInbox(app)
        XCTAssertTrue(app.staticTexts["准备人工智能竞赛材料"].firstMatch.waitForExistence(timeout: 10))
        let persisted = app.buttons[completionID]
        XCTAssertTrue(persisted.waitForExistence(timeout: 5))
        XCTAssertEqual(persisted.label, "恢复为未完成")
        attachScreenshot(app, name: "完全退出并重启后保留完成状态")

        persisted.click()
        XCTAssertTrue(waitForLabel("标记为完成", on: app.buttons[completionID]))
        app.terminate()
        app.launch()
        openInbox(app)
        XCTAssertTrue(app.buttons[completionID].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons[completionID].label, "标记为完成")
    }

    @MainActor
    func testNavigationAndBasicEditing() throws {
        let app = makeApp()
        app.launch()
        openInbox(app)
        defer { app.terminate() }
        let input = app.textFields["task.quickAdd"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.click()
        input.typeText("需要修改的任务\n")
        let edit = app.buttons["task.edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.click()
        let title = app.textFields["task.editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.click()
        title.typeKey("a", modifierFlags: .command)
        title.typeText("修改后的任务")
        attachScreenshot(app, name: "任务基础编辑")
        app.buttons["task.editor.save"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["修改后的任务"].firstMatch.waitForExistence(timeout: 5))

        for scope in ["today", "all", "inbox"] {
            let item = app.descendants(matching: .any)["sidebar.\(scope)"].firstMatch
            XCTAssertTrue(item.exists)
            item.click()
            if scope != "today" {
                XCTAssertTrue(app.staticTexts["修改后的任务"].firstMatch.waitForExistence(timeout: 5))
            }
        }
    }

    @MainActor
    func testPlannedTaskAppearsInTodayAndCompletionRefreshesList() throws {
        let app = makeApp()
        app.launch()
        openInbox(app)
        defer { app.terminate() }
        let input = app.textFields["task.quickAdd"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.click()
        input.typeText("今天计划执行的任务\n")
        let edit = app.buttons["task.edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.click()
        let plan = app.checkBoxes["task.editor.planEnabled"].firstMatch
        XCTAssertTrue(plan.waitForExistence(timeout: 5))
        plan.click()
        app.buttons["task.editor.save"].firstMatch.click()

        app.descendants(matching: .any)["sidebar.today"].firstMatch.click()
        // Today now exposes the title and date role as one native details button.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "今天计划执行的任务")).firstMatch.waitForExistence(timeout: 5))
        let completion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task.complete.")).firstMatch
        XCTAssertTrue(completion.waitForExistence(timeout: 5))
        let completionID = completion.identifier
        completion.click()
        XCTAssertTrue(app.buttons[completionID].waitForNonExistence(timeout: 5))
        app.descendants(matching: .any)["sidebar.all"].firstMatch.click()
        XCTAssertTrue(app.buttons[completionID].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons[completionID].label, "恢复为未完成")
    }

    @MainActor
    private func openInbox(_ app: XCUIApplication) {
        let inbox = app.descendants(matching: .any)["sidebar.inbox"].firstMatch
        XCTAssertTrue(inbox.waitForExistence(timeout: 10))
        inbox.click()
    }

    @MainActor
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--selno-ui-testing", "-NSTreatUnknownArgumentsAsOpen", "NO", "-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment["SELNO_UI_TEST_STORE_ID"] = UUID().uuidString
        return app
    }

    @MainActor
    private func waitForLabel(_ label: String, on element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
