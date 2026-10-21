# Selno · 序宁｜Phase 03 工程交付报告

日期：2026-10-21。基于现有工程增量开发，没有重建项目，没有 Commit 或 Push。

本轮功能已实现，Debug／Release 构建和相关复验已通过。单元测试 54 个定义全部通过，14 个 UI 测试定义均有本轮通过记录；其中一次完整回归包含 1 项定位超时，修复后进行了定向复验。下面保留各次运行的原始结果，未将它们描述成一次全量全绿。

## 1. 实际实现

### 品牌动态文案

- 八句品牌文案集中在 `BrandCopy`，按用户给定顺序循环。
- `BrandTypingState` 缓存 Swift `Character` 数组；输入 100ms／字、删除 55ms／字、阅读 3.5–5.5 秒、句间停顿 400ms。Emoji、肤色修饰、组合字符按完整字符处理。
- 标题固定 36pt 高度，单行按空间适当缩放，输入、删除时下方内容保持位置。
- 每个主窗口保留自己的状态。SwiftUI `.task(id:)` 负责取消；离开页面、失去窗口焦点、进入后台或不可见时暂停，返回后保留当前句子和字符位置。
- Reduce Motion 或 VoiceOver 开启时显示完整静态文案。生产辅助功能标签始终使用完整句子，不逐字发送品牌文字。
- 无定时器和第三方动画依赖。UI 测试专用配置允许观察真实动画状态、模拟低动态策略和固定深浅模式；Release 不应用这些测试覆盖。

### UI 视觉语言

建立 `SelnoDesign` 语义色与尺寸：Canvas、Sidebar、Surface、Elevated、三层文字、Border、鼠尾草 Accent、次强调色及 Success／Warning／Danger。

今日聚焦使用主要表面，近期安排、月历、收件箱和项目摘要用留白与弱分隔组织，减少重复深色卡片。共享模块标题、轻量空状态、主次按钮、状态 Badge、任务行和标签 Chip；按钮悬停／按下、标签选择和完成图标提供短反馈，并读取系统 Reduce Motion。

原生窗口、分栏、菜单、输入框、日期选择器和键盘操作继续保留。侧边栏选中态及部分系统控件沿用 macOS 用户的强调色。没有 WebView 或第三方 UI 框架。

### 总览及跨页面

- 总览继续作为默认首页；保留日历、今天、收件箱、全部任务、项目六个导航入口。设置位于侧边栏底部及系统设置菜单。
- 品牌标题、日期、数量与「打开日历」形成稳定层级。今日聚焦空状态保留两个主要动作；已有内容继续限制摘要行数并提供详情入口。
- 3／7 天近期范围、紧凑月历、收件箱快速捕获和项目进度均使用原有真实查询。
- 今天与总览复用同一聚合逻辑；模板节点按明确选择加入今天／近期安排，不重复计算任务。
- 收件箱与全部任务提供标签筛选和排序、模板创建入口；筛选排除当前任务时清除不再匹配的详情选择，删除正在筛选的标签后恢复全部标签。
- 项目任务、任务列表、总览、日历及详情统一使用标签组件。日历日期选中／今天采用品牌色，任务关联节点与独立日程采用不同图标和文字。
- 应用启动打开总览主窗口，设置窗口只在主动打开时显示；不会恢复一个空的工作区。

### 任务模板

持久化 `TaskTemplate`，支持新建、编辑、复制、删除、默认 Emoji、标签、重要性、字段默认值及从已有任务保存。四个内置模板只做首次初始化，均可编辑、删除；删除后不自动补回。

字段支持文本、多行文本、URL、日期时间，以 UUID 标识，包含分组、顺序、可选、显示隐藏和默认内容。创建表单逐组展开；模板编辑器以可点击的整行按钮展开字段，支持上移、下移、移除和新增。

任务标题与模板名称独立。已有任务保存为模板会复制字段及文本默认值、标签、重要性，清除实例的绝对日期和提醒选择，避免复用过期安排。

校园二课预设共十二个字段：

| 分组 | 字段 | 类型 |
| --- | --- | --- |
| 基本信息 | 活动名称、活动说明 | 文本、多行文本 |
| 报名 | 报名开始时间、报名截止时间、报名入口 | 日期时间、日期时间、URL |
| 活动 | 活动开始时间、活动结束时间、活动地点 | 日期时间、日期时间、文本 |
| 材料 | 材料提交截止时间、材料提交地点、活动附件说明 | 日期时间、文本、文本 |
| 其他 | 备注 | 多行文本 |

