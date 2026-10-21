# Selno · 序宁 — Phase 01 开发报告

验收日期：2026 年 10 月 20 日。Phase 01 已完成，未启动 Phase 02。

## 1. 完成内容

- 在原有 `Selno.xcodeproj` 中实施，复用 Selno、SelnoTests、SelnoUITests 三个 Target 和 Selno Scheme；补充可共享的 Scheme。
- 最低系统从原来的 macOS 15.8 调整为 15.0，默认开发语言设为简体中文，应用显示名为 Selno；Bundle Identifier 保持 `com.yexiaonan.Selno`。
- 使用原生 `NavigationSplitView` 建立今天、收件箱、全部任务三个入口；列表区分待办、已完成、已取消，并支持选择查看详情。
- 快速输入标题并回车创建任务；拒绝空白标题、修剪首尾空格，使用 pending、normal 和收件箱默认值。
- 支持完成与恢复未完成，分别记录和清除完成时间；通过 SwiftData 查询和观察自动刷新列表。
- 提供基础编辑表单：标题、备注、状态、重要性、计划日期、截止日期。表单取消不会修改数据。
- 今天按当前日历和时区筛选当天计划执行、当天计划开始、当天截止及已逾期待办；按任务去重，排除完成和取消记录。日期边界采用半开区间，明天零点不会误入今天。
- 建立本地磁盘容器、显式保存与失败回滚、数据库初始化失败信息和重试入口。不会通过删除数据库或静默切换到空内存库处理启动失败。
- 首次创建学习、竞赛、校园、开发、生活五个分类；使用固定 UUID 和数据库内初始化标记，重复启动、改名、归档或删除分类都不会造成重复初始化。
- 使用系统字体、SF Symbols 和系统原生控件，适配浅色、深色与窗口缩放。任务详情可展示并独立切换已有子任务的完成状态。

## 2. 工程结构

| 新增或修改的核心文件 | 职责 |
| --- | --- |
| `Selno/SelnoApp.swift` | 应用入口、窗口、容器注入、启动失败界面 |
| `Selno/App/AppBootstrap.swift` | 打开存储、初始化分类、Debug 测试存储隔离 |
| `Selno/App/MainWindowView.swift` | 三栏导航、任务选择、创建入口 |
| `Selno/Models/TodoProject.swift` | 项目及任务关联、归档日期 |
| `Selno/Models/TodoTask.swift` | 核心任务、计划与截止日期、派生紧急程度和子任务排序 |
| `Selno/Models/TaskStep.swift` | 一级子任务、排序及独立完成时间 |
| `Selno/Models/TaskCategory.swift` | 分类及关联任务 |
| `Selno/Models/TaskEnums.swift` | 稳定状态、重要性原始值及中文显示 |
| `Selno/Persistence/PersistenceController.swift` | 正式磁盘、内存测试与指定磁盘容器配置 |
| `Selno/Persistence/SelnoSchema.swift` | V1 schema 及后续迁移入口 |
| `Selno/Persistence/DefaultDataSeeder.swift`、`SeedRecord.swift` | 分类幂等初始化及原子保存标记 |
| `Selno/Services/TaskService.swift` | 校验、创建、更新、完成操作、子任务操作与显式保存 |
| `Selno/Features/Dashboard/TodayTaskFilter.swift` | 今天的日期过滤规则 |
| `Selno/Features/Tasks/TaskListScope.swift`、`TaskListView.swift`、`TaskRowView.swift` | 列表范围、排序、分组、快速创建和完成操作 |
| `Selno/Features/Tasks/TaskDetailView.swift`、`TaskEditorView.swift` | 详情、基础编辑草稿和可选日期控件 |
| `Selno/Shared/Components/PresentedError.swift` | 界面错误展示数据 |
| `SelnoTests/SelnoTests.swift`、`PersistenceTests.swift`、`TaskListTests.swift` | 数据行为、真实磁盘重开、初始化与日期筛选测试 |
| `SelnoUITests/SelnoUITests.swift`、`SelnoUITestsLaunchTests.swift` | 真实应用交互、完全退出重启与两种外观截图 |
| `Selno.xcodeproj/project.pbxproj`、共享 `Selno.xcscheme` | 系统版本、中文默认语言、显示名和测试宿主隔离 |
| `README.md`、`.gitignore` | 运行说明、架构约定与生成产物忽略规则 |

开发前 Git 只存在 `ContentView.swift` 中将模板文字改为 `Waiting` 的未提交修改。该文件及其依赖的模板 `Item.swift` 均原样保留，正式 App 使用独立的 `MainWindowView`。原模板存储未删除、未覆盖，也未将时间戳演示记录虚构转换为业务任务。

## 3. 数据模型

```text
TodoProject  1 ─── 多 TodoTask  1 ─── 多 TaskStep
TaskCategory 1 ─── 多 TodoTask
```

所有实体使用 UUID 作为业务标识。任务的项目、分类和子任务的父任务为可选关系；集合关系也使用可选类型并提供安全访问。反向关系明确指定，无数据库自增 ID 和唯一约束。

项目与分类使用 nullify 删除规则：删除它们只清除关联，任务仍然保留。任务对子任务使用 cascade 规则；子任务不能再嵌套子任务。归档日期目前是模型字段，尚未提供归档业务流程。

