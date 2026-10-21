# Selno · 序宁 — Phase 02.5 开发报告

复核日期：2026-10-21。工程根目录：`/Users/waiting/Desktop/Project/Selno`。本次只完成剩余验收、经用户授权的重复源文件编译排除及交付报告，没有重建工程或新增业务功能。

## 总览与导航

启动默认显示“总览”，导航顺序为：总览、日历、今天、收件箱、全部任务、项目。主窗口显式使用 macOS 15 的 `defaultLaunchBehavior(.presented)`，确保完全退出后重新启动会呈现窗口。保留系统窗口尺寸调整能力。

总览分成主内容与辅助信息两条浏览路径，使用系统字体、SF Symbols、语义灰白色、弱描边和原生操作控件。宽窗口中左侧是今日聚焦与近期安排，右侧是紧凑月历与收件箱，底部是项目进度；较窄窗口自动重排。无演示任务或硬编码日程。

| 模块 | 已实现内容 |
| --- | --- |
| 今日聚焦 | 今天计划、今天截止、今天开始及未完成逾期任务；同一 UUID 合并一次，标明日期含义；优先逾期、截止及重要事项；直接完成与查看详情。展示最多五条待办、两条日程，其余数量可进入今天页查看。 |
| 近期安排 | 从明天开始的 3／7 天切换；按本地日期分组，显示事件时间和任务日期角色。每件事只展示下一次安排；排除今日聚焦中已出现的事项；更多内容可进入当天日历。 |
| 日历概览 | 当前系统月份网格，今天强调、补位日期弱化、任务圆点与事件短线标记；悬停显示真实摘要；日期点击打开完整日历并选中对应日期。 |
| 收件箱快照 | 前四项活跃待整理任务、完整数量、真实快速输入回车保存、查看任务与进入收件箱。沿用原收件箱语义，只有截止日期的任务仍可在收件箱内。 |
| 项目进度 | 最近更新的三个未归档项目，显示名称、总数、完成数、进度与逾期数；点击进入项目详情；无数据时可创建真实项目。 |

项目页支持创建与编辑名称／备注、查看实际进度和任务、快速添加项目任务、完成／恢复任务、查看及编辑任务详情。已有归档项目可查看；本轮没有扩展高级项目工作流。

## 今天与日历 UI

今天页使用与总览一致的聚合规则，完整展示“需要完成”和“按时发生”两个区块。宽窗口分列、窄窗口纵向组织，可直接完成、查看、新增；没有始终占据右侧的大型空详情区。

日历保留原日期计算、查询、任务日期角色、悬停锚点、拖放实现、三种视图和右侧面板。优化月份标题层级、工具栏留白、四点网格间距、柔和圆角日期格、精细选中描边以及当日安排的背景与分隔。任务拖放继续使用原 AppKit 跟踪和 SwiftData 保存，不改最终截止日期。

## 模块与复用

| 文件 | 职责 |
| --- | --- |
| `Selno/App/AppSection.swift`、`MainWindowView.swift`、`SelnoApp.swift` | 六项导航、默认总览、日期与项目跳转、启动窗口呈现 |
| `Selno/Features/Dashboard/DashboardWorkspace.swift` | 总览及今天页、有限行数摘要、快捷创建、月历导航和响应式布局 |
| `Selno/Features/Dashboard/DashboardProjection.swift` | 今日优先级、UUID 去重、未来安排、项目统计 |
| `Selno/Features/Dashboard/DashboardDataQuery.swift` | 活跃逾期、收件箱快照与计数、未归档项目查询 |
| `Selno/Shared/Components/WorkspaceStyle.swift` | 原生语义表面、模块标题、紧凑空状态、任务与项目展示 |
| `Selno/Features/Projects/ProjectWorkspace.swift`、`Services/ProjectService.swift` | 基础项目概览、详情、创建编辑及明确保存 |
| `Selno/Services/TaskService.swift` | 复用原创建逻辑，新增可选项目关系；不改变默认收件箱创建行为 |
| `Selno/Features/Calendar/CalendarWorkspace.swift`、`CalendarGridView.swift`、`CalendarRangeContent.swift`、`DayAgendaView.swift` | 日期跳转入口及视觉整理；保留原交互 |
| `SelnoTests/DashboardTests.swift`、`SelnoUITests/DashboardUITests.swift` | 聚合与数据验证、真实表单交互、导航、重启、项目及窗口测试 |
| `SelnoUITests/CalendarUITests.swift`、`SelnoUITestsLaunchTests.swift` | 调整日历测试的导航入口、验证默认总览及深浅启动 |
| `Selno.xcodeproj/project.pbxproj` | 经用户授权，将重复副本 `Features/Calendar/AgendaRows 2.swift` 排除出 Selno Target；保留文件及其 Git 暂存状态 |