所有字段均可按需填写。保存前检查必填字段、HTTP(S) URL、日期有效性、报名与活动区间及提醒参数。错误不会留下半条任务或孤立实例。

### 独立实例与多时间节点

`TaskTemplateInstance` 保存模板 UUID、名称、修订号和创建时字段定义／答案快照。它与模板没有级联关系。修改或删除模板不会改写历史任务。

`TaskMilestone` 保存稳定节点 UUID、字段 UUID、名称、语义、日期、是否显示在日历、提醒提前分钟及调度状态。报名开始、报名截止、活动开始、活动结束、材料提交截止分别保留含义。

每个日期字段默认不进入日历、不建立通知；用户分别选择。节点不会写入 `dueAt`，也不会生成 `CalendarEvent` 副本。任务编辑按任务和字段 UUID 更新已有节点，清空日期则移除对应节点；删除任务级联清理节点和实例。

日历按「本地日期 + 任务 UUID」合并原日期角色及节点。同一任务在同一天只有一项，仍展示各节点含义和时间；跨日按实际语义分别出现。日历、悬停、右侧面板继续共享日期聚合快照。拖拽只修改 `plannedAt`，不会搬动独立节点或改变 `dueAt`。

节点通知使用 `selno.node.<节点 UUID>`，显式选择后才请求授权；同 ID 更新替换请求，完成、取消、删除任务或移除节点会清理待发送请求。调度通过可注入网关测试；本轮没有为所有任务开启通知或自动给所有节点提醒。

### 标签系统

扩展原 `TaskCategory`，保留原名称、颜色、SF Symbol、UUID 和旧分类关系；增加可为空的 Emoji 及多标签关系。没有另建一套重复 Tag 模型。

八组预设色为鼠尾草、琥珀、蓝灰、雾紫、陶土、蔷薇、橄榄、青绿。旧自定义颜色保留；新编辑采用预设色。Chip 使用轻量底色、独立 Emoji／图标和单行截断，任务行显示前两个及 `+N`，完整名称可通过提示查看。高对比环境增强边界。

设置支持创建、改名、修改 Emoji／颜色及确认删除。任务创建和编辑可多选，列表可筛选。颜色不会覆盖任务的重要性、截止和完成语义。

## 2. 模块与文件

### 新增

| 文件／模块 | 职责 |
| --- | --- |
| `Features/Dashboard/BrandHeadline.swift` | 文案配置、字符状态机、窗口活动探针、标题呈现 |
| `Shared/Components/SelnoDesign.swift`、`TagChip.swift` | 语义设计、按钮、Badge、标签、标签选择 |
| `Shared/Components/BrandAccessibilityTestOverrides.swift` | Debug 隔离 UI 测试的辅助功能和外观覆盖 |
| `Features/Settings/SettingsWorkspace.swift` | 原生模板、标签管理 |
| `Features/Templates/TemplateTypes.swift` | 版本化字段、答案、校验与编码 |
| `TemplateEditorView.swift`、`TemplateFieldsForm.swift`、`StructuredTaskDetail.swift` | 定义编辑、动态录入、快照及节点详情 |
| `Models/TaskTemplate.swift` | 模板、任务实例、时间节点三种实体 |
| `Persistence/SelnoSchemaV2Models.swift` | 冻结 Phase 02 六种实体 |
| `Services/TemplateService.swift`、`TagService.swift` | 明确保存、校验、失败回滚、幂等预设 |
| `Services/ReminderService.swift`、`Shared/Components/ReminderReconciliation.swift` | 显式节点通知、稳定标识、保存后串行协调 |
| `SelnoTests/Phase03Tests.swift`、`SelnoUITests/Phase03UITests.swift` | 数据、迁移、文案、提醒及运行界面验证 |

### 修改

- `SelnoApp`、`AppBootstrap`、`MainWindowView`：设置入口、模板初始化、窗口状态与提醒协调。
- `TodoTask`、`TaskCategory`、`SelnoSchema`、`PersistenceController`：V3 模型及兼容迁移。
- `TaskService`：标签／实例／节点原子保存，保留旧任务创建、状态和日期行为。
- `TaskEditorView`、`TaskDetailView`、`TaskListView`、`TaskRowView`：模板录入、详情、多标签及筛选。
- `DashboardWorkspace`、`DashboardProjection`、`ProjectWorkspace`、`WorkspaceStyle`：共享视觉和节点聚合。
- `CalendarAgenda`、`CalendarDataQuery`、`CalendarRangeContent`、`CalendarHoverTip`、`CalendarGridView`、`CalendarListView`、`AgendaRows`：有界节点查询、同日去重、标签和视觉。
- 原 UI 测试：保留关键断言，统一独立存储、启动状态及控件定位。移除旧测试中读取 Dock 的逻辑，本轮仅使用 Selno 窗口截图。
- `README.md` 与本报告：使用说明和验收记录。

