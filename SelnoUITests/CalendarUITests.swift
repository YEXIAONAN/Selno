import XCTest

final class CalendarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // A checkout on Desktop can prompt for the UI test runner's file access.
        // Handle only this runner's system dialog; app dialogs remain part of the test.
        addUIInterruptionMonitor(withDescription: "UI test runner Desktop access") { dialog in
            let runnerMessage = dialog.staticTexts.matching(NSPredicate(
                format: "label CONTAINS %@ OR value CONTAINS %@",
                "SelnoUITests-Runner", "SelnoUITests-Runner"
            )).firstMatch
            guard runnerMessage.exists else { return false }
            let allow = dialog.buttons.matching(NSPredicate(
                format: "title IN %@ OR label IN %@ OR value IN %@",
                ["允许", "Allow"], ["允许", "Allow"], ["允许", "Allow"]
            )).firstMatch
            guard allow.exists else { return false }
            allow.click()
            return true
        }
    }

    @MainActor
    func testCalendarEventHoverDailyPanelAndPersistence() throws {
        let app = makeApp()
        app.launch()
        openCalendar(app)
        dismissUnneededAppDesktopPrompt()
        defer { app.terminate() }
        let day = Calendar.current.startOfDay(for: .now)
        let dateButton = dayButton(day, app: app)
        XCTAssertTrue(dateButton.waitForExistence(timeout: 10))
        dateButton.click()
        dateButton.hover()
        let tip = app.descendants(matching: .any)["calendar.hover"].firstMatch
        XCTAssertTrue(tip.waitForExistence(timeout: 5))
        XCTAssertTrue(tip.label.contains("暂无安排"))
        app.buttons["calendar.today"].firstMatch.hover()
        XCTAssertTrue(tip.waitForNonExistence(timeout: 5))

        let createEvent = app.buttons["agenda.empty.newEvent"].firstMatch
        XCTAssertTrue(createEvent.waitForExistence(timeout: 5))
        createEvent.click()
        let title = app.textFields["event.editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.click()
        title.typeText("日历验收讨论会")
        let location = app.textFields["event.editor.location"]
        location.click()
        location.typeText("实验室")
        app.buttons["event.editor.save"].firstMatch.click()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        let eventRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "agenda.event.")).firstMatch
        XCTAssertTrue(eventRow.waitForExistence(timeout: 5))
        let eventID = eventRow.identifier
        XCTAssertTrue(waitForValue("1 项日程", on: dateButton))

        dateButton.hover()
        XCTAssertTrue(tip.waitForExistence(timeout: 5))
        XCTAssertTrue(tip.label.contains("日历验收讨论会"))
        XCTAssertTrue(tip.label.contains("1 项日程"))
        capture(app, name: "真实日程悬停摘要")
        app.buttons["calendar.today"].firstMatch.hover()
        XCTAssertTrue(tip.waitForNonExistence(timeout: 5))
        eventRow.click()
        XCTAssertTrue(app.buttons["event.edit"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["event.edit"].firstMatch.click()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.click()
        title.typeKey("a", modifierFlags: .command)
        title.typeText("更新后的日历讨论会")
        app.buttons["event.editor.save"].firstMatch.click()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        app.buttons["关闭"].firstMatch.click()
        XCTAssertTrue(eventRow.label.contains("更新后的日历讨论会"))

        newFromMenu("新建任务", app: app)
        let taskTitle = app.textFields["task.editor.title"]
        XCTAssertTrue(taskTitle.waitForExistence(timeout: 5))
        taskTitle.click()
        taskTitle.typeText("日历验收任务")
        app.buttons["task.editor.save"].firstMatch.click()
        let completion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "agenda.complete.")).firstMatch
        XCTAssertTrue(completion.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue("1 项待办", on: dateButton))
        let taskID = completion.identifier
        completion.click()
        XCTAssertTrue(waitForValue("0 项待办", on: dateButton))
        capture(app, name: "日历与当日安排真实数据")

        app.buttons["calendar.next"].firstMatch.click()
        app.buttons["calendar.previous"].firstMatch.click()
        dateButton.click()
        XCTAssertTrue(app.buttons[eventID].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue("1 项日程", on: dateButton))

        app.terminate()
        app.launch()
        openCalendar(app)
        XCTAssertTrue(dayButton(day, app: app).waitForExistence(timeout: 10))
        dayButton(day, app: app).click()
        XCTAssertTrue(app.buttons[eventID].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[taskID].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons[taskID].firstMatch.label, "恢复为未完成")
        XCTAssertTrue(waitForValue("1 项日程", on: dayButton(day, app: app)))
        capture(app, name: "日程和任务重启后仍在")

        app.descendants(matching: .any)["sidebar.today"].firstMatch.click()
        XCTAssertTrue(app.buttons[eventID].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testMonthYearWeekListAndPanelInteractions() throws {
        let app = makeApp()
        app.launch()
        openCalendar(app)
        dismissUnneededAppDesktopPrompt()
        defer { app.terminate() }
        let heading = app.staticTexts["calendar.heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        let original = text(heading)
        app.buttons["calendar.next"].firstMatch.click()
        XCTAssertNotEqual(text(heading), original)
        app.buttons["calendar.previous"].firstMatch.click()
        XCTAssertEqual(text(heading), original)

        app.descendants(matching: .any)["calendar.year"].firstMatch.click()
        app.menuItems["下一年"].firstMatch.click()
        XCTAssertNotEqual(text(heading), original)
        app.buttons["calendar.today"].firstMatch.click()
        XCTAssertEqual(text(heading), original)

        let calendar = Calendar.current
        let day = try monthDay(15)
        dayButton(day, app: app).click()
        let selectedDate = text(app.staticTexts["agenda.date"])
        app.buttons["agenda.close"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["agenda.date"].waitForNonExistence(timeout: 5))
        dayButton(day, app: app).click()
        XCTAssertTrue(app.staticTexts["agenda.date"].waitForExistence(timeout: 5))
        XCTAssertEqual(text(app.staticTexts["agenda.date"]), selectedDate)

        selectMode("周", app: app)
        XCTAssertTrue(dayButton(day, app: app).waitForExistence(timeout: 5))
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: day))
        let other = calendar.isDate(day, inSameDayAs: week.start)
            ? try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: week.start)) : week.start
        dayButton(other, app: app).click()
        XCTAssertNotEqual(text(app.staticTexts["agenda.date"]), selectedDate)
        capture(app, name: "周视图与日期详情")

        selectMode("列表", app: app)
        let month = try XCTUnwrap(calendar.dateInterval(of: .month, for: other))
        let listDay = app.buttons["calendar.list.day.\(dayID(month.start))"].firstMatch
        XCTAssertTrue(listDay.waitForExistence(timeout: 5))
        listDay.click()
        app.descendants(matching: .any)["calendar.listRange"].firstMatch.click()
        app.menuItems["30 天"].firstMatch.click()
        capture(app, name: "按天分组列表")
        app.buttons["calendar.toggleAgenda"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["agenda.date"].waitForNonExistence(timeout: 5))
        app.buttons["calendar.toggleAgenda"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["agenda.date"].waitForExistence(timeout: 5))
        selectMode("月", app: app)
        XCTAssertTrue(app.buttons["calendar.today"].firstMatch.exists)
    }

    @MainActor
    func testNativeTaskDragPersistsNewPlannedDate() throws {
        let app = makeApp()
        app.launch()
        openCalendar(app)
        dismissUnneededAppDesktopPrompt()
        defer { app.terminate() }
        let sourceDay = try monthDay(15)
        let destinationDay = try monthDay(17)
        XCTAssertTrue(dayButton(sourceDay, app: app).waitForExistence(timeout: 10))
        dayButton(sourceDay, app: app).click()
        app.buttons["agenda.empty.newTask"].firstMatch.click()
        let title = app.textFields["task.editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.click()
        title.typeText("拖拽计划任务")
        app.buttons["task.editor.save"].firstMatch.click()
        let source = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "calendar.drag.")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        allowRunnerDesktopAccessIfPresented()
        app.activate()
        app.buttons["calendar.today"].firstMatch.hover()
        let start = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = dayButton(destinationDay, app: app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.click(forDuration: 0.8, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
        // File access can also be requested while XCTest records its first drag.
        if allowRunnerDesktopAccessIfPresented() {
            app.activate()
            start.click(forDuration: 0.8, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
        }
        capture(app, name: "任务拖动落点")
        XCTAssertTrue(waitForValue("1 项待办", on: dayButton(destinationDay, app: app)))
        XCTAssertTrue(waitForValue("0 项待办", on: dayButton(sourceDay, app: app)))
        capture(app, name: "原生任务拖动改期")
        app.terminate()
        app.launch()
        openCalendar(app)
        XCTAssertTrue(dayButton(destinationDay, app: app).waitForExistence(timeout: 10))
        dayButton(destinationDay, app: app).click()
        XCTAssertTrue(waitForValue("1 项待办", on: dayButton(destinationDay, app: app)))
        let completion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "agenda.complete.")).firstMatch
        XCTAssertTrue(completion.waitForExistence(timeout: 5))
        XCTAssertEqual(completion.label, "标记为完成")
        let movedTask = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "calendar.drag.")).firstMatch
        movedTask.click()
        XCTAssertTrue(app.buttons["task.edit"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["关闭"].firstMatch.click()
    }

    @MainActor
    private func openCalendar(_ app: XCUIApplication) {
        let item = app.descendants(matching: .any)["sidebar.calendar"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.click()
    }

    @MainActor
    private func dismissUnneededAppDesktopPrompt() {
        let notifications = XCUIApplication(bundleIdentifier: "com.apple.UserNotificationCenter")
        for dialog in notifications.dialogs.allElementsBoundByIndex {
            let message = dialog.staticTexts.matching(NSPredicate(
                format: "(label CONTAINS %@ OR value CONTAINS %@) AND NOT (label CONTAINS %@ OR value CONTAINS %@)",
                "Selno", "Selno", "SelnoUITests-Runner", "SelnoUITests-Runner"
            )).firstMatch
            let desktop = dialog.staticTexts.matching(NSPredicate(
                format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@ OR label CONTAINS %@ OR value CONTAINS %@",
                "Desktop", "Desktop", "桌面", "桌面"
            )).firstMatch
            guard message.exists && desktop.exists else { continue }
            let deny = dialog.buttons.matching(NSPredicate(
                format: "title IN %@ OR label IN %@ OR value IN %@",
                ["不允许", "Don’t Allow", "Don't Allow"], ["不允许", "Don’t Allow", "Don't Allow"], ["不允许", "Don’t Allow", "Don't Allow"]
            )).firstMatch
            if deny.exists { deny.click() }
        }
    }

    @MainActor
    @discardableResult
    private func allowRunnerDesktopAccessIfPresented() -> Bool {
        let notifications = XCUIApplication(bundleIdentifier: "com.apple.UserNotificationCenter")
        let message = notifications.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            "SelnoUITests-Runner", "SelnoUITests-Runner"
        )).firstMatch
        guard message.exists else { return false }
        let allow = notifications.buttons.matching(NSPredicate(
            format: "title IN %@ OR label IN %@ OR value IN %@",
            ["允许", "Allow"], ["允许", "Allow"], ["允许", "Allow"]
        )).firstMatch
        guard allow.exists else { return false }
        allow.click()
        return true
    }

    @MainActor
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--selno-ui-testing", "-NSTreatUnknownArgumentsAsOpen", "NO", "-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment["SELNO_UI_TEST_STORE_ID"] = UUID().uuidString
        return app
    }

    private func dayID(_ date: Date) -> String {
        let p = Calendar.current.dateComponents([.era, .year, .month, .day], from: date)
        return "\(p.era ?? 0)-\(p.year ?? 0)-\(p.month ?? 0)-\(p.day ?? 0)-\(p.isLeapMonth == true ? 1 : 0)"
    }

    private func monthDay(_ day: Int) throws -> Date {
        let calendar = Calendar.current
        var parts = calendar.dateComponents([.era, .year, .month], from: .now)
        parts.day = day
        return try XCTUnwrap(calendar.date(from: parts))
    }

    @MainActor
    private func dayButton(_ date: Date, app: XCUIApplication) -> XCUIElement {
        app.buttons["calendar.day.\(dayID(date))"].firstMatch
    }

    @MainActor
    private func selectMode(_ title: String, app: XCUIApplication) {
        let picker = app.descendants(matching: .any)["calendar.mode"].firstMatch
        let choice = picker.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.click()
    }

    @MainActor
    private func newFromMenu(_ title: String, app: XCUIApplication) {
        app.descendants(matching: .any)["agenda.new"].firstMatch.click()
        let item = app.menuItems[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
    }

    @MainActor
    private func waitForValue(_ value: String, on element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", value), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    @MainActor
    private func text(_ element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
