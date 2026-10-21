import XCTest

/// End-to-end check of the user-facing acceptance flow: export a JSON file through
/// the native save panel, then replace the local store through the native open panel
/// and verify the restored rows survive an app relaunch.
final class Phase04DataManagementUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testExportThenReplaceImportAcrossRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SelnoPhase04UI-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = makeApp()
        app.launch(); settleLaunch(app); defer { app.terminate() }

        createTask("导出验收任务", in: app)

        let settings = app.descendants(matching: .any)["settings.open"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.click()
        let dataTab = app.buttons["数据管理"].firstMatch
        XCTAssertTrue(dataTab.waitForExistence(timeout: 5)); dataTab.click()
        let exportButton = app.buttons["data.export"].firstMatch
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5)); exportButton.click()

        navigatePanel(app, to: directory.path)
        let save = app.buttons["导出"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10)); save.click()

        // Export finishes by presenting a confirmation alert. It is app-modal, so
        // the next click on the import button would otherwise be swallowed.
        let exportDone = app.staticTexts["备份已导出"].firstMatch
        XCTAssertTrue(exportDone.waitForExistence(timeout: 15), "导出完成后没有出现确认提示")
        app.buttons["好"].firstMatch.click()
        XCTAssertTrue(exportDone.waitForNonExistence(timeout: 5))

        let backupURL = try waitForSingleBackup(in: directory)
        let data = try Data(contentsOf: backupURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["format"] as? String, "com.yexiaonan.selno.backup")
        XCTAssertEqual(json["schemaVersion"] as? Int, 2)
        let backupData = try XCTUnwrap(json["data"] as? [String: Any])
        XCTAssertEqual((backupData["tasks"] as? [[String: Any]])?.count, 1)
        let workspaces = try XCTUnwrap(backupData["workspaces"] as? [[String: Any]])
        XCTAssertEqual(workspaces.count, 1, "首次启动应写入且仅写入一个全局工作台")
        XCTAssertEqual(workspaces.first?["isGlobal"] as? Bool, true)
        XCTAssertEqual((workspaces.first?["modules"] as? [[String: Any]])?.count, 7)

        // Created after the export, so a true replace must remove it.
        app.typeKey("w", modifierFlags: .command)
        createTask("替换后应消失的任务", in: app)
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.click()
        XCTAssertTrue(dataTab.waitForExistence(timeout: 5)); dataTab.click()

        let importButton = app.buttons["data.import"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 5)); importButton.click()
        navigatePanel(app, to: backupURL.path)
        let open = app.buttons["打开"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10)); open.click()

        let confirm = app.buttons["data.import.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        let replace = app.radioButtons["替换恢复"].firstMatch
        if replace.waitForExistence(timeout: 3) {
            replace.click()
        } else {
            app.buttons["替换恢复"].firstMatch.click()
        }
        XCTAssertTrue(app.buttons["继续替换…"].waitForExistence(timeout: 5))
        confirm.click()
        let destructive = app.buttons["先备份，再替换"].firstMatch
        XCTAssertTrue(destructive.waitForExistence(timeout: 5)); destructive.click()
        let done = app.buttons["好"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 20)); done.click()

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["sidebar.inbox"].firstMatch.waitForExistence(timeout: 5))
        app.descendants(matching: .any)["sidebar.inbox"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["导出验收任务"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["替换后应消失的任务"].firstMatch.waitForNonExistence(timeout: 10))

        app.terminate(); app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["sidebar.inbox"].firstMatch.waitForExistence(timeout: 10))
        app.descendants(matching: .any)["sidebar.inbox"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["导出验收任务"].firstMatch.waitForExistence(timeout: 10),
                      "替换导入的任务应在重启后仍然存在")
        XCTAssertFalse(app.staticTexts["替换后应消失的任务"].firstMatch.exists)
    }

    @MainActor private func createTask(_ title: String, in app: XCUIApplication) {
        app.descendants(matching: .any)["sidebar.inbox"].firstMatch.click()
        let quick = app.textFields["task.quickAdd"]
        XCTAssertTrue(quick.waitForExistence(timeout: 10)); quick.click()
        quick.typeText("\(title)\n")
        XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 5))
    }

    /// Uses the panel's "Go to Folder" sheet so the test never depends on the
    /// current sidebar selection or a pre-existing save location.
    @MainActor private func navigatePanel(_ app: XCUIApplication, to path: String) {
        XCTAssertTrue(app.dialogs.firstMatch.waitForExistence(timeout: 10), "系统文件面板没有出现")
        // The Go to Folder field is created already focused; clicking the panel's
        // other name field would move focus and make synthesis fail.
        var field = app.textFields["PathTextField"].firstMatch
        for _ in 0..<3 where !field.waitForExistence(timeout: 2) {
            app.typeKey("g", modifierFlags: [.command, .shift])
            field = app.textFields["PathTextField"].firstMatch
        }
        XCTAssertTrue(field.exists, "文件面板未出现前往文件夹输入框")
        field.typeText(path)
        app.typeKey(.return, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.8)
    }

    @MainActor private func waitForSingleBackup(in directory: URL) throws -> URL {
        let deadline = Date.now.addingTimeInterval(10)
        while Date.now < deadline {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            ))?.filter { $0.pathExtension == "json" } ?? []
            if files.count == 1 { return files[0] }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("保存面板未在预期目录生成 JSON 备份：\(directory.path)")
        throw NSError(domain: "Phase04DataManagementUITests", code: 1)
    }

    @MainActor private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--selno-ui-testing", "-NSTreatUnknownArgumentsAsOpen", "NO",
                               "-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(zh-Hans)",
                               "-AppleLocale", "zh_CN", "-AppleInterfaceStyle", "Light"]
        app.launchEnvironment["SELNO_UI_TEST_STORE_ID"] = UUID().uuidString
        return app
    }

    @MainActor private func settleLaunch(_ app: XCUIApplication) {
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }
}