复用 `TodayTaskFilter`、`CalendarMath`、`CalendarAgendaBuilder`、`CalendarDataQuery`、`TaskService`、`CalendarEventService`，以及既有任务／事件编辑和详情界面。日期始终使用同一 Calendar 与 TimeZone；不使用固定 24 小时步长划分本地日期。

日期范围查询覆盖当前月网格与未来七天，额外取仍活跃的逾期待办；聚合前按 UUID 合并交集。收件箱查询限制四条，数量由 `fetchCount` 单独读取并在保存后刷新。日历和总览的日期摘要缓存仅在查询结果变化时重建。

没有更改模型、V1／V2 Schema、迁移计划、存储路径、Bundle Identifier 或签名设置。没有删除用户数据，没有第三方依赖，也没有 Commit／Push。

## 图标设计与资源

暖白底板、细微明暗层次、石墨灰连续 S 曲线。横向肩部与圆角转折表达秩序和从容；使用留白保持小尺寸辨识。没有文字、日期数字、勾选框、蓝紫渐变或多色装饰。

- 矢量绘制源码：[GenerateAppIcon.swift](/Users/waiting/Desktop/Project/Selno/Tools/GenerateAppIcon.swift)。
- 高分辨率原稿：[SelnoIcon-master-4096.png](/Users/waiting/Desktop/Project/Selno/Branding/SelnoIcon-master-4096.png)，4096 × 4096。
- 正式主图：[SelnoIcon-1024.png](/Users/waiting/Desktop/Project/Selno/Branding/SelnoIcon-1024.png)，1024 × 1024。
- 工程资源：[AppIcon Contents.json](/Users/waiting/Desktop/Project/Selno/Selno/Assets.xcassets/AppIcon.appiconset/Contents.json) 及同目录十张 PNG。
- 16、32、128、256、512 pt 各有 1x／2x，最大资源为 1024 px。每个尺寸从矢量独立渲染，小尺寸超采样后缩小，未放大低清位图。

