# 贡献指南

Selno（序宁）是一个本地优先的 macOS 任务、日历与工作台应用。数据默认保存在用户本机的 Application Support 目录，不依赖账号或云端服务。提交代码前，请先阅读本文件与 `SECURITY.md`。

## 仓库结构

```
Selno/                 应用源码
  App/                 入口、根导航、应用级状态
  Features/            Dashboard、Tasks、Calendar、Workspace、Settings
  Models/              SwiftData 模型与业务类型
  Persistence/         容器、版本化 Schema、迁移计划
  Services/            任务、通知等写入服务
  Backup/              JSON 导出、校验、合并与替换导入
  Shared/              通用组件与设计常量
  Resources/           Asset Catalog
SelnoTests/            单元、迁移、备份与性能测试（Swift Testing / XCTest）
SelnoUITests/          UI 测试
Docs/                  各阶段报告与截图
Branding/              图标源文件
```

## 开发环境

- macOS 15 或更新版本
- Xcode 26.x（本项目在 Xcode 26.3 上验证）
- 无需 CocoaPods、Swift Package 或外部服务

若终端只选择了 Command Line Tools，请显式指定完整 Xcode，而不要修改系统全局设置：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

工程使用自动签名并以本机运行（ad-hoc）方式构建，不需要 Apple Developer Team 即可开发和测试。Release 已启用 Hardened Runtime；正式分发签名身份、App Sandbox entitlement、数据迁移与公证属于发布决策，不要在普通功能提交中改动签名身份。

## 构建

```sh
# Debug
xcodebuild build -project Selno.xcodeproj -scheme Selno \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData

# Release（通用二进制）
xcodebuild build -project Selno.xcodeproj -scheme Selno \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath .build/ReleaseDerivedData
```

如果工程位于 iCloud Drive 或“桌面”等文件提供程序目录，构建产物可能带有 `com.apple.FinderInfo` 扩展属性而导致签名失败。请将 DerivedData 指向工程外（例如 `/tmp/...`）或按 Apple QA1940 清理构建产物的扩展属性；不要关闭签名、不要删除用户数据。

## 测试

```sh
# 单元测试（全部）
xcodebuild test -project Selno.xcodeproj -scheme Selno \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData \
  -only-testing:SelnoTests

# 单个测试
xcodebuild test -project Selno.xcodeproj -scheme Selno \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData \
  -only-testing:SelnoTests/Phase05MigrationTests
```

UI 测试需要可交互的 macOS 会话，在无窗口服务器或远程 CI 中可能无法运行：

```sh
xcodebuild test-without-building -project Selno.xcodeproj -scheme Selno \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData \
  -only-testing:SelnoUITests
```

所有测试必须使用隔离的临时库或内存库。UI 测试通过 `--selno-ui-testing` 和 `SELNO_UI_TEST_STORE_ID` 创建专属存储，禁止让测试连接或清理正式用户库。

## Swift 与 SwiftUI 约定

- 面向用户的文案使用中文；标识符、类型名与提交信息使用英文。
- 保持 `MainActor` 默认隔离。不要用 `@unchecked Sendable` 掩盖并发警告；若类型确实跨隔离域传递，应说明其不可变性与同步方式。
- SwiftUI 视图只负责展示与交互，写入通过 `TaskService`、`BackupImportService` 等服务完成，并显式处理 `save()` 失败与 `rollback()`。
- 查询应有明确边界：列表使用 `fetchLimit`，时间范围使用 `Predicate`，避免在 `body` 中执行全表扫描或重复计算。
- 不引入没有测量依据的“优化”；性能改动需附可复现的前后数据。

## Schema 与迁移

- 已发布的版本化模型定义不得原地修改。当前 V4/V5 仍复用可变模型类，V4 尚未完全独立冻结；这一遗留问题记录在 `Docs/Phase055-Report.md`，应作为下一轮 Schema 工作的前置项。
- 任何字段、关系或索引变化都应新增 `SelnoSchemaV6`（依次递增），并在改动前先补齐当前 V5 的冻结定义，同时补充：
  - 版本化 Schema 与 `SchemaMigrationPlan` 迁移阶段；
  - 从上一版本磁盘库升级的测试；
  - 升级后导出/恢复与重复启动测试。
- 删除项目或分类使用 nullify 保留任务；任务自身拥有的实例、步骤、节点与提醒使用 cascade。修改删除规则必须说明数据保留策略。
- 默认分类通过固定 UUID 幂等初始化，不要用“删库重建”解决迁移问题。

## 数据、隐私与安全

- 禁止提交真实任务、日程、联系人、用户数据库、备份 JSON、含个人信息的截图或日志。
- 测试数据必须是合成的；Fixture 需说明生成方式并可复现。
- 备份格式变更必须保持向后兼容，或提升格式版本并提供迁移与拒绝策略。
- 发现凭据或隐私泄露时，不要提交修复前先公开细节；按 `SECURITY.md` 处理。

## 提交规范

建议使用 Conventional Commits：

```
<type>(<scope>): <summary>

<body: motivation and verification>
```

常用类型：`feat`、`fix`、`perf`、`refactor`、`test`、`docs`、`build`、`ci`、`chore`、`security`。

示例：

```
perf(dashboard): limit inbox query to visible rows

Replace the unbounded inbox @Query with a 4-row descriptor and use
fetchCount for the badge. Measured 10,000-task store before/after in
Phase 05.5 report.
```

要求：

- 一个提交只做一类逻辑变更，不混入格式化全仓或无关重构。
- 提交前运行 `git diff --check`，确认没有空白错误与意外文件。
- 不提交 `.build/`、`DerivedData/`、`xcuserdata/`、`.DS_Store`、日志、密钥或本地数据库。
- 不使用 `git add -A` 盲加；逐项检查暂存内容。
- 不强制推送共享分支，不重写已发布历史。

## Pull Request

1. 从 `main` 创建主题分支。
2. 描述变更动机、用户可见影响、测试方式与风险。
3. 确认 Debug 构建、单元测试通过；涉及 UI 时说明是否运行 UI 测试。
4. 涉及迁移、备份或权限时，附升级/恢复路径与回滚说明。
5. 等待审查，不在审查期间强制推送覆盖他人提交。

## License

本仓库当前未声明开源许可证。许可证选择由仓库所有者决定；在明确之前，请勿假设本项目可按某个开源许可证使用或再分发。