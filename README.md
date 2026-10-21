# Selno · 序宁

让每一件事，都有条不紊。

Selno 使用 SwiftUI 与 SwiftData 构建本地 macOS 任务和日程管理应用。最低系统 macOS 15.0，Release 使用 `arm64`、`x86_64` 通用架构，Bundle Identifier 为 `com.yexiaonan.Selno`。不需要账户、后端或网络，不启用 CloudKit。

## Phase 03：Quiet Structure

总览品牌标题按「输入 → 阅读 → 删除 → 下一句」循环八句文案，以 Swift `Character` 处理 Emoji 和组合字符。标题保持固定高度；离开总览、窗口失去焦点或不可见时停止任务，返回后从原状态继续。Reduce Motion 和 VoiceOver 下显示完整静态句子。

`SelnoDesign` 提供深浅自适应的背景、表面、文字、边界、鼠尾草强调色及状态色。总览保留今日聚焦的主要表面，其他模块使用排版与弱分隔组织信息。按钮、标签、任务行、日期选中和详情使用共享组件，并尊重减少动态效果。

侧边栏底部「设置」及系统设置菜单包含「任务模板」「标签」两个页面。

- 标签复用 `TaskCategory`，支持多选、Emoji、八组预设颜色、编辑、删除和列表筛选。旧名称、颜色和分类关联保留，旧标签 Emoji 默认为空。任务行显示两个 Chip 和溢出数量，详情可显示更多。
- 模板支持创建、编辑、复制、删除及从任务保存；普通任务、校园二课活动、课程作业、比赛报名为首次初始化的可编辑预设。删除预设后不会重新生成。
- 从任务编辑器或收件箱的「从模板创建」进入动态表单。支持文本、多行文本、URL、可选日期时间、分组、顺序、显示隐藏、默认标签和重要性。模板名称与任务标题独立。
- 校园二课预设包含十二个字段，区分报名开始、报名截止、活动开始、活动结束、材料提交截止。节点单独勾选后才显示在日历，或建立本地通知；不会改写 `dueAt`，也不会生成独立 `CalendarEvent` 副本。
- 任务详情可查看创建时的字段快照和时间节点。修改或删除原模板不改变已有任务。无法读取的未来版本记录保留原始字节，普通任务信息仍可编辑。

模板定义与实例使用版本化 Codable 数据及稳定字段 UUID；日期节点使用独立稳定 UUID 管理日历展示和提醒。通知仅在用户明确选择节点提醒时请求授权，同一节点的修改替换原请求，完成、取消、移除节点或删除任务会清理待发送请求。实际系统通知的授权和横幅显示需在目标机器验证。

## Phase 04：可靠日常使用

### 数据管理

「设置 → 数据管理」提供完整的 JSON 导出与导入，不增加侧边栏入口。

- 「导出 JSON…」使用原生保存面板，默认文件名为 `Selno-Backup-YYYY-MM-DD.json`。导出包含全部任务及其状态、重要性、日期、子任务、项目、旧分类与多标签、模板、任务上的模板快照、时间节点、独立日程和任务提醒配置；使用稳定 UUID 与关系，日期为 ISO 8601 UTC。导出只读取，不修改任何业务数据。
- 「选择备份文件…」使用原生打开面板。文件会先完整解码和校验，再显示文件记录数与本地现状。校验失败不会写入任何内容。
- **合并导入**按稳定 UUID 匹配：已存在的记录保留本地版本，只补充新记录，并报告新增与跳过数量；重复导入同一文件是幂等的。任务、项目、标签、模板、日程或任务子项发生 ID 冲突时不会拼接出混合记录。
- **替换恢复**先自动写入 `Selno-PreRestore-<时间戳>.json` 到 `Application Support/Selno/Backups`，再替换全部本地数据；写入安全备份失败时不会开始。替换在单个事务中完成，失败会回滚并保留原数据。
- 导入完成后，列表、详情与提醒立即按新数据刷新；同一任务同一类型只登记一条系统通知。
- 格式标识为 `com.yexiaonan.selno.backup`。Phase 04 的 `schemaVersion` 为 1；Phase 05 起导出为 2，并继续读取 1。未来版本会被拒绝，不会猜测或降级写入；缺失的可选集合与字段使用安全默认值，无法识别的未来模板字节原样保留。

### 通知与提醒

任务可在任务编辑器设置「截止前提醒」（7 天／3 天／1 天或自定义分钟）和「指定时间提醒」。提醒使用系统通知中心与日历触发器，不轮询。