相对本轮开始时的文件哈希，共修改 28 个已有文件、新增 18 个文件（含报告）。逐文件清单及受保护文件核对见 [本轮文件审计](/Users/waiting/Desktop/Project/Selno/.build/phase03/source-audit.json)。这些数字不把 Phase 01／02／02.5 原有未提交文件重复计为本轮新增。

## 3. 模型与迁移

当前 Schema 为 **V3（3.0.0）**，包含原六种实体及三种新实体。

| 模型 | 本轮新增的持久化数据 |
| --- | --- |
| TodoTask | 可选多标签、可选模板实例、可选节点列表 |
| TaskCategory | Emoji、多标签反向关系；旧分类关系保留 |
| TaskTemplate | UUID、名称、Emoji、修订号、定义 Data、创建／更新时间 |
| TaskTemplateInstance | UUID、源模板 UUID／名称／修订号、快照 Data、所属任务 |
| TaskMilestone | UUID、字段 UUID、名称、语义、日期、日历选择、提醒参数／状态、所属任务 |

V1 定义保持冻结；先从实际 Phase 02 源码冻结 V2，再扩展当前类型。迁移链为 V1 → V2 lightweight、V2 → V3 custom。后一个阶段将旧 `category` 补入 `tags`，保留旧关系，不删除或重建数据库。

字段定义与答案使用 Codable 版本、UUID 和明确类型，避免用名称关联。缺省元数据有安全默认值；不支持的未来版本或无法解码的记录保留原始 Data。普通任务信息仍可编辑，模板定义不允许被空默认值覆盖。

日历只新增可见范围内、已选择显示的节点查询。今日与近期沿用原有有界查询和 UUID 去重；没有为每个日期格重复取库。

## 4. 本轮构建与测试

环境：Intel Mac、macOS 15.8.1、Xcode 26.3、macOS SDK 26.2，真实共享 Scheme `Selno`。最低系统保持 macOS 15.0，Swift 语言模式及 Bundle Identifier／签名设置没有改变。

### 已执行且通过

| 检查 | 实际结果与记录 |
| --- | --- |
| Debug `build-for-testing` | 通过；[构建日志](/Users/waiting/Desktop/Project/Selno/.build/phase03/debug-tmp-build.log) |
| Release `build` | 通过；[构建日志](/Users/waiting/Desktop/Project/Selno/.build/phase03/release-final.log) |
| 最新单元测试 | **54 个定义、58 次参数化执行全部通过**，包含磁盘关闭重开后的模板快照、五个节点、多标签、V1／V2 迁移及独立事件 UUID／日期保留 |
| 修复后 UI 定向复验 | 校园模板／节点／多标签／重启快照、模板标签管理／自定义字段／标签筛选／窄窗口两项全部通过 |
| 最新定向结果包 | **56 个定义、60 次执行，0 失败、0 跳过**（54 个单元定义 + 2 个 UI 定义）；[Focused-Final.xcresult](/Users/waiting/Desktop/Project/Selno/.build/phase03/Focused-Final.xcresult)、[日志](/Users/waiting/Desktop/Project/Selno/.build/phase03/focused-final.log) |
| 其余 UI 回归 | 旧 Calendar 3 项、Dashboard 3 项、任务列表 3 项、启动 1 项，以及品牌动画 2 项均在本轮完整回归中通过；启动定义按两种配置执行 |
| 架构 | Release 包含 **x86_64、arm64**；[记录](/Users/waiting/Desktop/Project/Selno/.build/phase03/release-architectures.txt) |
| 签名 | Debug／Release 均经 `codesign --verify --deep --strict` 通过；[Debug](/Users/waiting/Desktop/Project/Selno/.build/phase03/debug-signature.log)、[Release](/Users/waiting/Desktop/Project/Selno/.build/phase03/release-signature.log) |
| 文件检查 | `git diff --check` 通过；原用户文件、图标、工程设置和暂存副本核对通过 |

最新单元检查包括 14 个本轮新增定义；UI 新增 4 个定义。单元与 UI 共 68 个不同定义有本轮通过记录，结果分布在完整回归和后续定向结果包中。

