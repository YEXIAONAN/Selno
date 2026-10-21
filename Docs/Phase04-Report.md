# Selno · 序宁｜Phase 04 工程交付报告

日期：2026-10-21。基于现有工程增量开发，没有重建项目，没有 Commit 或 Push。

本轮按指定优先级交付：先完成完整 JSON 导入与导出，再完成通知与提醒，最后改善高频操作。测试只使用独立的内存库、临时磁盘库或 UI 测试专属存储；没有清空、覆盖或迁移用户的正式数据库，没有重置 Git 工作区，也没有删除既有功能来简化实现。

## 1. 实际实现

### 1.1 JSON 导出与导入（P0）

数据管理统一位于「设置 → 数据管理」，没有增加侧边栏一级入口。页面分为导出备份、导入备份、安全与恢复三部分。

**导出**

- 使用原生 `NSSavePanel`，默认文件名 `Selno-Backup-YYYY-MM-DD.json`，类型为 UTF-8 JSON。
- 导出全部用户数据：任务（状态、重要性、创建／更新／完成时间、计划开始、计划执行、最终截止、归档时间）、子任务、所属项目、旧分类与多标签、任务模板、生成任务上的模板快照、时间节点（含日历选择和提醒提前量）、独立日程、任务提醒配置。
- UUID 稳定；关系以 UUID 引用，不使用数组下标。所有实体按 UUID 排序，便于比较和复现。
- 日期统一写为 ISO 8601 UTC、带小数秒；读取时同时接受无小数秒的旧式写法。
- 顶层写入格式标识、Schema 版本、导出时间、应用版本和时区。
- 导出只读取 context，不插入、不更新、不保存任何业务对象；有测试比较导出前后的完整快照。
- 写入使用临时文件加原子替换，避免中断留下半个 JSON 文件。

**导入**

- 使用原生 `NSOpenPanel` 选择文件，读取前检查大小（上限 128 MB）、目录与可读性。
- 先完整解码和校验，再显示预览；预览展示文件记录数、本地现有记录数、合并将新增与将跳过的数量。用户明确选择「合并导入」或「替换恢复」后才写入。
- 合并模式按稳定 UUID 匹配；任务、项目、标签、模板、日程已存在时保留本地版本，只补充新记录，并报告跳过数量。若任务的子项（子任务、模板快照、时间节点）与本地 ID 冲突，整条任务跳过，避免把两套快照拼接在一起。重复导入同一文件是幂等的，不会产生重复数据。
- 替换恢复先写一份 `Selno-PreRestore-<时间戳>.json` 安全备份到 `Application Support/Selno/Backups`；文件名冲突时追加序号。安全备份写入失败时不会开始替换。
- 替换在单个 context 事务内完成：按依赖顺序删除旧提醒、节点、实例、子任务、任务、日程、模板、标签与项目，再插入备份内容，最后只调用一次 `save()`。任一步失败执行 `rollback()`，内存与磁盘都回到导入前状态。
- 校验覆盖：格式标识、未来 Schema 版本、重复 ID、空名称／标题、未知状态与重要性、断裂的项目／分类／标签关系、重复标签关联、非有限日期、全天日程结束不晚于开始、定时日程结束早于开始、提醒任务与类型、提前量范围 0…525600 分钟、非法 Base64。
- 缺失的可选集合按空数组处理；缺失的可选字段使用安全默认值。无法识别的未来模板定义或载荷以 Base64 原字节保留，不猜测、不重写。
- 导入成功后发送数据变更通知，任务与日程工作区清除旧选择、撤销条和待打开任务，避免引用已被替换的行；提醒由已有的保存后协调机制重新建立。
- 同一任务同一类型只登记一条通知；合并导入的重复提醒按 UUID 及「任务 + 类型」去重，不会重复注册。

### 1.2 通知与提醒（P1）

