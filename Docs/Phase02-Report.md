# Selno · 序宁 — Phase 02 开发与验收报告

Phase 02 已完成并通过下述验收，未启动下一阶段。验收环境：2026 年 10 月 20 日，Intel Mac、macOS 15.8.1、Xcode 26.3、macOS 26.2 SDK。开发直接在现有 `Selno.xcodeproj` 中完成，沿用共享 Scheme **Selno**。没有创建新工程、删除正式数据库、执行 Git Commit 或 Push。

## 1. 主要新增与修改文件

下表列出相对 Phase 01 的本轮变化；Phase 01 原有模型与业务代码继续复用。

| 文件 | 本轮职责 |
| --- | --- |
| `Selno/App/AppSection.swift`、`MainWindowView.swift` | 今天、日历、收件箱、全部任务四项导航，默认打开当前日期的日历 |
| `Selno/SelnoApp.swift` | 调整初始窗口尺寸，继续使用原有启动与容器机制 |
| `Selno/Features/Calendar/CalendarWorkspace.swift` | 日期、月/周/列表模式、范围切换、年份、定位日期、面板开关 |
| `CalendarMath.swift` | 月历补位、周起始日、闰年、自然日递增、日期格式与导航 |
| `CalendarDataQuery.swift`、`CalendarRangeContent.swift` | 可见范围 SwiftData 查询、按天快照刷新、任务完成与改期入口 |
| `CalendarAgenda.swift` | TODO 日期角色、同日去重、事件跨日相交和每日计数 |
| `CalendarGridView.swift`、`CalendarListView.swift` | 可点击月/周网格、按日期分组列表、当前与选中日期状态 |
| `CalendarHoverTip.swift` | 真实任务/事件摘要、时段、空日期及剩余数量 |
| `DayAgendaView.swift`、`AgendaRows.swift` | 当日安排、完成操作、新建菜单、任务/事件详情入口 |
| `CalendarTaskDrag.swift` | AppKit 鼠标跟踪、原生任务拖放、带前缀的 UUID 载荷校验 |
| `CalendarEventEditorView.swift`、`CalendarEventDetailView.swift` | 日程表单、查看、编辑和确认删除 |
| `Selno/Models/CalendarEvent.swift`、`Services/CalendarEventService.swift` | 独立日程实体、时间校验和显式保存 |
| `Selno/Services/TaskService.swift` | 带计划日期的新任务、仅调整 `plannedAt` 的改期操作 |
| `Selno/Features/Tasks/TaskEditorView.swift`、`TaskDetailView.swift` | 复用原任务编辑能力，显示及编辑日期和时间 |
| `Selno/Features/Tasks/TaskWorkspaceView.swift`、`TaskListView.swift` | 保留原任务列表与详情，“今天”增加当天事件 |
| `Selno/Persistence/SelnoSchema.swift`、`SelnoSchemaV1Models.swift`、`PersistenceController.swift` | 冻结 V1，V2 增加事件，原文件轻量迁移 |
| `SelnoTests/CalendarMathTests.swift`、`CalendarAgendaTests.swift`、`CalendarEventTests.swift` | 日期计算、关联、计数、范围查询、事件持久化与校验测试 |
| `SelnoTests/SchemaMigrationTests.swift`、`Phase01Fixture.swift`、`Fixtures/Phase01.store` | 用原版 Phase 01 实际生成的数据库验证迁移保留数据 |
| `SelnoUITests/CalendarUITests.swift` | 日历核心验收、模式与面板交互、拖动改期验收 |
| `SelnoUITests/SelnoUITests.swift`、`SelnoUITestsLaunchTests.swift` | 适配新的默认入口，回归原收件箱、全部任务、今天和外观启动 |
| `README.md`、本报告 | 当前操作说明、数据约定、架构和实际验证结果 |

用户原有 `ContentView.swift` 中的 `Waiting` 修改及模板 `Item.swift` 保持原样，正式入口继续使用 Phase 01 建立的独立业务视图。

## 2. 日历模块架构