状态与重要性保存固定英文原始值，中文只用于显示。任务紧急程度由截止日期按自然日动态计算，不存为长期字段。计划开始、计划执行和最终截止分别存储。未知枚举原始值有安全显示回退，读取不会改写原始数据。

`SeedRecord` 是初始化元数据，不是第五种业务功能。它与分类在同一个数据库事务中保存，不依赖分类名称、全局偏好设置或生产数据库之外的标记文件。

正式数据保存在应用沙盒 Application Support 下的 `Selno/Selno.store`，CloudKit 明确关闭。主 context 关闭自动保存，业务操作在返回成功前显式保存；失败时回滚并显示错误。测试容器与正式文件隔离。

## 4. 编译与测试

验证环境：Intel Mac，macOS 15.8.1，Xcode 26.3，macOS 26.2 SDK。仅对构建命令设置 `DEVELOPER_DIR`；未修改系统 Xcode 选择、签名方式或开发团队。

| 检查 | 实际结果 |
| --- | --- |
| 原工程基线构建 | 通过；首次签名遇到生成产物 Finder 属性问题，清理后重试通过 |
| 最终 Debug `build-for-testing` | 通过，包含 App 和两个测试 Target |
| 最终 Release 构建 | 通过；`lipo -info` 确认为 `x86_64 arm64` 通用二进制 |
| 生成产物签名复核 | 清除环境写入的 Finder 属性后，Debug 与 Release 的 `codesign --verify --deep --strict` 均通过 |
| 自动化测试 | 全部通过：21 个测试定义、23 次执行，0 失败、0 跳过 |
| Swift Testing | 17 项定义；完成状态测试对 pending、inProgress 分别执行 |
| UI 功能测试 | 创建/完成/重启、基础编辑/导航、今天计划/完成刷新三个场景通过 |
| 外观启动测试 | 浅色与深色各运行一次，通过并保存窗口截图 |
| 临时磁盘持久化 | 通过；释放并重新创建磁盘 ModelContainer 后保留任务、完成时间、项目/分类/子任务关联和初始化标记 |
| 无效数据库保护 | 通过；加载预先写入的无效文件后报告失败，原文件字节保持不变 |
| 最终改动检查 | `git diff --check` 通过；未提交或推送 Git |

**核心验收已在真实 App UI 中执行并通过：**进入收件箱，输入“准备人工智能竞赛材料”并回车，确认列表出现，点击完成，完全终止进程，再启动同一 App，确认相同任务仍存在且显示已完成。随后恢复未完成，再次退出重启，恢复后的状态也保留。该测试使用专属磁盘文件，既验证真实持久化，也避免把验收任务写入用户正式数据库。

主要证据均在仓库的忽略目录 `.build/phase01/`：

- `build-for-testing-verified-retry.log`：最终 Debug 测试构建成功日志。
- `release-build-verified.log`：最终双架构 Release 构建成功日志。
- `acceptance-tests.log`、`test-summary.json`、`Phase01-Acceptance.xcresult`：最终测试日志、统计及完整结果包。
- `signature-verification.log`：Debug 与 Release 的严格签名复核结果。
- `screenshots/inbox-completed-after-relaunch.png`、`task-editor.png`、`launch-light.png`、`launch-dark.png`：退出重启、编辑和两种外观的窗口截图。

警告与验证边界：

- 没有剩余 Swift 源码编译错误或源码警告。Xcode 工具会提示 `Metadata extraction skipped. No AppIntents.framework dependency found.`；本阶段没有开发 App Intents。
- 当前 Desktop 文件提供程序会持续给新生成的 App/测试包写入 `com.apple.FinderInfo`，可使签名步骤和构建后的独立签名检查失败。本轮仅针对 `.build` 产物清除此属性并重试，最终签名构建及严格签名复核通过，未禁用工程签名；该环境属性以后仍可能被重新写回。原因和处理方式可参见 [Apple QA1940](https://developer.apple.com/library/archive/qa/qa1940/_index.html)。
- 损坏数据库保护测试会故意产生 Core Data/SQLite 错误诊断；对应测试成功验证原文件未被删除。
- 已验证 Intel 真机运行；Apple Silicon 已完成交叉编译，未在 Apple Silicon 硬件上执行 UI 测试。

## 5. 未完成内容

以下均未作为已完成功能交付：完整项目管理、分类管理、子任务创建/排序界面、归档/软删除业务、回收站、跨版本数据迁移和旧模板数据转换。

本轮未开发完整日历、日期悬停提示、右侧日历详情、系统通知、稍后提醒、重复任务调度、长期目标、每周统计、全局浮动窗口、附件、自动备份、iCloud/CloudKit、iOS、AI、账户、后端或网络 API。

V1 schema、项目关系和归档字段只构成后续扩展基础，不代表同步、迁移或归档产品能力已经完成。

## 6. 下一阶段建议

建议先完善项目创建与任务分配、分类选择和子任务录入/排序，再迭代任务安排体验。正式修改持久化字段前，应冻结 V1 的完整模型定义、增加下一版本与迁移测试。日程、提醒和目标实体应留到对应需求验证后设计。

本次工作停在 Phase 01，等待下一阶段指令。