- 新增 `TaskReminder`：截止前提醒与指定时间提醒两种类型，提前量支持 7 天／3 天／1 天预设和 1…525600 分钟自定义；指定时间提醒使用本地日期时间。
- 任务编辑器可分别开启两类提醒；没有截止日期时自动关闭截止提醒；指定时间已经过去时明确提示不会补发。任务详情显示提醒类型、提前量、延后时间和当前状态。
- 通知使用 `UNUserNotificationCenter` 和 `UNCalendarNotificationTrigger`，没有轮询。标识为 `selno.task.<UUID>` 与 `selno.node.<UUID>`，重复协调只会替换同一 ID。
- 通知类别提供「查看任务」「10 分钟后提醒」「1 小时后提醒」；点击通知可在应用内定位任务，冷启动也能消费待打开任务 ID。延后写入 `snoozeUntil`，到点后重新安排，不会回退到原时间二次触发。
- 任务完成、取消、归档或删除会移除对应待发送通知；修改日期或提前量会更新；重复行只保留一条参与调度。
- 启动、窗口激活、显式保存和手动「立即重新核对」都会触发串行、防抖的协调；缺少权限、任务未配置、时间已过、重复行和注册失败都有独立状态，不会静默堆叠。
- 安静时段可配置开始与结束时间，支持跨午夜；落入窗口的提醒顺延到窗口结束。已经过去的提醒不会因为顺延而复活。
- 设置页显示真实授权状态，可请求权限或打开系统通知设置，并如实说明：应用未运行或系统休眠时不执行应用内核对；已经错过的提醒不会补发；模板节点提醒与任务提醒共用同一系统通道。
- 模板时间节点继续复用同一提醒系统，没有另建第二套调度。

### 1.3 高频操作（P2）

- 收件箱与全部任务提供全局搜索，匹配标题、备注、项目、标签和保留的旧分类名称。
- 状态、项目、标签筛选与排序组合使用；日常状态筛选不会把已归档任务混入待办、已完成或已取消。
- 列表支持多选；批量栏可完成、添加标签、移动项目、归档／取消归档、删除和清除选择，全部通过 `TaskService` 在一个事务内保存，失败回滚。
- 删除需要确认；删除后显示 12 秒撤销条，可从 JSON 快照恢复原 ID、关系、子任务、节点与提醒。替换导入会清除不再有效的撤销快照。
- 新建任务后清除可能隐藏它的筛选条件，短暂高亮对应行并显示提示；编辑器保存后回到匹配的详情。
- 所有新增控件沿用现有 `SelnoDesign` 语义色、按钮和标签样式，保留深浅模式与原生 macOS 交互。

## 2. 主要文件变更

### 新增

| 文件／目录 | 职责 |
| --- | --- |
| `Selno/Backup/BackupModels.swift` | 版本化 JSON 文档与全部实体 DTO、容错解码、日期编码 |
| `Selno/Backup/BackupCodec.swift` | 编解码、格式版本与结构／关系／日期校验 |
| `Selno/Backup/BackupExportService.swift` | 只读汇总、稳定排序、原子写入、文件读取与去重命名 |
| `Selno/Backup/BackupImportService.swift` | 预览、合并计划、替换、安全备份、单事务提交与回滚 |
| `Selno/Features/Settings/DataManagementView.swift` | 设置中的数据管理、原生面板、预览确认与结果反馈 |
| `Selno/Features/Settings/ReminderSettingsView.swift` | 权限、安静时段、手动核对与行为说明 |
| `Selno/Models/TaskReminder.swift` | 提醒模型、类型、状态、通知 ID 与基础触发时间 |
| `Selno/Services/NotificationCenterCoordinator.swift` | 通知类别、前台展示、打开任务与延后动作 |
| `Selno/Features/Tasks/TaskQueryFilter.swift` | 搜索、状态／项目／标签筛选与排序 |
| `Selno/Features/Tasks/TaskUndoCenter.swift` | 删除快照、12 秒撤销窗口与恢复 |
| `Selno/Persistence/SelnoSchemaV3Models.swift` | 冻结 Phase 03 的 V3 定义，供迁移测试与迁移链使用 |
| `SelnoTests/Phase04BackupTests.swift` | 导出、合并、替换、回滚、格式与真实磁盘往返 |
| `SelnoTests/Phase04MigrationTests.swift` | V3 → V4 迁移及迁移后导出恢复 |
| `SelnoTests/Phase04ReminderTests.swift` | 提醒生命周期、安静时段、权限、重复与错过 |
| `SelnoTests/Phase04TaskWorkflowTests.swift` | 搜索筛选、批量操作、删除快照与撤销 |
| `SelnoUITests/Phase04DataManagementUITests.swift` | 原生面板导出 → 替换导入 → 重启保留的端到端验收 |

### 修改