原 Target 的 Debug 和 Release 已指定 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`，继续复用。编译产物的 Info.plist 指向 `AppIcon`；`AppIcon.icns` 与 `Assets.car` 同时打包。Asset Catalog 中含十个 Icon Image rendition，覆盖 16–1024 px；icns 的兼容表示与 Assets.car 的高清表示共同提供系统图标。

## 实际编译、测试与图标显示验证

### 当前工程复核

当前工作区保留了前几阶段的未提交和未跟踪文件，不能把整个 `git status` 都归为本次新修改。本次通过文件哈希对比确认，只修改了 `Selno.xcodeproj/project.pbxproj` 与本报告；业务源码、模型、原有用户修改和 Git 暂存内容保持不变。

复核时发现已暂存的 `AgendaRows 2.swift` 与 `AgendaRows.swift` 字节完全相同，但不在上次成功编译清单内。对当前工程实际执行增量编译后，确认它造成 `AgendaSelection`、`AgendaDetailsSheet`、`CalendarTaskAgendaRow` 和 `CalendarEventAgendaRow` 重复声明。

经用户明确授权，通过文件系统同步组的 `PBXFileSystemSynchronizedBuildFileExceptionSet` 仅排除此副本的 Selno Target 成员关系。没有删除、重命名、改写或取消暂存该文件。副本的暂存 blob 仍为 `cf89342f2795e102b29ec95d783777c98cc146ef`。排除后，当前 App 编译源码清单与上次完整测试时完全一致。

| 本次实际检查 | 结果 |
| --- | --- |
| 当前工程文件语法、`git diff --check` | 通过 |
| 真实 Selno Scheme，Debug `build-for-testing`，x86_64 | 通过 |
| 真实 Selno Scheme，Release `build`，generic macOS | 通过；包含 x86_64、arm64 |
| 两个构建产物 `codesign --verify --deep --strict` | 通过，本机签名有效 |
| Debug／Release Target 图标设置 | 均为 `AppIcon` |
| 源图、Contents.json 与十个槽位尺寸 | 有效；1024 主图与 512 pt @2x 资源字节一致 |
| 两个 `.app` 的图标资源 | 均有 `AppIcon.icns`、`Assets.car`；包含十个 Icon Image 表示，最大 1024 px |

本次使用增量构建，没有执行 clean 或重新创建工程。Desktop 文件服务曾向生成的包写入 `com.apple.FinderInfo` 干扰签名；仅对 `.build` 内的构建产物清理该属性后验证，没有改动工程签名设置、用户数据库或系统图标缓存。

### 已完成的完整测试

2026-10-20 的最终完整测试结果保留在 [Phase025-Verified.xcresult](/Users/waiting/Desktop/Project/Selno/.build/phase025/Phase025-Verified.xcresult)。Xcode 汇总为 **50 个测试定义、55 次实际执行，全部通过，0 失败、0 跳过**。其中 Swift Testing 报告 40 个测试定义，XCTest UI 报告 11 次执行，包含深浅两次启动配置和动态参数用例。

本次没有重复运行已通过的全量测试。业务代码没有变动，新增排除项只移除重复编译输入；当前 Debug、Release 构建已另行实际验证。测试运行设备为 macOS 15.8.1、Intel x86_64；arm64 已编译，未在 Apple Silicon 硬件上运行。

已有测试覆盖：默认总览、真实任务与日程聚合、收件箱快速输入与数量刷新、小月历指定日期跳转、近期安排、任务完成即时刷新、项目创建和完成进度、完全退出后重启持久化，以及原有 Today／Inbox／All Tasks。日历回归涵盖真实 Hover Tips、月／周／列表切换、年份切换、日期详情面板、任务拖动改期与重启保留。数据测试覆盖闰年、星期排列、本地时区、夏令时、跨日事件、UUID 去重、截止日期保留与原 Phase 01 数据迁移。

### UI 和图标显示范围

本次仅复核项目目录中的 Selno 自身测试截图，没有重新读取桌面、Dock 或其他应用界面。已有专属截图确认：浅色与深色层次正常；宽度约 1000、1280、1480 的布局能重排；长标题在日期格中合理截断，完整内容可在悬停与详情中查看；项目进度和已完成状态一致。

| 显示层级 | 验证范围 |
| --- | --- |
| 高清原稿与资源 | 已检查真实 PNG、尺寸和矢量绘图源码 |
| Asset Catalog 与 `.app` | 已确认 Debug／Release 正确编译和打包 |
| Finder 图标服务 | 已有 `NSWorkspace.icon(forFile:)` 读取结果，显示新 S 图标；不等同于逐项人工浏览 Finder 窗口 |
| Dock | 先前自动化尝试没有形成独立的图标截图验收附件，不计为正式通过项；本次不继续读取系统界面 |
| 应用切换器 | 未实际验收 |

关键证据均位于 `.build/phase025/`：

- `current-debug-verified.log`、`current-release-verified.log`：本次真实 Scheme 增量构建。
- `current-signature-debug.log`、`current-signature-release.log`：本次签名校验。
- `current-icon-verification.json`：本次图标设置、包内尺寸、架构和校验值。
- `verified-tests.log`、`test-summary.json`、`Phase025-Verified.xcresult`：已通过的最终全量测试。
- `screenshots/launch-1.png`、`launch-2.png`：Selno 浅色、深色默认总览。
- `screenshots/dashboard-real-data.png`、`dashboard-compact-dark.png`、`today.png`、`project.png`：真实数据及布局。
- `screenshots/calendar-hover.png`、`calendar-agenda.png`、`calendar-drag.png`、`calendar-week.png`、`calendar-list.png`：既有日历交互。

## 后续 UI 建议与范围

后续可继续优化键盘在总览模块间的连续操作、较大辅助功能字体下的断行，以及超多项目时的查找与排序。当前采用系统强调色反馈操作，主体仍保持中性色。

没有开发通知、CloudKit、Apple Calendar、AI、iOS 或高级项目流程。