```text
MainWindowView
  ├─ CalendarWorkspace：所选日期、显示范围、模式、面板状态
  │    └─ CalendarRangeContent：可见范围的两条 @Query
  │         └─ CalendarAgendaBuilder：本地日期 → 每日任务与事件快照
  │              ├─ 月/周网格 + 悬停浮层
  │              ├─ 按天列表
  │              └─ 当日安排 → 任务/日程详情和编辑表单
  └─ TaskWorkspaceView：今天、收件箱、全部任务，复用原有功能

编辑/完成/改期 → Service 校验 → ModelContext.save → @Query 更新 → 快照刷新
```

日历只查询当前显示的月网格、七天周或列表范围。事件按区间相交查询，能读取从范围外开始但跨入该范围的事件。没有日期的任务不进入日历查询。完整任务列表只在原有任务工作区加载。

日期网格和范围在切换时计算；按天分组在数据版本变化时计算。悬停与点击复用同一个快照，不为各个日期单独访问数据库。标题、时间或状态修改通过服务更新 `updatedAt` 并保存，触发刷新。分钟时间线更新今天高亮，“今天”在跨日时重建当天事件查询。

外层使用原生 `NavigationSplitView`，日历内部使用 `HSplitView`。右侧面板属于当前工作区；点击日期不会打开新窗口。面板关闭后可通过点击日期或顶部按钮重新展开。

悬停延迟约 350 毫秒；候选日期改变时取消旧等待，移出关闭，拖动改期时清除原日期提示。浮层使用系统材质，最多显示四项及剩余数量，按网格边界调整位置，`allowsHitTesting(false)` 避免拦截点击。任务工作区显式继承同一 Calendar 与 TimeZone。

## 3. CalendarEvent 模型与迁移

| 字段 | 类型与含义 |
| --- | --- |
| `id` | UUID，稳定业务标识 |
| `title`、`notes` | String，标题及备注 |
| `startsAt`、`endsAt` | Date，真实开始和结束时间 |
| `isAllDay` | Bool，是否按全天日期展示 |
| `location` | String?，可选地点 |
| `createdAt`、`updatedAt` | Date，创建与最后修改时间 |

日程不带 TODO 完成状态，不与 Apple Calendar 集成。所有日程和任务均使用 SwiftData 本地持久化，CloudKit 明确关闭。

定时日程要求 `endsAt >= startsAt`，标题不能只有空白；验证在更新模型前进行。区间采用 `[startsAt, endsAt)`，午夜结束不多算次日；零时长日程归入开始时间所在日期。

全天表单显示“结束日期（含）”，保存为开始日的本地午夜至结束日期次日的本地午夜。日期递增使用 Calendar，兼容夏令时的 23/25 小时自然日；再次编辑会反向转换，避免每次保存多加一天。

V1 的五种历史实体已完整冻结。V2 保留原有字段、关系和存储路径，只独立增加 `CalendarEvent`，通过 V1 → V2 lightweight migration 原地升级。没有删库、重建空库或改任务 UUID。正式路径仍是应用沙盒 Application Support 下的 `Selno/Selno.store`。

迁移夹具由修改前的 Phase 01 源码实际生成，包含已完成任务、固定 UUID、三个日期、完成时间、项目、分类、子任务和初始化记录。测试使用内嵌的压缩字节，解压后校验长度与 SHA-256，再写入自身临时目录，避免沙盒宿主读取桌面上的独立测试包而请求整个桌面的权限。测试只迁移临时副本，验证保留这些字段及关系，新增事件后关闭再打开。原文件保留供复核，校验值见夹具 README。

## 4. 与 TodoTask 的关联规则

| 字段 | 日历含义 |
| --- | --- |
| `plannedAt` | 计划执行，日历新建任务默认使用当前选中日的 09:00，可编辑 |
| `plannedStartAt` | 计划开始，单独保留其日期含义 |
| `dueAt` | 最终截止，没有计划日期时也能在截止日看到任务 |
| 全部为空 | 留在收件箱或原任务列表，不自动分配日期 |