- `Selno/Persistence/SelnoSchema.swift`、`PersistenceController.swift`：V4 Schema、V3 → V4 轻量迁移、自动备份目录。
- `Selno/Models/TodoTask.swift`：归档时间；`Models/TaskTemplate.swift`：节点与提醒状态衔接。
- `Selno/Services/TaskService.swift`：提醒配置、批量完成／标签／项目／归档、删除快照与恢复。
- `Selno/Services/ReminderService.swift`：任务提醒与节点提醒统一协调、安静时段、权限与失败状态。
- `Selno/Shared/Components/ReminderReconciliation.swift`：启动、保存、激活和手动通知触发。
- `Selno/Features/Settings/SettingsWorkspace.swift`：新增「数据管理」「提醒」设置页。
- `Selno/Features/Tasks/TaskListView.swift`、`TaskWorkspaceView.swift`、`TaskEditorView.swift`、`TaskDetailView.swift`、`TaskRowView.swift`、`TaskListScope.swift`：搜索筛选、多选批量、提醒录入与展示、新建反馈。
- `Selno/App/MainWindowView.swift`、`AppBootstrap.swift`、`SelnoApp.swift`：通知冷却、数据替换后的导航清理、协调挂载。
- `Selno/Features/Calendar/CalendarDataQuery.swift`、`Dashboard/DashboardDataQuery.swift` 等：排除已归档任务。
- UI 测试辅助：系统通知代理未运行时不再查询其无障碍树，避免测试宿主因系统代理停止而误报。
- `SelnoTests/Phase03Tests.swift`：把一个依赖运行时刻的节点测试固定在当天 09:00，消除 17:00 后跨午夜造成的假失败；产品行为未改。
- `README.md` 与本报告：使用说明与验收记录。

## 3. JSON 格式与版本

当前格式：

```json
{
  "format": "com.yexiaonan.selno.backup",
  "schemaVersion": 1,
  "exportedAt": "2026-10-21T09:30:00.000Z",
  "appVersion": "1.0 (1)",
  "timeZone": "Asia/Shanghai",
  "data": {
    "projects": [],
    "tags": [],
    "templates": [],
    "tasks": [],
    "events": [],
    "reminders": []
  }
}
```

`data` 中的实体：

- `projects`：`id`、`name`、`notes`、`createdAt`、`updatedAt`、`archivedAt?`。
- `tags`：`id`、`name`、`symbolName`、`colorHex`、`sortOrder`、`isArchived`、`createdAt`、`emoji`。
- `templates`：`id`、`name`、`emoji`、`revision`、`createdAt`、`updatedAt`、`definition?`、`definitionRawBase64?`。
- `tasks`：`id`、`title`、`notes`、`status`、`importance`、`createdAt`、`updatedAt`、`completedAt?`、`plannedStartAt?`、`plannedAt?`、`dueAt?`、`archivedAt?`、`projectID?`、`categoryID?`、`tagIDs`、`steps`、`templateInstance?`、`milestones`。
- `steps`：`id`、`title`、`isCompleted`、`sortOrder`、`createdAt`、`completedAt?`。
- `templateInstance`：`id`、`templateID?`、`templateName`、`templateRevision`、`payload?`、`payloadRawBase64?`。
- `milestones`：`id`、`fieldID`、`title`、`semantic`、`date`、`isOnCalendar`、`reminderLeadMinutes?`。
- `events`：`id`、`title`、`notes`、`startsAt`、`endsAt`、`isAllDay`、`location?`、`createdAt`、`updatedAt`。
- `reminders`：`id`、`taskID`、`kind`（`due`／`scheduled`）、`leadMinutes`、`scheduledAt?`、`createdAt`、`updatedAt`。

日期统一为 ISO 8601 UTC；读取接受带小数秒和不带小数秒两种表示。提醒的运行时状态、延后时间和系统授权状态不写入备份，导入后以 `pending` 重新协调，由系统权限与当前时间决定最终状态，避免把过期或机器相关的状态带到另一台 Mac。

版本策略：只接受 `format == "com.yexiaonan.selno.backup"` 且 `schemaVersion == 1`。更高版本明确拒绝，不猜测、不降级写入。新增可选字段或集合保持向后兼容；改变字段含义时必须提升版本并提供迁移。

## 4. Schema V4 与迁移

当前 Schema 为 **V4**：

