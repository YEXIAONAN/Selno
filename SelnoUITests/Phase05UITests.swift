import XCTest

final class Phase05UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    // MARK: - Workspace lifecycle and layout

    @MainActor func testCreateAddResizeReorderFilterSwitchAndRelaunch() throws {
        let app = makeApp(style: "Light")
        app.launch(); settleLaunch(app); defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.workspace"].firstMatch
            .waitForExistence(timeout: 10))

        createWorkspace(named: "论文工作台", in: app)
        let board = app.descendants(matching: .any)["workspace.heading"].firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(board.label, "论文工作台")

        openEditor(in: app)
        addModule("stats", in: app)
        XCTAssertEqual(editCards(app).count, 1)
        let statsID = uuidSuffix(editCards(app)[0].identifier)
        addModule("taskList", in: app)
        XCTAssertEqual(editCards(app).count, 2, "编辑草稿应包含两个模块")
        let taskListCard = editCards(app).first {
            uuidSuffix($0.identifier) != statsID
        }
        XCTAssertNotNil(taskListCard)
        let taskListID = uuidSuffix(taskListCard?.identifier ?? "")
        capture(app, "新建场景的模块草稿")

        // Resize the first module (统计 defaults to 小) to 中 through the
        // supported-size menu.
        let sizeButton = app.descendants(matching: .any)[
            "workspace.module.size.\(statsID)"
        ].firstMatch
        XCTAssertTrue(sizeButton.waitForExistence(timeout: 5))
        XCTAssertTrue((sizeButton.value as? String)?.contains("小") == true,
                      "尺寸菜单应显示当前尺寸，实际为“\(sizeButton.value as? String ?? "nil")”")
        sizeButton.click()
        XCTAssertTrue(app.menuItems["中"].waitForExistence(timeout: 5))
        app.menuItems["中"].click()
        // The synthesized menu click can leave the transient popover on screen
        // even though the selection took effect. Dismiss it with a click on the
        // empty board area; Escape would reach the edit bar's cancel shortcut.
        app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.85)
        ).click()
        XCTAssertTrue(app.menuItems["中"].waitForNonExistence(timeout: 3),
                      "尺寸菜单应关闭")
        XCTAssertTrue(wait(until: {
            (app.descendants(matching: .any)["workspace.module.size.\(statsID)"]
                .firstMatch.value as? String)?.contains("中") == true
        }, timeout: 5), "尺寸菜单应显示新尺寸")

        // Drag the first module to the end drop zone. The reorder is staged in
        // the draft; persistence happens once on 完成.
        let handle = app.descendants(matching: .any)[
            "workspace.module.drag.\(statsID)"
        ].firstMatch
        let endZone = app.descendants(matching: .any)["workspace.edit.dropEnd"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        XCTAssertTrue(endZone.waitForExistence(timeout: 5))
        allowRunnerDesktopAccessIfPresented()
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = endZone.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.click(forDuration: 0.9, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.6)
        XCTAssertTrue(wait(until: {
            self.editCards(app).map(\.identifier) == [
                "workspace.module.card.\(taskListID)",
                "workspace.module.card.\(statsID)"
            ]
        }, timeout: 6), "拖动到末尾后草稿顺序应变化")

        // Give the task list the global data scope. This replaces, rather than
        // combines with, the scene filter.
        let config = app.descendants(matching: .any)[
            "workspace.module.config.\(taskListID)"
        ].firstMatch
        XCTAssertTrue(config.waitForExistence(timeout: 5)); config.click()
        XCTAssertTrue(app.descendants(matching: .any)["workspace.module.config"].firstMatch
            .waitForExistence(timeout: 5))
        selectSegment("module.config.scope", title: "全局数据", in: app)
        app.descendants(matching: .any)["module.config.save"].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)["workspace.module.config"].firstMatch
            .waitForNonExistence(timeout: 5))

        app.descendants(matching: .any)["workspace.edit.done"].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)["workspace.editBoard"].firstMatch
            .waitForNonExistence(timeout: 5))
        XCTAssertEqual(moduleCards(app).count, 2)
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "workspace.module.drag."
        )).count, 0, "正常浏览不应显示拖动手柄")
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "workspace.module.remove."
        )).count, 0, "正常浏览不应显示移除按钮")

        // Edit the scenario's default filter through 管理工作台.
        app.descendants(matching: .any)["workspace.manage"].firstMatch.click()
        app.menuItems["管理工作台"].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)["workspace.editor"].firstMatch
            .waitForExistence(timeout: 5))
        app.descendants(matching: .any)["workspace.editor.filter"].firstMatch.click()
        let pending = app.buttons["filter.status.pending"].firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        if !pending.isHittable { app.scrollViews.firstMatch.swipeUp() }
        pending.click()
        XCTAssertEqual(pending.value as? String, "已选择")
        app.descendants(matching: .any)["workspace.editor.save"].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)["workspace.editor"].firstMatch
            .waitForNonExistence(timeout: 5))
        let source = app.descendants(matching: .any)["workspace.filter.source"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(source.label.contains("待开始"),
                      "场景筛选来源应显示新的规则摘要，实际为“\(source.label)”")
        capture(app, "场景自定义布局与筛选来源")

        // Switching to the global board and back must not leak edit state.
        app.descendants(matching: .any)["sidebar.overview"].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.workspace"].firstMatch
            .waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["workspace.editBoard"].firstMatch.exists)
        sidebarWorkspace(named: "论文工作台", app: app).click()
        XCTAssertTrue(wait(until: { self.appHeading(app) == "论文工作台" }, timeout: 5))

        app.terminate(); app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.heading"].firstMatch
            .waitForExistence(timeout: 10))
        sidebarWorkspace(named: "论文工作台", app: app).click()
        XCTAssertTrue(app.descendants(matching: .any)["workspace.heading"].firstMatch
            .waitForExistence(timeout: 5))
        XCTAssertEqual(moduleCards(app).count, 2, "重启后应保留模块布局")
        XCTAssertTrue(app.descendants(matching: .any)["workspace.filter.source"].firstMatch.exists)
        openEditor(in: app)
        let persistedSize = app.descendants(matching: .any)[
            "workspace.module.size.\(statsID)"
        ].firstMatch
        XCTAssertTrue(persistedSize.waitForExistence(timeout: 5))
        XCTAssertTrue((persistedSize.value as? String)?.contains("中") == true, "重启后应保留模块尺寸")
        app.descendants(matching: .any)["workspace.edit.cancel"].firstMatch.click()
    }

    // MARK: - Cancel, switch and per-scenario edit state

    @MainActor func testCancelRestoresDraftAndScenarioSwitchingClearsEditState() throws {
        let app = makeApp(style: "Light")
        app.launch(); settleLaunch(app); defer { app.terminate() }

        createWorkspace(named: "场景甲", in: app)
        openEditor(in: app)
        addModule("stats", in: app)
        XCTAssertEqual(editCards(app).count, 1)
        app.descendants(matching: .any)["workspace.edit.cancel"].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)["workspace.editBoard"].firstMatch
            .waitForNonExistence(timeout: 5))
        XCTAssertEqual(moduleCards(app).count, 0, "取消应丢弃尚未保存的草稿")

        // Saving the same draft once must persist one module.
        openEditor(in: app)
        addModule("stats", in: app)
        app.descendants(matching: .any)["workspace.edit.done"].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)["workspace.editBoard"].firstMatch
            .waitForNonExistence(timeout: 5))
        XCTAssertEqual(moduleCards(app).count, 1)

        createWorkspace(named: "场景乙", in: app)
        XCTAssertEqual(moduleCards(app).count, 0, "空白场景不应继承其他场景的布局")
        openEditor(in: app)
        addModule("quickActions", in: app)
        XCTAssertEqual(editCards(app).count, 1)
        // Switching scenario while editing must discard the draft and reset the
        // edit state rather than carrying it into the other scene.
        sidebarWorkspace(named: "场景甲", app: app).click()
        XCTAssertTrue(wait(until: {
            self.appHeading(app) == "场景甲" && !self.isEditing(app)
        }, timeout: 5))
        XCTAssertEqual(moduleCards(app).count, 1)

        sidebarWorkspace(named: "场景乙", app: app).click()
        XCTAssertTrue(wait(until: { self.appHeading(app) == "场景乙" }, timeout: 5))
        XCTAssertEqual(moduleCards(app).count, 0, "未点完成的草稿不应写入场景乙")
        openEditor(in: app)
        XCTAssertEqual(editCards(app).count, 0, "重新进入编辑应读取已保存布局")
        app.descendants(matching: .any)["workspace.edit.cancel"].firstMatch.click()

        // Delete a scenario through the sidebar menu; business data and other
        // scene layouts must remain untouched.
        let row = sidebarWorkspace(named: "场景乙", app: app)
        row.rightClick()
        XCTAssertTrue(app.menuItems["删除场景…"].waitForExistence(timeout: 5))
        app.menuItems["删除场景…"].click()
        let confirm = app.buttons["action-button-1"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertEqual(confirm.label, "删除场景")
        confirm.click()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["dashboard.workspace"].firstMatch
            .waitForExistence(timeout: 5), "删除场景后应回到全局工作台")
        sidebarWorkspace(named: "场景甲", app: app).click()
        XCTAssertTrue(wait(until: { self.appHeading(app) == "场景甲" }, timeout: 5))
        XCTAssertEqual(moduleCards(app).count, 1, "删除其他场景不能影响已保存的布局")
    }

    // MARK: - Sidebar reorder

    @MainActor func testSidebarWorkspaceDragReordersAndPersists() throws {
        let app = makeApp(style: "Light")
        app.launch(); settleLaunch(app); defer { app.terminate() }

        createWorkspace(named: "场景甲", in: app)
        createWorkspace(named: "场景乙", in: app)
        let first = sidebarWorkspace(named: "场景甲", app: app)
        let second = sidebarWorkspace(named: "场景乙", app: app)
        XCTAssertLessThan(first.frame.minY, second.frame.minY,
                          "新建的场景应排在已有场景之后")

        // The row text stays a plain selection target; only its small grip is a
        // drag source, so reordering cannot swallow navigation clicks.
        let grip = app.descendants(matching: .image).matching(
            NSPredicate(format: "label == %@", "拖动 场景乙")
        ).firstMatch
        XCTAssertTrue(grip.waitForExistence(timeout: 5))
        let start = grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        start.click(forDuration: 0.8, thenDragTo: end,
                    withVelocity: .slow, thenHoldForDuration: 0.5)

        XCTAssertTrue(wait(until: {
            guard let a = self.sidebarWorkspaceIfPresent(named: "场景甲", app: app),
                  let b = self.sidebarWorkspaceIfPresent(named: "场景乙", app: app) else {
                return false
            }
            return b.frame.minY < a.frame.minY
        }, timeout: 6), "侧栏拖动应改变工作台顺序")

        let storeID = app.launchEnvironment["SELNO_UI_TEST_STORE_ID"]
        app.terminate()
        let relaunched = makeApp(style: "Light", storeID: storeID)
        relaunched.launch(); settleLaunch(relaunched); defer { relaunched.terminate() }
        XCTAssertTrue(wait(until: {
            self.sidebarWorkspaceIfPresent(named: "场景乙", app: relaunched) != nil
        }, timeout: 10))
        guard let a = sidebarWorkspaceIfPresent(named: "场景甲", app: relaunched),
              let b = sidebarWorkspaceIfPresent(named: "场景乙", app: relaunched) else {
            return XCTFail("重启后应保留两个场景")
        }
        XCTAssertLessThan(b.frame.minY, a.frame.minY, "重启后应保留拖动后的顺序")
    }

    // MARK: - Catalog, appearance and narrow layout

    @MainActor func testCatalogGroupingDarkLightAndNarrowWindow() throws {
        let app = makeApp(style: "Light")
        app.launch(); settleLaunch(app); defer { app.terminate() }

        createWorkspace(named: "窄窗口场景", in: app)
        openEditor(in: app)
        app.descendants(matching: .any)["workspace.edit.add"].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)["workspace.catalog"].firstMatch
            .waitForExistence(timeout: 5))
        for category in ["聚焦", "任务与项目", "日历", "快捷操作"] {
            XCTAssertTrue(app.staticTexts[category].firstMatch.exists,
                          "模块目录应包含分类：\(category)")
        }
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "catalog.add."
        )).count, 8, "模块目录应列出八个内置模块")
        // Filtering guarantees the target row is visible and simultaneously
        // covers the catalog's local search.
        let search = app.textFields["catalog.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.click()
        search.typeText("近期")
        XCTAssertTrue(wait(until: {
            app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH %@", "catalog.add."
            )).count == 1
        }, timeout: 5), "目录搜索应只保留匹配模块")
        app.descendants(matching: .any)["catalog.add.upcoming"].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)["workspace.catalog"].firstMatch
            .waitForNonExistence(timeout: 5))
        XCTAssertEqual(editCards(app).count, 1)

        // Shrink the window to the supported minimum and verify the deterministic
        // layout reflows inside the window instead of overlapping or overflowing.
        let window = app.windows.firstMatch
        let original = window.frame
        // The bottom-right corner drag is the same technique used by the earlier
        // dashboard tests. Retry once because the first press can land on the
        // window's shadow when the frame is refreshed during launch.
        for _ in 0..<2 where window.frame.width >= original.width - 100 {
            let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
                .withOffset(CGVector(dx: -2, dy: -2))
            corner.click(forDuration: 0.4,
                         thenDragTo: corner.withOffset(CGVector(dx: -500, dy: -140)),
                         withVelocity: .slow, thenHoldForDuration: 0.3)
            _ = wait(until: { window.frame.width < original.width - 100 }, timeout: 3)
        }
        XCTAssertLessThan(window.frame.width, original.width - 100, "窗口应缩小到窄宽度")
        XCTAssertGreaterThanOrEqual(window.frame.width, 990)
        let board = app.descendants(matching: .any)["workspace.editBoard"].firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        for card in editCards(app) {
            XCTAssertLessThanOrEqual(card.frame.maxX, window.frame.maxX + 2,
                                     "窄窗口下模块不应横向溢出")
        }
        capture(app, "窄窗口下的模块布局")

        app.descendants(matching: .any)["workspace.edit.done"].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)["workspace.editBoard"].firstMatch
            .waitForNonExistence(timeout: 5))
        XCTAssertEqual(moduleCards(app).count, 1)

        // Relaunch in dark appearance; the same store and layout must survive.
        let storeID = app.launchEnvironment["SELNO_UI_TEST_STORE_ID"]
        app.terminate()
        let dark = makeApp(style: "Dark", storeID: storeID)
        dark.launch(); settleLaunch(dark)
        XCTAssertTrue(dark.descendants(matching: .any)["dashboard.heading"].firstMatch
            .waitForExistence(timeout: 10))
        sidebarWorkspace(named: "窄窗口场景", app: dark).click()
        XCTAssertTrue(wait(until: { self.appHeading(dark) == "窄窗口场景" }, timeout: 5))
        XCTAssertEqual(moduleCards(dark).count, 1)
        capture(dark, "深色场景工作台")
    }

    // MARK: - Helpers

    @MainActor private func createWorkspace(named name: String, in app: XCUIApplication) {
        let add = app.descendants(matching: .any)["workspace.add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10)); add.click()
        XCTAssertTrue(app.descendants(matching: .any)["workspace.create"].firstMatch
            .waitForExistence(timeout: 5))
        let field = app.textFields["workspace.create.name"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(name)
        app.descendants(matching: .any)["workspace.create.save"].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)["workspace.create"].firstMatch
            .waitForNonExistence(timeout: 5))
    }

    @MainActor private func openEditor(in app: XCUIApplication) {
        let empty = app.descendants(matching: .any)["workspace.empty.customize"].firstMatch
        let target: XCUIElement
        if empty.waitForExistence(timeout: 1.5) {
            target = empty
        } else {
            target = app.descendants(matching: .any)["workspace.customize"].firstMatch
        }
        XCTAssertTrue(target.waitForExistence(timeout: 5)); target.click()
        XCTAssertTrue(app.descendants(matching: .any)["workspace.editBoard"].firstMatch
            .waitForExistence(timeout: 5))
    }

    @MainActor private func addModule(_ kind: String, in app: XCUIApplication) {
        let add = app.descendants(matching: .any)["workspace.edit.add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.click()
        XCTAssertTrue(app.descendants(matching: .any)["workspace.catalog"].firstMatch
            .waitForExistence(timeout: 5))
        let button = app.descendants(matching: .any)["catalog.add.\(kind)"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        if !button.isHittable {
            // The catalog scrolls; modules below the fold cannot be clicked
            // until they are brought into view. Its own search does that
            // deterministically without relying on swipe distances.
            let search = app.textFields["catalog.search"].firstMatch
            if search.waitForExistence(timeout: 2) {
                search.click()
                search.typeText(catalogQuery(for: kind))
                _ = wait(until: { button.isHittable }, timeout: 3)
            }
        }
        button.click()
        XCTAssertTrue(app.descendants(matching: .any)["workspace.catalog"].firstMatch
            .waitForNonExistence(timeout: 5))
    }

    private func catalogQuery(for kind: String) -> String {
        switch kind {
        case "stats": return "统计"
        case "taskList": return "任务列表"
        case "quickActions": return "快捷"
        case "upcoming": return "近期"
        case "calendar": return "日历"
        case "focus": return "聚焦"
        case "inbox": return "收件箱"
        case "projectProgress": return "项目"
        default: return kind
        }
    }

    @MainActor private func selectSegment(_ identifier: String, title: String,
                                          in app: XCUIApplication) {
        let picker = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let choice = picker.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "分段控件应包含 \(title)")
        choice.click()
    }

    @MainActor private func sidebarWorkspace(named name: String,
                                             app: XCUIApplication) -> XCUIElement {
        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND (label CONTAINS %@ OR value CONTAINS %@)",
            "sidebar.workspace.", name, name
        )).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "侧栏应包含工作台 \(name)")
        return row
    }

    @MainActor private func sidebarWorkspaceIfPresent(named name: String,
                                                      app: XCUIApplication) -> XCUIElement? {
        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND (label CONTAINS %@ OR value CONTAINS %@)",
            "sidebar.workspace.", name, name
        )).firstMatch
        return row.exists ? row : nil
    }

    @MainActor private func editCards(_ app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "workspace.module.card."
        )).allElementsBoundByIndex
    }

    @MainActor private func moduleCards(_ app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier MATCHES %@", "workspace\\.module\\.[0-9A-Fa-f-]{36}"
        )).allElementsBoundByIndex
    }

    @MainActor private func appHeading(_ app: XCUIApplication) -> String? {
        let heading = app.descendants(matching: .any)["workspace.heading"].firstMatch
        return heading.exists ? heading.label : nil
    }

    @MainActor private func isEditing(_ app: XCUIApplication) -> Bool {
        app.descendants(matching: .any)["workspace.editBoard"].firstMatch.exists
    }

    private func uuidSuffix(_ identifier: String) -> String {
        String(identifier.split(separator: ".").last ?? "")
    }

    @MainActor private func wait(until condition: () -> Bool,
                                 timeout: TimeInterval) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date.now.addingTimeInterval(0.1))
        }
        return condition()
    }

    @MainActor private func makeApp(style: String, storeID: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--selno-ui-testing", "-NSTreatUnknownArgumentsAsOpen", "NO",
                               "-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(zh-Hans)",
                               "-AppleLocale", "zh_CN", "-AppleInterfaceStyle", style]
        app.launchEnvironment["SELNO_UI_TEST_STORE_ID"] = storeID ?? UUID().uuidString
        return app
    }

    @MainActor private func settleLaunch(_ app: XCUIApplication) {
        if app.windows.firstMatch.waitForExistence(timeout: 3) { return }
        let notifications = XCUIApplication(bundleIdentifier: "com.apple.UserNotificationCenter")
        if notifications.state != .notRunning {
            let ownMessage = notifications.staticTexts.matching(NSPredicate(
                format: "label CONTAINS %@ OR value CONTAINS %@", "Selno", "Selno"
            )).firstMatch
            if ownMessage.exists {
                let message = "\(ownMessage.label) \(ownMessage.value ?? "")"
                if message.localizedCaseInsensitiveContains("desktop") || message.contains("桌面") {
                    let runner = message.contains("SelnoUITests-Runner")
                    let choices = runner ? ["允许", "Allow"] : ["不允许", "Don’t Allow", "Don't Allow"]
                    let button = notifications.buttons.matching(NSPredicate(
                        format: "title IN %@ OR label IN %@", choices, choices
                    )).firstMatch
                    if button.exists { button.click() }
                }
            }
        }
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10), "Selno 应在启动后打开主窗口")
    }

    @MainActor private func allowRunnerDesktopAccessIfPresented() {
        let notifications = XCUIApplication(bundleIdentifier: "com.apple.UserNotificationCenter")
        guard notifications.state != .notRunning else { return }
        let message = notifications.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            "SelnoUITests-Runner", "SelnoUITests-Runner"
        )).firstMatch
        guard message.exists else { return }
        let allow = notifications.buttons.matching(NSPredicate(
            format: "title IN %@ OR label IN %@",
            ["允许", "Allow"], ["允许", "Allow"]
        )).firstMatch
        if allow.exists { allow.click() }
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}