同一任务可以在不同日期展示不同角色；同一天按任务 UUID 合并为一项，同时保留“计划执行 / 计划开始 / 最终截止”角色，计数不重复。日期格使用图标区分截止与计划，周摘要、浮层和详情显示角色文字。

待办数只计入 pending、inProgress；完成及取消记录仍可在对应日期查看。任务与事件使用不同图标和分组。任务新建不会把计划日期复制到截止日期。

改期服务只写 `plannedAt` 和 `updatedAt`，保留原计划的时分秒；无原计划时默认 09:00。`dueAt`、`plannedStartAt`、状态及完成时间不变。所有当天判断、分组和范围构造使用一致的 Calendar 与 TimeZone，不截取 UTC 日期字符串。

“今天”保留原有按 UUID 去重的筛选规则：当天计划执行、当天计划开始、当天截止、已逾期且尚未完成的任务；另用区间查询显示当天日程。

## 5. 实际编译与测试结果

所有构建和测试均针对当前工程的真实 **Selno** Scheme 执行。最终结果包为 `.build/phase02/Phase02-Final-Verified.xcresult`，`xcodebuild` 返回 0，结果为 `TEST EXECUTE SUCCEEDED`。

| 检查 | 实际结果 |
| --- | --- |
| Debug `build-for-testing` | 通过，App、SelnoTests、SelnoUITests 均构建成功 |
| Release `build` | 通过；`lipo -info` 确认为 `x86_64 arm64` 通用二进制 |
| 严格签名复核 | 清理生成产物的 Finder 属性后，Debug 与 Release 的 `codesign --verify --deep --strict` 均通过 |
| 最终全量回归 | **39 个测试定义、44 次执行，0 失败、0 预期失败、0 跳过** |
| Swift Testing | 7 个 suite、32 项定义；闰年参数运行四组，任务状态参数运行两组，共 36 次执行 |
| 日历 UI | 创建/编辑/悬停/重启、月年周列表与面板交互、原生拖动改期三个场景通过 |
| 原有任务 UI | 收件箱创建/完成/重启、编辑与全部任务导航、今天计划及完成刷新三个场景通过 |
| 外观启动 | 浅色、深色各一次，通过并人工检查窗口截图 |
| 真实旧库迁移 | 保留任务 UUID、状态、完成时间、三个日期及关联；升级后新增事件并重开查询通过 |
| 夹具完整性 | 原文件 SHA-256 仍为 `5b0c1e439cc01eaa1bcecb166590e18babbc8c7bf13e094716c9ba862d8b562e` |
| 改动检查 | `git diff --check` 通过；未 Commit、未 Push |

逐项对应本轮要求：

| 验收项 | 验证方式与结果 |
| --- | --- |
| 1. 当前月份 | 使用运行时当前日期检查月内天数、首日和完整周补位；UI 默认定位今天，通过 |
| 2. 月份和年份切换 | 跨年数学测试、真实 UI 下一月/上一月/下一年/今天，通过 |
| 3. 闰年 | 2024、2025、2000、2100 年二月参数测试，通过 |
| 4. 月/周/列表 | 实际切换三种模式、列表范围，通过 |
| 5. 点击日期与右侧内容 | 选择日期、切换周内日期、按天列表选择、关闭和重开面板，通过 |
| 6. Hover Tips | 空日期“暂无安排”、真实事件标题/时间/数量、移出关闭，通过 |
| 7. 日历新增任务 | 选定日创建、网格与面板计数更新；无自动截止日期的数据断言，通过 |
| 8. 新增事件 | 表单填写标题及地点、保存后出现真实记录、详情和编辑，通过 |
| 9. 同日混合计数 | 多条任务和三条事件、已完成项、同日计划+截止去重，通过 |
| 10. 完成即时刷新 | 日历待办数降为零、今天列表移除、全部任务保留完成记录，通过 |
| 11. 重启持久化 | UI 完全终止并重启后保留同一 UUID 的任务状态和事件；另有磁盘容器重开测试，通过 |
| 12. Inbox/全部任务 | 原有创建、编辑、导航、完成和恢复、重复重启 UI 回归，通过 |
| 13. 改期不改截止 | 服务测试验证截止、计划开始、完成状态、完成时间均不变；原生 UI 拖动并重启验证新计划日，通过 |

