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

## 运行与导航

用 Xcode 打开 `Selno.xcodeproj`，选择共享 Scheme **Selno** 和 **My Mac** 运行。

应用默认进入总览，左侧依次提供总览、日历、今天、收件箱、全部任务、项目六个入口。原有 `ContentView.swift` 的用户修改及模板 `Item.swift` 原样保留，但正式入口不使用模板，旧模板存储也不会被删除或覆盖。

- 总览聚合今日聚焦、未来 3／7 天安排、紧凑月历、收件箱快照和项目进度；所有内容来自真实 SwiftData 查询。可直接完成任务、快速记下想法，或创建今天的任务与日程。
- 总览月历中的日期可直接打开完整日历，并同步选中日期和当日安排；系统悬停提示显示真实摘要。
- 今天页独立展示全部待办和按时间排列的日程，支持完成、查看与新增，复用总览的去重和优先级逻辑。
- 项目页支持创建、编辑名称与备注、查看进度与逾期情况、添加项目任务、完成任务和查看任务详情。
- 日历提供月、周和列表模式，以及前后范围、年份、日期定位和返回今天。
- 点击日期更新同一窗口内的当日安排面板；面板可收起，通过日期或顶部按钮重新展开。
- 悬停日期约 350 毫秒显示真实数据摘要，移出关闭。摘要最多展示四项并显示剩余数量，浮层不接收鼠标点击。
- 当日安排中的“新建”菜单区分任务与日程。新任务默认计划在选定日期，不自动添加截止日期；日程支持时间、全天、地点与备注。
- 点击安排可查看详情并编辑；任务可完成或恢复，日程没有任务完成状态。删除日程需要确认。
- 将日历中的任务条目拖到其他日期可调整计划执行日，保留原计划时间；不会修改最终截止日期、完成状态或计划开始日期，改期会立即保存。
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

`DashboardWorkspace.swift` 根据窗口宽度组织主内容与辅助信息，灰白语义色自动适配深浅模式。总览侧重扫视与快捷操作，今天页显示完整任务和日程；两者均跨本地午夜重新查询。

`DashboardProjection.swift` 独立组织今日聚焦和近期摘要：任务按 UUID 去重，依次关注逾期、今天截止、重要性；未来摘要只呈现每件事下一次承诺，保留同一天的日期角色，并排除已在今日聚焦出现的任务和日程。跨日日程在近期摘要首次相交的日期展示一次；完整日历依然按每个相交日期展示。近期摘要有限的行数会显示其余数量和当天详情入口。

当前月和未来七天使用有界日期查询，额外查询仍未完成的逾期待办；不会加载多年已完成任务。收件箱快照查询限制四条，用 `fetchCount` 读取完整待整理数量；数量在明确保存后刷新。项目摘要展示最近更新的三个未归档项目，统计其真实任务关系，全部项目可在独立页面查看。

`ProjectService.swift` 校验项目名称、明确保存并在失败时回滚。项目任务通过现有 `TaskService` 创建并原子保存关系。Phase 02.5 不改动任何 SwiftData 实体字段、关系或 Schema 版本。

## 应用图标

`Tools/GenerateAppIcon.swift` 使用 CoreGraphics 矢量路径绘制暖白圆角底与石墨灰 S 曲线，逐尺寸渲染 macOS 十个资源槽位；小图直接从矢量超采样，无低分辨率放大。

保留 `Branding/SelnoIcon-master-4096.png` 原稿、`Branding/SelnoIcon-1024.png` 主图，以及 `Selno/Assets.xcassets/AppIcon.appiconset` 中的资源。Target 的 Debug 与 Release 都使用已有的 `AppIcon` 设置。修改绘图路径后，在项目根目录运行 `xcrun swift Tools/GenerateAppIcon.swift` 即可重新生成。

日历每次只查询当前月网格、七天周或所选列表范围内相关任务，以及与范围相交的事件。日期分组在查询数据变化后更新；日期点击和悬停复用已分组的数据，不为每个格子单独查询数据库。

## Schema 与迁移

Phase 01 的五种持久化类型已冻结在 `Persistence/SelnoSchemaV1Models.swift`。Phase 02 的六种类型冻结在 `Persistence/SelnoSchemaV2Models.swift`。当前 V3 增加 `TaskTemplate`、`TaskTemplateInstance`、`TaskMilestone`，并为 `TodoTask` 增加多标签、模板实例和节点关系，为 `TaskCategory` 增加 Emoji 与多标签反向关系。

迁移链为 V1 → V2 lightweight，再由 V2 → V3 custom migration 保留原文件并将旧分类补入多标签关系。旧分类关系继续保留；模板删除不关联删除任务，任务删除会级联清理自身实例与节点。两条升级路径均有独立磁盘测试。

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

共享 Scheme 为单元测试宿主设置 `SELNO_TESTING=1`，Debug 下使用内存库。每个数据测试再建立独立容器；磁盘及迁移测试使用临时目录。UI 测试通过 `--selno-ui-testing` 和随机 `SELNO_UI_TEST_STORE_ID` 使用专属磁盘文件，同一案例重启 App 时复用该文件，避免污染正式数据。测试存储选择只在 Debug 中启用。

Desktop 文件提供程序可能向生成的 `.app`、`.xctest` 或 `.framework` 写回 `com.apple.FinderInfo`，从而干扰签名。仅清理 `.build` 产物的对应扩展属性并重试；不要清理用户数据库、修改团队或禁用工程签名。参见 [Apple QA1940](https://developer.apple.com/library/archive/qa/qa1940/_index.html)。

历史报告见 `Docs/Phase01-Report.md`、`Docs/Phase02-Report.md`、`Docs/Phase025-Report.md`。本轮文件、架构、构建、测试、真实截图与人工验收边界见 `Docs/Phase03-Report.md`。