- 通知提供「查看任务」「10 分钟后提醒」「1 小时后提醒」。任务完成、取消、归档或删除会移除待发送通知；修改日期会更新；同一标识只保留一条请求。
- 启动、窗口激活、保存后会自动协调，也可在「设置 → 提醒」手动「立即重新核对」。任务详情显示待发送、已延后、已过期、权限阻止等真实状态。
- 可配置安静时段（支持跨午夜）：落入窗口的提醒顺延到窗口结束，已经过去的提醒不会复活。
- 提醒只能在应用已经运行或保存后交给系统；Selno 未运行、系统休眠或没有通知权限时不会执行应用内核对。已错过的提醒不会补发，避免重复打扰。模板时间节点与任务提醒共用同一通知通道。

### 高频操作

- 收件箱与全部任务支持搜索（标题、备注、项目、标签、旧分类）以及状态、项目、标签筛选和排序。
- 列表支持多选，可批量完成、添加标签、移动项目、归档和执行删除。批量修改在单个事务中保存，失败回滚。
- 删除需要确认，并在窗口底部提供 12 秒撤销；撤销按删除快照恢复原 ID、关系、子任务、节点与提醒。
- 新建任务后会清除可能隐藏它的筛选条件，短暂高亮对应行并显示提示；替换导入会清理失效的选择和撤销状态。

## Phase 05：自适应工作台

Phase 05 将「总览」升级为可自定义的全局工作台，并在同一份本地数据之上增加场景工作台。工作台只保存名称、Emoji、强调色、顺序、默认筛选与模块布局，不复制任何任务、项目、标签、日程或模板。侧边栏原有的总览、日历、今天、收件箱、全部任务、项目保持不变，「总览」就是全局工作台，不重复新增入口。

- 首次启动只创建一个全局工作台，使用默认布局；重复启动不会重复创建。全局工作台可以改名、改色、重排和恢复默认布局，但不能删除。
- 场景可从空白、校园、开发、生活或复制现有工作台创建；最多 24 个工作台、每个最多 48 个模块。删除场景只删除该场景的布局与筛选，业务记录不受影响。
- 八个内置模块：今日聚焦、近期安排（3／7 天）、紧凑月历、收件箱、项目进度、任务列表、任务统计、快捷操作。模块目录按聚焦、任务与项目、日历、快捷操作分组，不连接网络或插件市场。
- 正常浏览不显示编辑控件。进入自定义模式后可拖动排序、调整尺寸、配置筛选、移除或添加模块；草稿只存在于内存，点「完成」时一次性保存，取消丢弃，保存失败回滚并保留草稿。模块拖拽使用独立 JSON 载荷，侧栏工作台拖拽使用独立 XML 载荷，与日历任务改期的纯文本拖拽互不影响；侧栏行本身保持普通点击切换，只有尾部握柄可拖动排序。
- 布局由确定性的行列装箱算法计算，断点为 840 与 1180 点，最多三列；模块按逻辑顺序排列，窄窗口自动收为整行，不使用绝对像素坐标。未知的模块类型与原始配置字节会保留为占位模块，不会被静默丢弃。
- 任务筛选支持状态、重要性、项目、标签、日期范围、截止状态、计划状态、归档与搜索；同一维度内取「或」，维度之间取「且」。日期使用当前 Calendar 与 TimeZone 的本地午夜，不截取 UTC 字符串。
- 模块数据范围有「继承场景」「全局数据」「自定义筛选」三种：自定义规则整体替代场景规则，不叠加；已保存的任务视图是完整规则集，选中后模块固定为自定义范围。页面显示筛选来源。
- 工作台查询按整块板合并可见日期窗口并限制在回溯 180 天、前瞻 365 天、最长 550 天内；一次板级查询供所有模块复用，不为每个模块单独查询数据库。
- JSON 备份升级为 v2，新增工作台、模块布局、任务视图与筛选规则；v1 文件仍可导入并在缺少全局工作台时补建一个。合并按 UUID 幂等，替换恢复先写安全备份，未知未来模块与非法引用在写入前校验。
- V5 Schema 只新增 `Workspace`、`WorkspaceModule`、`SavedTaskView`，历史 V1–V4 模型未原地修改；V4 → V5 为轻量迁移，默认全局工作台在迁移完成后的启动流程中幂等写入。

## 运行与导航

用 Xcode 打开 `Selno.xcodeproj`，选择共享 Scheme **Selno** 和 **My Mac** 运行。

