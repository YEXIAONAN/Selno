import XCTest

final class Phase03UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testCampusTemplateTagsMilestonesAndRelaunch() throws {
        let app = makeApp(style: "Dark")
        app.launch(); settleLaunch(app); defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.heading"].waitForExistence(timeout: 10))
        app.descendants(matching: .any)["dashboard.new"].firstMatch.click()
        app.menuItems["新建任务"].firstMatch.click()
        let title = app.textFields["task.editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.click(); title.typeText("校园科技文化活动")
        app.descendants(matching: .any)["template.selector"].firstMatch.click()
        app.menuItems.matching(NSPredicate(format: "title CONTAINS %@", "校园二课活动")).firstMatch.click()
        let tags = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tag.select."))
        XCTAssertTrue(tags.firstMatch.waitForExistence(timeout: 5))
        tags.element(boundBy: 0).click(); tags.element(boundBy: 2).click(); tags.element(boundBy: 3).click()
        capture(app, "二课模板创建与多标签")
        let activity = app.disclosureTriangles["活动"].firstMatch
        reveal(activity, app: app); activity.click()
        let start = app.checkBoxes["field.enable.activityStarts"].firstMatch
        reveal(start, app: app); start.click()
        let calendar = app.checkBoxes["显示在日历"].firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 5)); calendar.click()
        let end = app.checkBoxes["field.enable.activityEnds"].firstMatch
        reveal(end, app: app); end.click()
        capture(app, "二课活动多时间节点表单")
        app.buttons["task.editor.save"].firstMatch.click()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        let focus = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "校园科技文化活动")).firstMatch
        XCTAssertTrue(focus.waitForExistence(timeout: 5)); focus.click()
        XCTAssertTrue(app.staticTexts["task.detail.title"].waitForExistence(timeout: 5))
        capture(app, "任务快照与多时间节点详情")
        app.buttons["关闭"].firstMatch.click()
        app.descendants(matching: .any)["sidebar.calendar"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["agenda.date"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "agenda.complete.")).firstMatch.exists)
        capture(app, "日历任务节点与独立日程区分")
        app.terminate(); app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.heading"].waitForExistence(timeout: 10))
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
        XCTAssertTrue(focus.label.contains("活动开始时间"), "重启后应保留已选择显示的日历节点")
        focus.click()
        XCTAssertTrue(app.descendants(matching: .any)["task.template.snapshot"].firstMatch.waitForExistence(timeout: 5), "重启后应保留模板实例快照")
    }

    @MainActor func testTagAndTemplateManagement() throws {
        let app = makeApp(style: "Light")
        app.launch(); settleLaunch(app); defer { app.terminate() }
        let settings = app.descendants(matching: .any)["settings.open"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.click()
        let tags = app.buttons["标签"].firstMatch
        XCTAssertTrue(tags.waitForExistence(timeout: 5)); tags.click()
        app.buttons["tags.new"].firstMatch.click()
        let name = app.textFields["tag.editor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.click(); name.typeText("校园二课与材料整理")
        let emoji = app.textFields["tag.editor.emoji"]; emoji.click(); emoji.typeText("🏫")
        app.descendants(matching: .any)["tag.editor.color"].firstMatch.click()
        app.menuItems["琥珀"].firstMatch.click()
        app.buttons["tag.editor.save"].firstMatch.click()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        capture(app, "浅色标签管理与配色")
        app.buttons["任务模板"].firstMatch.click()
        app.buttons["templates.new"].firstMatch.click()
        let templateName = app.textFields["template.editor.name"]
        XCTAssertTrue(templateName.waitForExistence(timeout: 5)); templateName.click(); templateName.typeText("自定义材料任务")
        app.descendants(matching: .any)["template.editor.addField"].firstMatch.click()
        app.menuItems["文本"].firstMatch.click()
        let fieldDisclosure = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "template.field.toggle.")).firstMatch
        reveal(fieldDisclosure, app: app); fieldDisclosure.click()
        let fieldName = app.textFields["template.field.name"].firstMatch
        reveal(fieldName, app: app); fieldName.click(); fieldName.typeKey("a", modifierFlags: .command); fieldName.typeText("提交说明")
        capture(app, "模板字段与默认标签编辑")
        app.buttons["template.editor.save"].firstMatch.click()
        XCTAssertTrue(templateName.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["自定义材料任务"].firstMatch.waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command)
        app.descendants(matching: .any)["sidebar.inbox"].firstMatch.click()
        app.descendants(matching: .any)["task.fromTemplate"].firstMatch.click()
        let taskTitle = app.textFields["task.editor.title"]
        XCTAssertTrue(taskTitle.waitForExistence(timeout: 5)); taskTitle.click(); taskTitle.typeText("标签筛选与窄窗口验收")
        let longTag = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "tag.select.", "校园二课与材料整理")).firstMatch
        reveal(longTag, app: app); longTag.click()
        app.buttons["task.editor.save"].firstMatch.click()
        XCTAssertTrue(taskTitle.waitForNonExistence(timeout: 5))
        let quick = app.textFields["task.quickAdd"]
        XCTAssertTrue(quick.waitForExistence(timeout: 5)); quick.click(); quick.typeText("未标记的待整理任务\n")
        XCTAssertTrue(app.staticTexts["未标记的待整理任务"].firstMatch.waitForExistence(timeout: 5))
        let filter = app.descendants(matching: .any)["tags.filter"].firstMatch
        XCTAssertTrue(filter.waitForExistence(timeout: 5)); filter.click()
        app.menuItems.matching(NSPredicate(format: "title CONTAINS %@", "校园二课与材料整理")).firstMatch.click()
        XCTAssertTrue(app.staticTexts["标签筛选与窄窗口验收"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["未标记的待整理任务"].firstMatch.waitForNonExistence(timeout: 5))
        let window = app.windows.firstMatch
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -2, dy: -2))
        corner.click(forDuration: 0.3, thenDragTo: corner.withOffset(CGVector(dx: -280, dy: -100)))
        XCTAssertGreaterThanOrEqual(window.frame.width, 990)
        capture(app, "浅色收件箱标签筛选与长名称")
        filter.click(); app.menuItems["全部标签"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["未标记的待整理任务"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor func testBrandLifecycleReduceMotionAndAccessibleStaticText() throws {
        let app = makeApp(style: "Light")
        app.launchArguments += ["--selno-test-reduce-motion", "--selno-test-voiceover"]
        app.launch(); settleLaunch(app); defer { app.terminate() }
        let heading = app.descendants(matching: .any)["dashboard.heading"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        XCTAssertEqual(heading.label, "每一件事，有条不紊。")
        for _ in 0..<3 {
            app.descendants(matching: .any)["sidebar.inbox"].firstMatch.click()
            app.descendants(matching: .any)["sidebar.overview"].firstMatch.click()
        }
        XCTAssertEqual(heading.label, "每一件事，有条不紊。")
        for _ in 0..<3 {
            app.menuBars.menuBarItems["文件"].firstMatch.click()
            app.menuItems["新Selno窗口"].firstMatch.click()
            XCTAssertTrue(app.windows.element(boundBy: 1).waitForExistence(timeout: 5))
            app.typeKey("w", modifierFlags: .command)
            XCTAssertTrue(app.windows.element(boundBy: 1).waitForNonExistence(timeout: 5))
        }
        capture(app, "浅色总览与低动态辅助功能")
        app.terminate(); app.launch()
        XCTAssertTrue(heading.waitForExistence(timeout: 10)); XCTAssertEqual(heading.label, "每一件事，有条不紊。")
    }

    @MainActor func testBrandAnimationPausesBehindSettingsAndResumes() throws {
        let app = makeApp(style: "Light")
        app.launch(); settleLaunch(app); defer { app.terminate() }
        let heading = app.descendants(matching: .any)["dashboard.heading"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        let first = "每一件事，有条不紊。"
        XCTAssertTrue(wait(until: { heading.label == first && (heading.value as? String) == first }, timeout: 6))
        app.descendants(matching: .any)["settings.open"].firstMatch.click()
        XCTAssertTrue(app.buttons["templates.new"].firstMatch.waitForExistence(timeout: 5))
        let pausedValue = heading.value as? String
        let pausedLabel = heading.label
        let until = Date.now.addingTimeInterval(6)
        let pause = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in Date.now >= until }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [pause], timeout: 7), .completed)
        XCTAssertEqual(heading.value as? String, pausedValue)
        XCTAssertEqual(heading.label, pausedLabel)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(wait(until: { heading.label != pausedLabel }, timeout: 8))
        capture(app, "品牌文案前后台暂停与恢复")
    }

    @MainActor private func wait(until condition: @escaping @MainActor () -> Bool, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in MainActor.assumeIsolated { condition() } }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor private func makeApp(style: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--selno-ui-testing", "-NSTreatUnknownArgumentsAsOpen", "NO", "-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-AppleInterfaceStyle", style]
        app.launchEnvironment["SELNO_UI_TEST_STORE_ID"] = UUID().uuidString
        return app
    }
    @MainActor private func settleLaunch(_ app: XCUIApplication) {
        if app.windows.firstMatch.waitForExistence(timeout: 3) { return }
        let notifications = XCUIApplication(bundleIdentifier: "com.apple.UserNotificationCenter")
        let ownMessage = notifications.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Selno", "Selno")).firstMatch
        if ownMessage.exists {
            let message = "\(ownMessage.label) \(ownMessage.value ?? "")"
            if message.localizedCaseInsensitiveContains("desktop") || message.contains("桌面") {
                let runner = message.contains("SelnoUITests-Runner")
                let choices = runner ? ["允许", "Allow"] : ["不允许", "Don’t Allow", "Don't Allow"]
                let button = notifications.buttons.matching(NSPredicate(format: "title IN %@ OR label IN %@", choices, choices)).firstMatch
                if button.exists { button.click() }
            }
        }
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10), "Selno 应在启动后打开主窗口")
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0..<5 where !element.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
