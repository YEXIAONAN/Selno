import XCTest

final class DashboardUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testRealDashboardDataCalendarHandoffAndRelaunch() throws {
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.heading"].waitForExistence(timeout: 10))
        let quick = app.textFields["dashboard.quickAdd"]
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        quick.click(); quick.typeText("待整理的真实想法\n")
        XCTAssertTrue(contentText("待整理的真实想法", app: app).waitForExistence(timeout: 5))
        XCTAssertTrue(waitForText("1 项待整理", element: app.staticTexts["dashboard.inboxCount"]))

        newFromDashboard("新建任务", app: app)
        fill("task.editor.title", with: "今天的聚焦任务", app: app)
        app.buttons["task.editor.save"].firstMatch.click()
        XCTAssertTrue(contentText("今天的聚焦任务", app: app).waitForExistence(timeout: 5))
        newFromDashboard("新建日程", app: app)
        fill("event.editor.title", with: "今日聚焦讨论会", app: app)
        app.buttons["event.editor.save"].firstMatch.click()
        XCTAssertTrue(contentText("今日聚焦讨论会", app: app).waitForExistence(timeout: 5))
        capture(app, name: "总览真实任务日程与收件箱")

        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        let miniDate = Calendar.current.component(.day, from: tomorrow) == 1 ? Date.now : tomorrow
        let mini = app.buttons["dashboard.day.\(dayID(miniDate))"].firstMatch
        XCTAssertTrue(mini.waitForExistence(timeout: 5))
        mini.click()
        XCTAssertTrue(app.staticTexts["agenda.date"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(app.staticTexts["agenda.date"]).contains("\(Calendar.current.component(.day, from: miniDate))日"))
        if miniDate != tomorrow {
            let fullDay = app.buttons["calendar.day.\(dayID(tomorrow))"].firstMatch
            if !fullDay.exists { app.buttons["calendar.next"].firstMatch.click() }
            fullDay.click()
        }
        app.buttons["agenda.empty.newTask"].firstMatch.click()
        fill("task.editor.title", with: "明天推进的事项", app: app)
        app.buttons["task.editor.save"].firstMatch.click()
        sidebar("overview", app: app)
        XCTAssertTrue(contentText("明天推进的事项", app: app).waitForExistence(timeout: 5))
        let completion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task.complete.")).firstMatch
        XCTAssertTrue(completion.waitForExistence(timeout: 5))
        completion.click()
        XCTAssertTrue(contentText("今天的聚焦任务", app: app).waitForNonExistence(timeout: 5))
        capture(app, name: "总览近期安排与完成即时刷新")

        app.terminate(); app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.heading"].waitForExistence(timeout: 10))
        XCTAssertTrue(contentText("今日聚焦讨论会", app: app).waitForExistence(timeout: 5))
        XCTAssertTrue(contentText("待整理的真实想法", app: app).exists)
        XCTAssertTrue(contentText("明天推进的事项", app: app).exists)
        XCTAssertFalse(contentText("今天的聚焦任务", app: app).exists)
        sidebar("today", app: app)
        XCTAssertTrue(app.staticTexts["today.heading"].waitForExistence(timeout: 5))
        XCTAssertTrue(contentText("今日聚焦讨论会", app: app).exists)
        capture(app, name: "今天页任务与日程分区")
        sidebar("inbox", app: app)
        XCTAssertTrue(app.staticTexts["待整理的真实想法"].firstMatch.waitForExistence(timeout: 5))
        sidebar("all", app: app)
        XCTAssertTrue(app.staticTexts["今天的聚焦任务"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testProjectsProgressPersistsAndDashboardOpensProject() throws {
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        sidebar("projects", app: app)
        app.buttons["projects.new"].firstMatch.click()
        fill("project.editor.name", with: "产品发布准备", app: app)
        app.buttons["project.editor.save"].firstMatch.click()
        let project = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "projects.open.")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        project.click()
        let quick = app.textFields["project.quickAdd"]
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        quick.click(); quick.typeText("提交最终材料\n")
        let completion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project.complete.")).firstMatch
        XCTAssertTrue(completion.waitForExistence(timeout: 5))
        completion.click()
        XCTAssertTrue(waitForText("1 / 1 已完成", element: app.descendants(matching: .any)["project.progress"].firstMatch))
        capture(app, name: "真实项目任务与进度")
        app.buttons["关闭"].firstMatch.click()
        sidebar("overview", app: app)
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dashboard.project.")).firstMatch
        if !card.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.click()
        XCTAssertTrue(app.textFields["project.quickAdd"].waitForExistence(timeout: 5))
        XCTAssertEqual(completion.label, "恢复为未完成")
        app.terminate(); app.launch()
        sidebar("projects", app: app)
        project.click()
        XCTAssertTrue(completion.waitForExistence(timeout: 5))
        XCTAssertEqual(completion.label, "恢复为未完成")
        XCTAssertTrue(waitForText("1 / 1 已完成", element: app.descendants(matching: .any)["project.progress"].firstMatch))
    }

    @MainActor
    func testDarkOverviewAndWindowResize() throws {
        let app = makeApp()
        app.launchArguments += ["-AppleInterfaceStyle", "Dark"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.heading"].waitForExistence(timeout: 10))
        let window = app.windows.firstMatch
        capture(app, name: "深色总览")
        let original = window.frame
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
        corner.click(forDuration: 0.3, thenDragTo: corner.withOffset(CGVector(dx: 200, dy: 100)))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.heading"].exists)
        XCTAssertTrue(app.textFields["dashboard.quickAdd"].exists)
        capture(app, name: "总览扩大窗口")
        let newCorner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
        newCorner.click(forDuration: 0.3, thenDragTo: newCorner.withOffset(CGVector(dx: -600, dy: -150)))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.heading"].exists)
        XCTAssertGreaterThanOrEqual(window.frame.width, 990)
        XCTAssertNotEqual(window.frame.size, original.size)
        capture(app, name: "深色紧凑总览")
    }

    @MainActor private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--selno-ui-testing", "-NSTreatUnknownArgumentsAsOpen", "NO", "-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment["SELNO_UI_TEST_STORE_ID"] = UUID().uuidString
        return app
    }
    @MainActor private func sidebar(_ key: String, app: XCUIApplication) {
        let item = app.descendants(matching: .any)["sidebar.\(key)"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10)); item.click()
    }
    @MainActor private func fill(_ identifier: String, with value: String, app: XCUIApplication) {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.click(); field.typeText(value)
    }
    @MainActor private func newFromDashboard(_ title: String, app: XCUIApplication) {
        app.descendants(matching: .any)["dashboard.new"].firstMatch.click()
        app.menuItems[title].firstMatch.click()
    }
    @MainActor private func contentText(_ title: String, app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }
    private func dayID(_ date: Date) -> String {
        let p = Calendar.current.dateComponents([.era, .year, .month, .day], from: date)
        return "\(p.era ?? 0)-\(p.year ?? 0)-\(p.month ?? 0)-\(p.day ?? 0)-\(p.isLeapMonth == true ? 1 : 0)"
    }
    @MainActor private func text(_ element: XCUIElement) -> String { "\(element.label) \(element.value ?? "")" }
    @MainActor private func waitForText(_ value: String, element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", value, value), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