### 已执行但失败、随后修复

最近一次完整 Scheme 运行 [Final-Acceptance.xcresult](/Users/waiting/Desktop/Project/Selno/.build/phase03/Final-Acceptance.xcresult) 的原始结果是 **67 个定义、72 次执行：71 次通过、1 次失败，0 跳过**。失败项为校园任务重启后的快照标题定位，Xcode 在 macOS 15 上评估文字控件查询超时。对应运行界面中快照与日期数据实际存在。

随后给快照标题增加稳定标识，保留重启／节点／快照断言；该 UI 项在 `Focused-Final` 中重新通过。同时新增直接重开磁盘库的单元测试，核对模板 Data、字段 UUID、节点 UUID、日历选择、多标签和截止日期，已通过。模板编辑菜单的浅色对比度调整也经该次管理流程和真实截图复核。

**修复后没有再执行一趟完整 Scheme**，而是重跑全部单元及受影响的两项 UI。上述完整运行的失败记录没有被删除或改记为通过。结果汇总见 [完整运行 JSON](/Users/waiting/Desktop/Project/Selno/.build/phase03/full-summary.json) 和 [定向复验 JSON](/Users/waiting/Desktop/Project/Selno/.build/phase03/focused-summary.json)。

### 验证方式

本轮 Debug／Release 使用临时 DerivedData，避免 Desktop 文件提供程序写回 Finder 属性干扰签名和运行。工程仍在原位置，测试结果保存在 `.build/phase03`。

```sh
TASK_DERIVED_DATA=$(cat .build/phase03/verification-derived.txt)
TASK_RELEASE_DERIVED_DATA=$(cat .build/phase03/release-derived.txt)

DEVELOPER_DIR=/Users/waiting/Downloads/Xcode.app/Contents/Developer \
xcodebuild build-for-testing -project Selno.xcodeproj -scheme Selno \
  -configuration Debug -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath "$TASK_DERIVED_DATA"

DEVELOPER_DIR=/Users/waiting/Downloads/Xcode.app/Contents/Developer \
xcodebuild test-without-building -project Selno.xcodeproj -scheme Selno \
  -configuration Debug -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath "$TASK_DERIVED_DATA" -collect-test-diagnostics never \
  -resultBundlePath .build/phase03/Final-Acceptance.xcresult

DEVELOPER_DIR=/Users/waiting/Downloads/Xcode.app/Contents/Developer \
xcodebuild build -project Selno.xcodeproj -scheme Selno \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$TASK_RELEASE_DERIVED_DATA"
```

最后一次定向运行在相同命令中增加 `-only-testing:SelnoTests`、`-only-testing:SelnoUITests/Phase03UITests/testCampusTemplateTagsMilestonesAndRelaunch`、`-only-testing:SelnoUITests/Phase03UITests/testTagAndTemplateManagement`，结果路径为 `Focused-Final.xcresult`。重新运行时应选择新的结果包目录。

实际目录分别记录在 `.build/phase03/verification-derived.txt` 和 `release-derived.txt`。测试开关只在 Debug 生效，每个 UI 用例使用随机独立数据库；重启检查复用同一个用例的数据库。没有用演示任务填充生产首页。

单元测试包含真正的 V1 原库字节迁移、冻结 V2 磁盘库迁移、UUID／状态／日期／关系保留、模板快照独立性、非法输入不产生残留、旧标签迁移、节点去重与稳定 ID、通知网关的增改清理及拒绝授权／过期行为。故意构造损坏库的测试会输出 Core Data 错误，结果以断言为准，不能据此认定正常库损坏。

开发中遇到并修复了只读辅助功能环境值导致的编译错误、Desktop 构建产物签名属性干扰、UI 测试启动恢复状态、Xcode／macOS 控件类型定位差异，以及模板字段行点击范围问题。早期失败或中止记录不作为通过依据；旧测试包的成绩不算最终验收。

## 5. 真实界面与图标

截图使用 `app.windows.firstMatch.screenshot()`，只取 Selno 自身窗口；内容由 UI 测试实际创建并持久化，不是设计稿。模板相关截图已用最后一次复验结果更新。完整索引见 [截图来源记录](/Users/waiting/Desktop/Project/Selno/.build/phase03/screenshot-index.json)。

深色总览：

![深色总览](/Users/waiting/Desktop/Project/Selno/.build/phase03/screenshots/dashboard-dark.png)

浅色总览与真实任务、事件、收件箱数据：

![浅色总览](/Users/waiting/Desktop/Project/Selno/.build/phase03/screenshots/dashboard-light.png)