- `TodoTask` 新增可选 `archivedAt`，用于归档而不删除数据，并让日历、总览与日常列表排除已归档任务。
- 新增 `TaskReminder` 实体，保存任务 UUID、类型、提前量、指定时间、延后时间、状态与创建／更新时间；通过 UUID 关联任务，不使用 SwiftData 关系，便于替换导入与删除清理。
- Phase 03 的完整 V3 定义冻结在 `SelnoSchemaV3Models.swift`。
- 迁移链：V1 → V2 lightweight → V3 custom → V4 lightweight。V4 只增加可选属性和新实体，不重建已有表、不删除旧字段。
- 迁移测试使用冻结 V3 定义创建真实磁盘库，写入项目、标签、任务、模板、快照、节点和提醒前数据，再以 V4 容器打开：ID、关系、日期、节点与模板快照保持不变，可新增 `TaskReminder`，关闭重开仍存在。
- 同一测试继续把迁移后的 V4 库导出为 JSON，再导入干净的 V4 磁盘库并重开，验证迁移数据可完整恢复。

## 5. 实际测试与构建结果

### 单元测试

最终运行：**87 个测试，14 个 Suite，全部通过，0 失败**（测试执行 5.200 秒）。在该最终运行后检查正式备份目录，新增文件数为 0。

| Suite | 覆盖重点 |
| --- | --- |
| `Phase04BackupTests`（14） | 文件名；导出不改数据；空库；多项目／多模板与任务归属；磁盘导出 → JSON → 干净磁盘导入 → 重开；合并幂等与冲突；子项冲突整任务跳过；替换安全备份可恢复；替换注入失败后重开仍是原状态；未来版本拒绝；非法关系／日期／重复 ID；旧 JSON 缺可选集合；未来模板字节保留；时区无关日期 |
| `Phase04MigrationTests`（2） | 冻结 V3 磁盘库迁移 V4；迁移后导出并恢复到干净 V4 库 |
| `Phase04ReminderTests`（10） | 生命周期、延后、跨午夜安静时段、权限变化、重复／孤儿、失败重试、错过过期、服务层提醒卫生、导入幂等、节点与任务标识 |
| `Phase04TaskWorkflowTests`（7） | 搜索、归档状态、列表范围、排序、批量事务、删除快照恢复、撤销中心 |
| 既有 Phase 01–03 测试 | 创建、编辑、状态、项目、标签、模板、迁移、日期与通知回归 |

说明：一次 17:00 后的运行中，既有 `multipleNodesRetainMeaningAndDoNotBecomeDeadlinesOrEvents` 因「当前时间 + 7 小时」跨过本地午夜而得到同日 4 个节点。该测试已改为固定在当天 09:00 构造节点，随后全量复跑通过；产品代码未因此修改。

### UI 测试

最终运行：**16 次测试执行全部通过，0 失败**（579.027 秒；15 个测试方法：3 Dashboard + 3 Calendar + 4 Phase03 + 3 Selno + 1 Launch × 两种外观 + 1 Phase04 数据管理）。备份目录隔离修改前后各跑过一次全量，均为 16/16。

新增 `testExportThenReplaceImportAcrossRelaunch` 是最终验收标准的端到端验证：

1. 在空白的 UI 测试专属存储中创建「导出验收任务」。
2. 打开设置 → 数据管理 → 导出 JSON，操作系统原生保存面板，回到临时目录并确认。
3. 校验文件格式标识、Schema 版本 1 和任务数量。
4. 关闭设置，再创建「替换后应消失的任务」。
5. 重新打开数据管理 → 选择备份，操作系统原生打开面板，预览中选择「替换恢复」并确认破坏性操作。
6. 回到收件箱：导出时那条任务存在，导出后新增的那条消失。
7. 终止并重新启动应用，复用同一 UI 测试存储，确认恢复的任务仍在、后加的任务仍不存在。

该测试实际走通原生 `NSSavePanel` / `NSOpenPanel`、预览、替换确认、真实磁盘写入与重启后的真实 SwiftData 读取，不是仅做 JSON 编解码断言。

### 真实持久化验证

- 磁盘 V4 库导出 → 写入 JSON 文件 → 干净磁盘 V4 库导入 → 重新打开容器：任务、项目、标签、模板、快照、节点、日程与提醒关系全部一致。
- 替换流程在全部修改完成后、唯一 `save()` 之前注入错误：`rollback()` 后重新打开磁盘库，仍是导入前的完整数据；安全备份文件存在且可再次导入。
- 冻结 V3 磁盘库 → V4 迁移 → 重开 → 导出 → 干净 V4 导入 → 重开：数据保留。
- 合并重复执行两次，第二次新增为 0，记录数不变；冲突保留本地内容；子项 ID 冲突不产生混合任务。

### 构建与运行