应用默认进入全局工作台，左侧依次提供总览、日历、今天、收件箱、全部任务、项目六个固定入口，以及用户创建的场景工作台。原有 `ContentView.swift` 的用户修改及模板 `Item.swift` 原样保留，但正式入口不使用模板，旧模板存储也不会被删除或覆盖。

- 总览即全局工作台，聚合今日聚焦、未来 3／7 天安排、紧凑月历、收件箱快照和项目进度；所有内容来自真实 SwiftData 查询。可直接完成任务、快速记下想法，或创建今天的任务与日程。
- 总览月历中的日期可直接打开完整日历，并同步选中日期和当日安排；系统悬停提示显示真实摘要。
- 今天页独立展示全部待办和按时间排列的日程，支持完成、查看与新增，复用总览的去重和优先级逻辑。
- 项目页支持创建、编辑名称与备注、查看进度与逾期情况、添加项目任务、完成任务和查看任务详情。
- 日历提供月、周和列表模式，以及前后范围、年份、日期定位和返回今天。
- 点击日期更新同一窗口内的当日安排面板；面板可收起，通过日期或顶部按钮重新展开。
- 悬停日期约 350 毫秒显示真实数据摘要，移出关闭。摘要最多展示四项并显示剩余数量，浮层不接收鼠标点击。
- 当日安排中的“新建”菜单区分任务与日程。新任务默认计划在选定日期，不自动添加截止日期；日程支持时间、全天、地点与备注。
- 点击安排可查看详情并编辑；任务可完成或恢复，日程没有任务完成状态。删除日程需要确认。
- 将日历中的任务条目拖到其他日期可调整计划执行日，保留原计划时间；不会修改最终截止日期、完成状态或计划开始日期，改期会立即保存。工作台编辑模式使用独立的手柄拖拽，只在草稿内重排，不会与日历任务拖拽共用状态。
- 收件箱和全部任务继续支持输入标题并回车创建，任务状态分组、详情与编辑。“今天”同时显示当天日程以及今天计划、今天截止和已逾期的待办。

## 日期与数据约定

`TodoTask.plannedAt` 表示计划执行，`plannedStartAt` 表示计划开始，`dueAt` 表示最终截止。日历分别保留这些含义：跨日期可以出现多次，同一天合并为一个任务项并保留所有日期角色。无日期任务不会被随意放入日历。收件箱定义保持为没有项目、计划开始及计划执行日期；只设置截止日期仍可属于收件箱。

`CalendarEvent` 独立存储 UUID、标题、备注、开始和结束时间、全天标记、地点、创建和更新时间，不强行使用 TODO 状态。所有分组使用同一个当前 Calendar 与 TimeZone，按本地日历递增日期，避免用固定 24 小时或截取 UTC 字符串判断日期。

时间区间使用半开语义 `[startsAt, endsAt)`：跨午夜事件按与日期区间实际相交的天展示，午夜结束不会多算次日。零时长定时日程归入开始时间所在日。全天表单的结束日期包含当天，保存时转换为该结束日期次日的本地午夜；再次编辑会反向转换，不会每次保存都延长一天。定时日程结束不能早于开始。

正式文件位于应用沙盒 Application Support 下的 `Selno/Selno.store`。主 context 关闭自动保存，由 Service 明确保存；失败时回滚并显示错误。启动失败提供错误信息与重试，保留原数据库。

## 日历模块

| 模块 | 职责 |
| --- | --- |
| `App/MainWindowView.swift`、`AppSection.swift` | 原生分栏导航；仅在任务工作区加载完整任务列表 |
| `Features/Calendar/CalendarWorkspace.swift` | 日期、模式、可见窗口和面板状态 |
| `CalendarMath.swift` | 月网格、周、列表范围、日历导航与显示日期 |
| `CalendarDataQuery.swift`、`CalendarRangeContent.swift` | 按可见日期范围执行 SwiftData 查询和数据变化刷新 |
| `CalendarAgenda.swift` | 按天汇总、任务去重、日期角色与事件区间相交 |
| `CalendarGridView.swift`、`CalendarListView.swift` | 可操作的日期格、周摘要与按天列表 |
| `CalendarTaskDrag.swift` | AppKit 任务条目鼠标跟踪、原生拖放与带前缀 UUID 校验 |
| `CalendarHoverTip.swift`、`DayAgendaView.swift`、`AgendaRows.swift` | 共享每日汇总驱动的悬停、当日面板与详情入口 |
| `CalendarEventEditorView.swift`、`CalendarEventDetailView.swift` | 日程创建、查看、编辑和确认删除 |
| `Models/CalendarEvent.swift`、`Services/CalendarEventService.swift` | 日程模型、校验和显式持久化 |
| `Features/Tasks/TaskWorkspaceView.swift` | 保留收件箱及全部任务的列表、详情、快捷创建和编辑 |