主要证据保存在仓库的忽略目录 `.build/phase02/`：

- `build-for-testing-verified.log`、`release-build-final.log`：实际 Debug/Release 构建日志。
- `final-tests-verified.log`、`test-summary.json`、`Phase02-Final-Verified.xcresult`：最终全量运行及 Xcode 结果统计。
- `signature-verification.log`：两个配置的严格签名复核。
- `screenshots/`：真实数据悬停、重启后安排、拖动改期、周/列表和浅深色窗口截图。

复现命令如下；本机完整 Xcode 的 `DEVELOPER_DIR` 为 `/Users/waiting/Downloads/Xcode.app/Contents/Developer`，仅对命令设置，未修改系统 Xcode 选择或工程签名方式。

```sh
xcodebuild build-for-testing -project Selno.xcodeproj -scheme Selno \
  -configuration Debug -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath .build/DerivedData

xcodebuild test-without-building -project Selno.xcodeproj -scheme Selno \
  -configuration Debug -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath .build/DerivedData -parallel-testing-enabled NO

xcodebuild build -project Selno.xcodeproj -scheme Selno \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath .build/ReleaseDerivedData
```

全部 UI 验收使用专属磁盘库，同一场景重启时复用该库；Swift Testing 使用独立内存或临时磁盘容器，不把验收记录写入正式数据库。夹具读取曾遇到桌面授权阻塞，已改为上述内嵌字节方案，并拒绝先前遗留的多余请求后重新完成全量回归和截图。

## 6. 已完成交互与核心验收

已通过真实 App UI 验证的核心流程：默认打开日历并定位今天 → 点击日期打开当日安排 → 悬停空日期显示“暂无安排” → 新建有地点的定时日程 → 日期计数和右侧列表即时更新 → 悬停显示同一真实日程标题、09:00–10:00 时段和数量 → 打开日程详情并修改标题 → 同日新增任务并完成 → 切换月份再返回，数据仍在 → 完全终止 App 并重新启动 → 相同任务、完成状态和修改后的日程仍存在 → 今天页显示该日程。

月/年切换、返回今天、周/列表切换、按天选择、列表范围切换、面板关闭和重新展开也已在真实 UI 中执行通过。任务与日程的业务校验、日程编辑和删除另有数据测试覆盖。

原生拖拽验收也通过：在当前月份的 15 日新建任务 → 将网格任务条拖到 17 日 → 原日计数归零、目标日出现一项待办、面板同步更新 → 完全退出并重启 → 目标日仍有该任务、保持未完成 → 点击该任务条成功打开详情。月份和年份取运行时当前值，没有固定生产日历到某年某月。

## 7. 已知问题与范围边界

- 已验证 Intel 真机运行。Apple Silicon 已完成 Release 交叉编译，尚未在 Apple Silicon 硬件上运行 UI 测试。
- 拖拽支持当前月/周网格中的可见日期；尚未开发拖动时自动翻月、事件时长拖拽或按小时排程。
- Desktop 文件提供程序会持续给生成的包写回 `com.apple.FinderInfo`，可能使签名步骤失败。本轮只清理 `.build` 产物的该扩展属性并重试，未禁用签名或改变开发团队。参见 [Apple QA1940](https://developer.apple.com/library/archive/qa/qa1940/_index.html)。
- 没有剩余 Swift 源码编译错误或源码警告；Xcode 的 App Intents 元数据工具会提示未发现 `AppIntents.framework`，本阶段没有该功能。
- macOS 15 的 Core Data 在版本化模型加载时输出过 `model is still editable` 的 checksum 诊断；真实旧库迁移、字段/关联保留和重开断言均通过。故意加载损坏文件的保护测试也会输出 SQLite/Core Data 错误，对应测试确认原文件保留。这些诊断没有被写成“没有日志警告”。
- 本阶段未开发 iOS、CloudKit、Apple Calendar、完整通知、自动备份、AI、按小时拖拽时间块、完整项目工作流或高级统计，也未进入下一阶段。