- Debug 与 Release 均构建成功；Release 产物为 `x86_64 arm64` 通用架构，adhoc 签名校验通过。
- 实际启动最终 Release 应用：进程存活，主窗口 1280×820、位置 (256,128)、标题「总览」；通过 Apple Event 正常退出，没有新的崩溃报告，也没有遗留系统崩溃对话框。
- `git diff --check` 通过，没有空白错误。
- 本轮运行使用 `DEVELOPER_DIR=<Xcode.app>/Contents/Developer`，没有改变系统默认开发者目录。

### 过程中修复的问题

- 早期开发崩溃遗留的系统「Selno 意外退出」对话框由 `com.apple.UserNotificationCenter` 持有，会遮挡后续 UI 测试。确认没有对应新崩溃报告后关闭该系统代理，并让测试辅助在代理未运行时不再查询其元素。
- 原生文件面板的自动化需要等待面板真正出现后再发送「前往文件夹」；导出完成后的确认弹窗会拦截紧接着的导入点击，测试现在显式关闭该弹窗后再继续。
- 替换导入最初测试设计把两条任务都写进了导出文件，导致「应消失」断言不成立；改为在导出后再创建第二条任务，才真正验证替换删除。
- 替换流程的安全备份在测试中默认落到了正式的 `Application Support/Selno/Backups`。现在 UI 测试写入专属存储旁的 `UITests/<ID>/Backups`，单元测试默认写入一次性临时目录；最终单元运行后正式目录新增为 0。
- 上述修复都在测试或测试辅助中完成，没有为通过测试而改变产品导入语义。产品侧唯一的配套调整是：Debug 的 `--selno-ui-testing` 启动参数会把自动备份目录指向测试库旁；Release 与正常 Debug 启动仍使用正式的 `Application Support/Selno/Backups`。

## 6. 未完成事项与风险

- **系统通知投递无法完全自动化。** 单元测试通过可注入网关验证调度、更新、取消、延后、权限和重复防护；真实横幅是否显示仍取决于本机通知授权与系统设置。实际通知到达需要在目标 Mac 上人工确认。
- **应用未运行时的行为。** 已经交给系统的 `UNCalendarNotificationTrigger` 仍由 macOS 投递，但应用内的核对、安静时段顺延后的状态刷新和恢复不会执行；下次启动才重新协调。已错过的提醒不会补发，这是刻意的防重复策略。
- **安静时段是顺延而非丢弃。** 窗口内到期的提醒会移动到窗口结束；如果用户期望完全静音，需要在系统专注模式中另行配置。
- **合并冲突始终保留本地。** 本轮没有逐字段「以备份覆盖」选项；需要覆盖时应使用替换恢复。替换会删除现有本地数据，只能依靠自动安全备份回退。
- **替换的安全备份依赖磁盘可写。** 安全备份写入失败会中止替换；这是有意的保护，但用户需要确保 Application Support 所在磁盘有空间。读取导入文件上限为 128 MB。
- **提醒的延后与运行状态不进入 JSON。** 这是为了让备份可跨机器使用；代价是恢复后不能保留某条提醒的临时延后状态。
- **UI 测试依赖本机原生面板与中文界面。** 在无辅助功能权限、系统语言不同或面板结构变化的机器上可能需要调整定位；本轮在本机实际通过。
- **项目锁定为本地单机。** 没有 CloudKit、账户、网络同步或第三方备份框架；JSON 文件由用户自行保管。

## 7. 工作区与数据保护

- 未执行 `git reset`、`git checkout --`、`git clean`；没有 Commit 或 Push。
- 未删除或重建正式 `Selno/Selno.store`；未执行破坏性迁移。所有迁移测试只操作各自临时目录，V3 冻结库由测试代码生成。
- 导出路径只读取业务数据；导出前后快照一致由测试覆盖。
- 替换恢复在删除前写入独立安全备份；失败回滚并在重开后验证。
- 测试使用独立内存库、临时磁盘库或 `SELNO_UI_TEST_STORE_ID` 指定的 UI 测试库；正式用户数据没有被清空。UI 测试替换导入产生的自动安全备份也写入测试库旁的 `Selno/UITests/<ID>/Backups`，不会混入正式的自动备份目录。
- 修复前遗留在正式自动备份目录的 46 个文件均已逐条解析，确认全部来自固定日期的单元测试或本轮 UI 测试任务（不含真实用户备份）；先归档到 `.build/phase04/removed-test-backups-20261021.tar.gz`，再清理。该目录现在为空。
- 未引入第三方备份、数据库或通知框架；只使用系统 SwiftUI、SwiftData、AppKit 与 UserNotifications。