## 总览与项目

`DashboardWorkspace.swift` 继续承载「今天」页的完整任务与日程；「总览」已由 `WorkspaceBoardView.swift` 的全局工作台取代。两者复用 `DashboardProjection` 与日历汇总逻辑，灰白语义色自动适配深浅模式，并跨本地午夜重新查询。

`DashboardProjection.swift` 独立组织今日聚焦和近期摘要：任务按 UUID 去重，依次关注逾期、今天截止、重要性；未来摘要只呈现每件事下一次承诺，保留同一天的日期角色，并排除已在今日聚焦出现的任务和日程。跨日日程在近期摘要首次相交的日期展示一次；完整日历依然按每个相交日期展示。近期摘要有限的行数会显示其余数量和当天详情入口。

当前月和未来七天使用有界日期查询，额外查询仍未完成的逾期待办；不会加载多年已完成任务。收件箱快照查询限制四条，用 `fetchCount` 读取完整待整理数量；数量在明确保存后刷新。项目摘要展示最近更新的三个未归档项目，统计其真实任务关系，全部项目可在独立页面查看。

`ProjectService.swift` 校验项目名称、明确保存并在失败时回滚。项目任务通过现有 `TaskService` 创建并原子保存关系。Phase 02.5 不改动任何 SwiftData 实体字段、关系或 Schema 版本。

## 工作台模块

| 模块 | 职责 |
| --- | --- |
| `Features/Workspace/WorkspaceBoardView.swift` | 全局与场景工作台的浏览态、编辑态、草稿保存与模块布局 |
| `WorkspaceDataQuery.swift` | 板级查询计划、日期窗口合并、筛选解析、任务／统计／收件箱数据 |
| `WorkspaceLayoutEngine.swift` | 断点、列数、跨度、行装箱与稳定宽度计算 |
| `WorkspaceModuleRegistry.swift`、`WorkspaceModuleCatalog.swift` | 八个内置模块、支持尺寸、模块目录与模块配置 |
| `WorkspaceModuleViews.swift` | 各模块的真实数据呈现、完成／打开／快捷创建 |
| `WorkspaceEditorViews.swift`、`TaskFilterEditor.swift` | 工作台创建与编辑、筛选规则、任务视图编辑 |
| `WorkspaceDragTypes.swift` | 模块与侧栏工作台的独立拖拽类型、载荷与 UUID 校验 |
| `Models/Workspace.swift`、`WorkspaceEnums.swift` | 工作台、模块、任务视图模型与快照；尺寸、范围、上限 |
| `Models/TaskFilterExpression.swift` | 可序列化筛选规则、确定性 Codable、匹配与范围解析 |
| `Services/WorkspaceService.swift` | 工作台／模块／任务视图的校验、事务保存、回滚与种子 |
| `App/WorkspaceSidebarView.swift` | 侧边栏场景列表、创建、复制、重排、重命名与删除 |

## 应用图标

`Tools/GenerateAppIcon.swift` 使用 CoreGraphics 矢量路径绘制暖白圆角底与石墨灰 S 曲线，逐尺寸渲染 macOS 十个资源槽位；小图直接从矢量超采样，无低分辨率放大。

保留 `Branding/SelnoIcon-master-4096.png` 原稿、`Branding/SelnoIcon-1024.png` 主图，以及 `Selno/Assets.xcassets/AppIcon.appiconset` 中的资源。Target 的 Debug 与 Release 都使用已有的 `AppIcon` 设置。修改绘图路径后，在项目根目录运行 `xcrun swift Tools/GenerateAppIcon.swift` 即可重新生成。

日历每次只查询当前月网格、七天周或所选列表范围内相关任务，以及与范围相交的事件。日期分组在查询数据变化后更新；日期点击和悬停复用已分组的数据，不为每个格子单独查询数据库。

## Schema 与迁移

Phase 01 的五种持久化类型已冻结在 `Persistence/SelnoSchemaV1Models.swift`。Phase 02 的六种类型冻结在 `Persistence/SelnoSchemaV2Models.swift`。Phase 03 的 V3 增加 `TaskTemplate`、`TaskTemplateInstance`、`TaskMilestone`，并为 `TodoTask` 增加多标签、模板实例和节点关系，为 `TaskCategory` 增加 Emoji 与多标签反向关系；完整 V3 定义已冻结在 `Persistence/SelnoSchemaV3Models.swift`。