模板任务创建与多标签：

![模板任务创建](/Users/waiting/Desktop/Project/Selno/.build/phase03/screenshots/campus-template.png)

二课活动的可选日期及独立日历／提醒选择：

![二课活动日期](/Users/waiting/Desktop/Project/Selno/.build/phase03/screenshots/campus-dates.png)

标签筛选、长名称及窄窗口：

![标签与窄窗口](/Users/waiting/Desktop/Project/Selno/.build/phase03/screenshots/inbox-tags.png)

任务快照与多时间节点：

![任务详情](/Users/waiting/Desktop/Project/Selno/.build/phase03/screenshots/task-details.png)

另有 [模板编辑](/Users/waiting/Desktop/Project/Selno/.build/phase03/screenshots/template-editor.png)、[标签管理](/Users/waiting/Desktop/Project/Selno/.build/phase03/screenshots/tags-settings.png)、[今天](/Users/waiting/Desktop/Project/Selno/.build/phase03/screenshots/today.png)、[项目](/Users/waiting/Desktop/Project/Selno/.build/phase03/screenshots/project.png)、[日历悬停](/Users/waiting/Desktop/Project/Selno/.build/phase03/screenshots/calendar-hover.png) 和 [深色紧凑窗口](/Users/waiting/Desktop/Project/Selno/.build/phase03/screenshots/dashboard-compact-dark.png)。

本轮没有重绘图标。原主图位于 `Branding/SelnoIcon-1024.png`，4096 原稿位于 `Branding/SelnoIcon-master-4096.png`；Asset Catalog 为 `Selno/Assets.xcassets/AppIcon.appiconset`。十个 PNG 槽位的尺寸与 JSON 已重新检查，Debug／Release 继续使用 `AppIcon`。

两个包均包含 `AppIcon.icns`（48,818 字节）及 `Assets.car`（572,824 字节），`CFBundleIconFile=AppIcon`、Bundle Identifier 正确。通过系统 `NSWorkspace.icon(forFile:)` 从本轮 Release 包读取并渲染后，已人工查看为既有石墨灰 S 图标：[打包图标预览](/Users/waiting/Desktop/Project/Selno/.build/phase03/packaged-icon-preview.png)。这项检查没有打开 Finder、Dock 或应用切换器。资源证据见 [打包审计](/Users/waiting/Desktop/Project/Selno/.build/phase03/package-audit.json) 与 [尺寸审计](/Users/waiting/Desktop/Project/Selno/.build/phase03/icon-source-audit.json)。

## 6. 人工验收边界及后续细节

- VoiceOver 完整读屏、真实系统 Reduce Motion／高对比设置的组合体验，仍需目标机器人工验收；自动测试覆盖应用策略和完整句子辅助功能内容，不能替代实际语音检查。
- 本地通知的授权弹窗、系统横幅、锁屏及勿扰模式下的投递体验尚未人工验证。当前自动测试通过可注入网关验证请求数据和同步清理，不宣称已看到系统通知。
- Apple Silicon 已做构建架构检查，当前 Intel 主机不能替代 Apple Silicon 真机运行。
- Dock 和应用切换器显示本轮未独立验收；不读取或截取这些界面，也不重置系统图标缓存。
- 可继续精修完整键盘 Tab 顺序、长内容任务详情和高密度项目列表；本轮保留原生控件及原有快捷捕获，不扩展为另一套工作流。
- 收件箱／全部任务在未选中任务时仍沿用原生详情占位，后续可压缩为顶部轻量摘要；模板字段位于首尾时的排序按钮也可进一步明确禁用态。这些属于已识别的视觉细节，未影响本轮创建、编辑、排序数据保存和筛选流程。

本轮没有集成 Apple Calendar、CloudKit、AI、网络服务、iOS、自动备份或完整通知调度平台。到 Phase 03 为止停止。

## 7. 工作区保护

没有修改用户原有 `ContentView.swift`。暂存的 `AgendaRows 2.swift` 文件及其 index blob 保留，仍使用此前获准的 Target 排除配置；本轮没有再次修改工程文件。图标源资源与 `CalendarEvent` 实体保持原样。未进行 Git Commit、Push、reset 或数据库删除。

窗口行为参考 [Apple Scene 默认启动行为](https://developer.apple.com/documentation/swiftui/scene/defaultlaunchbehavior(_:)) 与 [Settings 原生场景](https://developer.apple.com/documentation/swiftui/settings)；实际可用性以本轮工程运行记录为准。