V4 为 `TodoTask` 增加可选 `archivedAt`，并新增 `TaskReminder`（任务 UUID、类型、提前量、指定时间、延后时间与状态）。V5 新增 `Workspace`、`WorkspaceModule` 与 `SavedTaskView`，没有修改历史业务字段；迁移链为 V1 → V2 lightweight、V2 → V3 custom migration、V3 → V4 lightweight、V4 → V5 lightweight。旧分类关系继续保留；模板删除不关联删除任务，任务删除会级联清理自身实例与节点。各升级路径均有独立磁盘测试，迁移后的 V4 库还会再执行一次导出与干净库恢复验证；Phase 05 另有 V4 → V5 磁盘迁移、重复启动与 V2 备份往返测试。

迁移测试使用修改前 Phase 01 源码实际生成的 `SelnoTests/Fixtures/Phase01.store`，包含固定 UUID 的已完成任务、日期字段、项目、分类和子任务关联。`Phase01Fixture.swift` 内嵌其压缩字节，解压后验证 SHA-256 再写入测试自己的临时目录，避免测试宿主向用户请求桌面目录权限。测试只修改临时副本，并验证迁移后所有数据保留、能新增日程、重新打开仍存在。

项目与分类删除使用 nullify，保留任务；任务对子任务使用 cascade。默认分类继续通过固定 UUID 和数据库内 `SeedRecord` 幂等初始化。不使用删除数据库、清理记录或关闭持久化来处理升级问题。

后续修改已发布的持久化字段前，应冻结完整的 V3 定义，再增加新版本及迁移测试，不能原地修改历史 schema。

## 构建与测试

```sh
xcodebuild build-for-testing -project Selno.xcodeproj -scheme Selno \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData

xcodebuild test-without-building -project Selno.xcodeproj -scheme Selno \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData

xcodebuild build -project Selno.xcodeproj -scheme Selno \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath .build/ReleaseDerivedData
```

如果终端只选择了 Command Line Tools，在命令前设置 `DEVELOPER_DIR` 为完整 Xcode 的 `Contents/Developer` 即可，无需更改系统设置。

共享 Scheme 为单元测试宿主设置 `SELNO_TESTING=1`，Debug 下使用内存库。每个数据测试再建立独立容器；磁盘及迁移测试使用临时目录。UI 测试通过 `--selno-ui-testing` 和随机 `SELNO_UI_TEST_STORE_ID` 使用专属磁盘文件，同一案例重启 App 时复用该文件，避免污染正式数据；替换导入的自动安全备份同样写入该测试库旁的 `UITests/<ID>/Backups`。测试存储选择只在 Debug 中启用。

Desktop 文件提供程序可能向生成的 `.app`、`.xctest` 或 `.framework` 写回 `com.apple.FinderInfo`，从而干扰签名。仅清理 `.build` 产物的对应扩展属性并重试；不要清理用户数据库、修改团队或禁用工程签名。参见 [Apple QA1940](https://developer.apple.com/library/archive/qa/qa1940/_index.html)。

历史报告见 `Docs/Phase01-Report.md`、`Docs/Phase02-Report.md`、`Docs/Phase025-Report.md`、`Docs/Phase03-Report.md`。Phase 04 的 JSON 格式、通知行为、迁移与真实持久化验证、构建与测试结果见 `Docs/Phase04-Report.md`。Phase 05 的工作台架构、V5 迁移、布局与筛选规则、构建与测试状态见 `Docs/Phase05-Report.md`。

Phase 04 测试结果：单元 87/87 通过，UI 16/16 通过（含原生保存／打开面板的导出 → 替换 → 重启验收）。Phase 05 在 2026-10-21 的最终单元测试为 136/136 通过（18 个 Suite，其中 Phase 05 49 条，布局覆盖 10／30／100 个模块）；UI 测试 20 次执行 0 失败，其中 Phase 05 4/4、既有回归 16/16。真实运行截图见 `Docs/Phase05Screenshots/`，完整结果、构建日志与遗留风险见 `Docs/Phase05-Report.md`。此外，本轮在正式库的离线副本上实际执行了 V4 → V5 迁移，业务行数与种子幂等性通过；副本含个人数据，验收后已删除，未写入仓库。
