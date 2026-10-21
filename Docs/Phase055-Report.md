# Selno · 序宁 — Phase 05.5 安全、质量与性能审计报告

- 审计日期：2026-10-22
- 审计对象：`main` 分支，基线提交 `e4e3986`，工作区包含本轮未提交改动
- 运行环境：macOS 15.8.1（x86_64）、Xcode 26.3（17C529）
- 数据边界：性能与回归测试只使用内存库或临时目录中的合成数据；本轮没有读取、修改、导出或删除真实用户数据库。
- 说明：本报告不记录任何凭据值，不复制真实任务内容，不输出完整用户目录路径。报告中“未发现”只表示已执行规则未命中，不表示绝对不存在。

## 1. 工程概览

本轮是质量与安全审计，不新增业务功能，不新增 Schema 版本，不修改 Bundle Identifier `com.yexiaonan.Selno`。

| 项目 | 结果 |
| --- | --- |
| 基线分支 | `main`，跟踪 `origin/main`，本地 refs 均为 `e4e3986` |
| 本轮前工作区 | 用户已有多项未提交改动；本轮在其上增量修改，没有回滚或覆盖 |
| 跟踪文件 | 145 个（移除 1 个已跟踪的 Xcode 用户状态文件后） |
| 新 Schema | 无；V1–V5 保持不变 |
| 新增测试 | 4 个 Phase 05.5 测试文件，覆盖隔离存储、任务查询、导入上限与性能回归 |
| 构建产物 | 仅写入 `/tmp` 下的独立 DerivedData；未写入仓库 |

本轮实际处理的主线：

1. 仓库卫生、忽略规则、贡献与安全政策、CI 工作流。
2. 测试存储 fail-closed，避免测试宿主落到真实库。
3. 备份日期编解码与导入数量上限。
4. 仪表盘收件箱、任务工作区、筛选上下文、工作台投影的可测量优化。
5. 性能基线、回归测试和本报告。

## 2. Git 仓库检查

执行的检查：

```sh
git status --short
git branch -vv
git remote -v
git log --oneline --decorate -15
git ls-files
git diff --check
git fetch origin
```

结果：

- `git status --short` 显示本轮修改、1 个已暂存删除（`xcuserdata` 用户状态）、以及新增的文档、CI、测试文件；没有未跟踪构建产物进入仓库。
- `git branch -vv`：`main e4e3986 [origin/main]`，本地与本地记录的远程 ref 相同。
- `git remote -v`：仅一个 `origin`，未发现额外远程、子模块或 LFS 配置。
- `git diff --check`：通过，无空白错误。
- `git ls-files`：审计开始时 145 个文件；本轮新增 9 个文件（规范、CI、测试与报告），并从索引移除 1 个 `xcuserdata` 用户状态文件。最大文件为 6.7 MB 的品牌主图，其余为图标、截图和 100 KB 的合成迁移 Fixture。
- 跟踪文件模式全部为 `100644`，没有可执行位或世界可写位。
- `git fetch origin`：第一次因 DNS 无法解析 `github.com` 失败；提交前重试成功，`HEAD`、`origin/main` 均为 `e4e3986`，没有发现远程分叉。网络故障期间的结论只代表本地 refs 一致；重试后才确认远程当前状态。

未发现：

- `.gitmodules`、`.gitattributes` 之外的 LFS 配置、子模块。
- 跟踪的 `.env`、私钥、证书、Provisioning Profile、数据库、WAL/SHM、备份 JSON 或日志。
- `Docs/` 或 `README.md` 中的 `/Users/` 绝对路径。

已处理：

- `Selno.xcodeproj/xcuserdata/.../xcschememanagement.plist` 从 Git 索引移除，本地文件保留；该文件含本机账户名，不应进入共享仓库。
- `.gitignore` 由宽泛规则改为精确规则，未忽略整个 `Selno/Backup/`、全部 JSON 或全部 PNG。
- 新增 `.gitattributes` 统一换行并标记二进制资源。

保留未动：

- `Selno/Features/Calendar/AgendaRows 2.swift` 是已跟踪的旧重复文件，当前被 target 的 exception set 排除。历史文档显示用户曾明确要求保留该文件与索引状态，本轮不删除。
- `Selno/Item.swift`、`Selno/ContentView.swift` 是 Xcode 模板遗留代码；README 明确说明正式入口不使用、也不删除模板存储。它们被列为清理建议，不在本轮删除。

## 3. 隐私与敏感信息审计

扫描范围：全部 Git 历史、当前跟踪文件名、`Docs/`、截图、备份 Fixture、Xcode 配置。

已执行的检查：

```sh
git log -p --all | grep -Eic 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{36,}|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}'
git ls-files | grep -Ei '(^|/)\.env(\.|$)|\.(p8|p12|pfx|key|pem|mobileprovision|provisionprofile)$|\.store($|-)|\.sqlite($|-)|\.log$'
git grep -n '/Users/' -- Docs README.md
```

结果：

- 凭据类模式在全部历史中的命中数为 **0**。没有发现 API Key、GitHub Token、AWS Key、私钥块或 `.env` 文件。
- 敏感文件名扫描只命中 `SelnoTests/Fixtures/Phase01.store`。该文件是 Phase 01 的合成迁移 Fixture，由固定 UUID 与压缩字节生成，不含真实用户数据；测试只读取其临时副本。
- 五份历史报告中的本机绝对路径已替换为相对链接或 `<repo>` / `<Xcode.app>` 占位；`git grep '/Users/'` 现无命中。
- `Docs/Phase05Screenshots/` 的截图为合成示例内容；抽检的 01、04 截图未显示真实账户、任务或日程。这个结论来自抽检与审计，不等于对每个像素作绝对证明。
- `SECURITY.md` 不再声称 Release 已启用 App Sandbox；当前事实是 Debug 构建含 sandbox entitlement，Release ad-hoc 产物没有嵌入 sandbox entitlement。
- Bundle Identifier 保持 `com.yexiaonan.Selno`，未按审计建议更改。该标识包含个人 handle，属于产品标识决策，不应由本轮擅自修改。

已记录但未删除的风险：

- 前序 Phase 05 真库副本验收在系统临时目录留下了日志与 `.xcresult` 包。审计确认其中未包含可读的真实任务正文、数据库文件或截图，但可能含本机路径、测试元数据和系统诊断；这些文件位于世界可读的临时目录。由于删除属于不可逆操作，且用户要求所有删除先证明目标安全，本轮保留并在第 14 节列为待所有者确认的残留项。
- `Selno/ContentView.swift` 等模板源码含开发者姓名注释。它是用户明确保留的模板代码，本轮不修改；建议后续单独清理。
- 品牌主图 `Branding/SelnoIcon-master-4096.png` 为 6.7 MB，是仓库体积的主要来源，但不是敏感信息。是否改用 LFS 或移除主图由所有者决定。

## 4. Git 历史风险

- 历史只有 4 个提交；没有合并提交、子模块或指向外部仓库的引用。
- 全历史凭据模式扫描为 0；没有发现需要轮换的凭据，也没有发现需要重写历史的已泄漏秘密。
- 没有执行 `git reset --hard`、`git clean -fd`、`git push --force`、历史重写或远程分支删除。
- 本轮的 `xcuserdata` 删除只发生在索引层，未改写历史；本地文件仍保留。
- 提交前 `git fetch origin` 重试成功，远程 `origin/main` 仍为 `e4e3986`，与本地基线一致，没有分叉。若推送前远程再次前进，应停止自动推送并要求人工选择合并策略，不能强制覆盖。

结论：未发现需要凭据轮换或历史重写的高风险秘密。没有进行任何历史改写。

## 5. `.gitignore`、仓库规范与文档

### 忽略规则

`.gitignore` 现在覆盖：

- Xcode / SwiftPM 构建产物与结果包；
- `xcuserdata`、`*.xcuserstate`；
- macOS 元数据；
- SwiftData/SQLite 主库与 WAL、SHM、journal 旁文件；
- 自动备份与临时导出 JSON；
- `.env`、证书、私钥、Provisioning Profile；
- 日志、临时文件与编辑器状态。

规则使用具体文件名或扩展名，没有忽略整个源码目录、整个备份目录、全部 JSON 或全部 PNG。

### 仓库规范

新增：

- `CONTRIBUTING.md`：目录结构、Xcode 环境、构建/测试命令、Swift/SwiftUI 约定、Schema 与迁移规则、隐私规则、Conventional Commits 与 PR 要求。
- `SECURITY.md`：私下报告方式、应避免放入公开 Issue 的内容、处理流程、当前安全边界。没有编造安全邮箱，也没有声称 GitHub Private Vulnerability Reporting 已启用。
- `.gitattributes`：文本文件 LF，图片/图标/数据库结果包按二进制处理。
- `README.md`：更新 Phase 05.5 摘要、沙盒/签名事实、V5 迁移说明与测试存储说明。

未处理：

- 仓库没有 `LICENSE`。许可证选择属于所有者决策，本轮没有擅自添加。
- 没有移动或重命名历史报告；只清理了其中的本机绝对路径。这样避免破坏已有链接与审计记录。

## 6. GitHub Actions / CI

新增 `.github/workflows/ci.yml`：

- 触发：`push` 到 `main`、针对 `main` 的 `pull_request`、以及 `workflow_dispatch`。
- 权限：`permissions: contents: read`，没有写权限、没有 secrets 注入。
- 并发：同一 workflow/ref 取消旧运行。
- `debug-unit-tests`：
  - `actions/checkout@v4.2.2`；
  - 选择可用的最新 Xcode 26；
  - 静态敏感文件名与凭据模式扫描；
  - `build-for-testing` + `test-without-building`，只运行 `SelnoTests`；
  - 不上传任何测试产物、截图、日志或本地数据。
- `manual-ui-tests`：仅 `workflow_dispatch` 且 `run_ui_tests=true` 时运行；原因已写在 workflow 注释中：macOS 托管 runner 可能没有可用的交互式窗口服务器。

安全边界：

- 未使用 `pull_request_target`，不把 secrets 暴露给来自 fork 的代码。
- 没有把 Token、环境变量或本地路径写入日志。
- Action 使用版本标签固定，而不是 commit SHA。这比浮动 `@v4` 好，但仍不是最严格的 SHA 固定；属于待改进项。
- 本地等价命令已执行并通过。普通 push 会触发 GitHub Actions；本轮没有等待云端运行结果，因此不声明 CI 已在 GitHub 上通过。
- GitHub 仓库的 Secret Scanning、Push Protection、分支保护、Dependabot 等设置属于管理员操作；本轮没有修改，也无法确认当前是否启用。

## 7. Swift / SwiftUI 架构检查

本轮没有进行大规模拆分。审计确认的问题与处理：

| 观察 | 处理 |
| --- | --- |
| `TaskListView` 在 body 中对整个数组重新过滤、排序、搜索 | 未重构；列为残留性能项 |
| 工作台每次 body 重建 `WorkspaceBoardData` 与投影 | 本轮先移除被丢弃的月历投影；缓存生命周期仍是残留项 |
| 视图身份包含 `workspace.updatedAt`、导航 token 重建子树 | 未改动；列为残留项 |
| 多个每分钟 `TimelineView` 独立驱动昂贵 body | 未改动；列为残留项 |
| 视图承担校验、权限、时钟和查询编排 | 未改动；需要独立设计，不适合低风险补丁 |
| `WorkspaceService` 存在测试专用写入路径 | 未改动；列为架构残留项 |
| 没有使用 `@unchecked Sendable` 压制警告 | 保持；本轮新增代码没有引入该标注 |

本轮实际改动集中在可证明的查询与计算路径：

- `TaskWorkspaceQuery` 为任务工作区增加归档排除；Inbox 进一步排除项目、计划开始、计划日期。
- `TaskFilterEvaluationContext` 把 `startOfDay`、日期区间和搜索词修剪提升到每次遍历一次。
- `DashboardProjection.build` 增加 `includeMonth`，工作台不再构建只被仪表盘使用的月历快照。
- 备份日期编解码从“每个日期创建一个 `ISO8601DateFormatter`”改为每个 codec 复用 `Date.ISO8601FormatStyle`。

没有为了消除警告而引入 `@unchecked Sendable`，也没有为了性能改变用户可见的筛选语义。

## 8. SwiftData、迁移与备份安全

### 测试隔离

`PersistenceController.launchStorage(arguments:environment:)` 现在是 fail-closed：

1. 参数含 `--selno-ui-testing` 时必须提供合法 `SELNO_UI_TEST_STORE_ID`，否则抛出 `PersistenceError.invalidUITestStore`，不会回退到真实库。
2. XCTest 宿主环境变量存在时使用内存库。
3. 普通启动才返回 `.local`。

该逻辑不依赖 `#if DEBUG`，因此 Release 测试宿主也不会误用正式库。`Phase055TestIsolationTests` 覆盖四种路径。

### 备份导入

已有保护：

- 格式标识、`schemaVersion` 1–2、未来版本拒绝；
- 128 MiB 文件大小上限，读取前后各检查一次；
- 项目、标签、模板、任务、日程、提醒、工作台、任务视图的重复 UUID 检查；
- 任务对项目/分类/标签、提醒对任务的引用检查；
- 日期有限性检查、日程结束不早于开始、全天日程约束；
- 工作台与模块上限、全局工作台唯一、模块引用任务视图存在；
- 自定义日期范围完整性；
- 合并按 UUID 幂等；替换先写安全备份，所有写入在单个事务中保存，失败回滚。

本轮新增：

- 顶层集合数量上限：项目/标签/模板各 50,000，任务/日程各 100,000，提醒 200,000，任务视图 10,000；
- 总记录上限 500,000（含子任务、模板实例、时间节点、模块）；
- 超限时在写入前抛出 `BackupError.invalidData`，不触碰现有数据库。

新增 `SelnoTests/Phase055BackupLimitsTests.swift` 验证超过任务上限的文件被拒绝。

仍然存在的风险：

- JSON 已完整解码后才执行上述校验；128 MiB 原始文件在解码阶段仍可能造成较高内存峰值。要彻底解决需要流式解析或更小的硬上限，未在本轮实现。
- 部分标量字段在解码时用 `try?` 回退默认值，类型错误可能被静默修正；这是既有兼容策略，列为残留项。
- 模板 payload、工作台/任务视图的原始 Base64 字节只做语法校验，导入时仍可能覆盖已验证的类型化值。
- 自动安全备份与用户导出为明文 JSON，未设置更严格的 POSIX 权限；这是本地优先应用的既有设计，需要产品决策。
- 删除标签后，持久化筛选中的旧标签 UUID 可能悬空；加载时会忽略，但不会主动清理。

### Schema 与迁移

- V1–V5 模型没有被本轮修改；没有新增 V6。
- 审计确认 V4/V5 仍复用可变模型类，V4 定义未完全独立冻结；这会影响未来迁移的可审计性。本轮不做 Schema 重排，列为下一轮前置项。
- 全量单元测试继续覆盖 V1 Fixture、V2/V3/V4/V5 迁移、JSON V1/V2 往返、合并幂等、替换安全备份和失败回滚。

## 9. 性能基线

测量条件：

- Debug、`-Onone`、app-hosted XCTest；
- 合成内存库；
- 任务数 100 / 1,000 / 10,000；
- 模块数 10 / 30 / 100，宽度 400 / 800 / 1,200；
- 每个样本先 warm-up，再取 3 次中位数；备份导出取 2 次中位数；
- 只测算法、查询与 JSON 编解码，不测窗口服务器、FPS、CPU 或内存。

基线（`perf-before.log`，10,000 任务）：

| 场景 | 中位数 |
| --- | ---: |
| 仪表盘收件箱，无 limit | 1,223.61 ms |
| 仪表盘收件箱，limit 4 | 5.52 ms |
| 收件箱 `fetchCount` | 3.71 ms |
| 全表筛选，无搜索 | 92.51 ms |
| 状态+日期筛选 | 94.00 ms |
| 搜索筛选 | 185.93 ms |
| 备份导出映射 | 3,060.21 ms |
| 备份 JSON 编码 | 9,977.95 ms |
| 备份 JSON 解码+校验 | 12,119.98 ms |
| 仪表盘投影（10k 任务 + 200 日程） | 702.03 ms |
| 月历议程 | 330.92 ms |
| 100 模块布局，宽 1,200 | 0.08 ms |

未测量：

- 冷启动、热启动、首次可交互；
- 空闲 CPU、内存峰值、场景切换、编辑延迟、真实滚动 FPS；
- Instruments Time Profiler / SwiftUI / Core Data 模板。

以上项目均标记为“未测得”，不以“没有明显卡顿”代替性能结论。

## 10. 优化前后对比

### 收件箱快照与计数

- `@Query` 从无限制收件箱改为 `limit 4`；
- 计数从拉取全部匹配行改为 `context.fetchCount`；
- 谓词继续排除归档、项目、计划开始、计划日期、已完成、已取消。

10,000 任务：

| 指标 | 优化前 | 优化后 |
| --- | ---: | ---: |
| 收件箱 limit 4 | 5.52 ms | 6.14 ms |
| 收件箱 count | 3.71 ms | 4.27 ms |
| 无限制收件箱（不再在主界面每次保存时执行） | 1,223.61 ms | 仍可用于诊断 |

结论：limit 与 `fetchCount` 的主要收益是**不再拉取 1.2 秒级的全量数组**；单次查询本身没有显著变快，不能把 5.52→6.14 的噪声当作优化。

### 筛选上下文

生产路径改为 `evaluationContext` + `matches(context:)`：

| 10,000 任务 | 优化前 | 优化后（prepared） |
| --- | ---: | ---: |
| 无搜索 | 92.51 ms | 14.05 ms |
| 状态+日期 | 94.00 ms | 43.81 ms |
| 搜索 | 185.93 ms | 94.19 ms |

这是本轮最明确的 CPU 侧改进：每个任务不再重复计算 `startOfDay`、日期区间和搜索词修剪。未预处理的旧 API 在最终复测中为 94.51 / 129.13 / 189.59 ms，因此不能把“94.00→43.81”描述成同一个旧调用的提速；生产路径已经改用 prepared 上下文，旧 API 只保留给单条判断与测试。

### 备份日期编解码

`ISO8601DateFormatter` 的创建从“每个日期一次”改为“每个 encoder/decoder 一次”：

| 10,000 任务 | 优化前 | 优化后 |
| --- | ---: | ---: |
| JSON 编码 | 9,977.95 ms | 202.17 ms |
| JSON 解码+校验 | 12,119.98 ms | 228.63 ms |
| 备份导出映射 | 3,060.21 ms | 2,982.13 ms |
| 文件大小 | 4,539,915 B | 4,539,915 B |

编码/解码约下降 98%，字节格式与兼容性不变；备份导出映射没有明显变化，说明剩余成本在模型映射，而不是日期格式化。

### 工作台投影

工作台只需要 focus、今日日程、upcoming 和逾期计数，不需要完整月历快照：

| 10,000 任务 + 200 日程 | 中位数 |
| --- | ---: |
| 完整投影（含月历） | 686.54 ms |
| 工作台投影（不含月历） | 338.32 ms |

约减少 51% 的投影时间。月历模块仍通过 `monthSnapshot` 自行构建；仪表盘继续使用完整投影。

### 任务工作区查询

新增了 Inbox 的存储层窄化（归档、项目、计划日期），不再先取全表再在内存过滤：

| 10,000 任务 | 新增测量 |
| --- | ---: |
| 工作区 Inbox 查询 | 1,218.45 ms |
| 工作区 All 查询（仅排除归档） | 2,453.50 ms |

这仍是当前最大的单次查询成本。`All`/`Today` 仍需要全表活动任务；`TaskListView` 的 body 内排序/过滤也仍在。未把 1.2 秒的 Inbox 查询声称为“已解决”，只说明它比无谓的全表拉取更窄，并列为残留项。

### 布局

100 模块、1,200 宽度的布局中位数在最终复测中为 0.08 ms（400/800 宽度为 0.06 ms），和基线一致；没有观察到可归因于本轮改动的布局退化。

## 11. 迁移与回归测试

本轮最终单元测试覆盖：

- V1 Fixture 解压、SHA-256 校验与磁盘迁移；
- V2/V3/V4/V5 版本化 Schema 迁移；
- JSON V1 与 V2 的编码、解码、校验、合并、替换；
- 合并幂等、重复 UUID、引用完整性、未来版本拒绝；
- 替换前安全备份、事务回滚、失败不破坏现有库；
- 工作台、模块、筛选、任务视图、标签、模板、提醒；
- Phase 05.5 新增的隔离存储、任务查询、性能与导入上限。

结果：全量单元测试通过（具体数量见第 15 节）。本轮没有对真实用户库执行迁移；迁移测试使用合成 Fixture 和临时目录。Phase 05 曾在正式库离线副本上执行 V4 → V5 验收，本轮没有重复该操作。

## 12. 可访问性与人工验收

本轮没有完成以下人工验收，因此不标记为通过：

- VoiceOver 全流程；
- Reduce Motion 下的品牌标题与工作台动效；
- 仅键盘完成排序、移动、筛选、确认对话框；
- 焦点恢复、对比度、Emoji 标签朗读；
- 真实通知授权、横幅、点击深链；
- 原生保存/打开面板在不同 macOS 版本和文件提供程序下的行为；
- 窗口缩放、长时间运行、跨午夜真实时钟。

现有 UI 测试覆盖了一部分交互，但它们不能替代人工可访问性验收。UI 测试结果见第 15 节；未运行的人工项保持“未通过/未验证”。

## 13. 清理清单

本轮没有删除任何用户文件、源码或测试数据。只从 Git 索引移除了 1 个本机 Xcode 用户状态文件，本地副本保留。

保留并建议后续处理：

| 项目 | 原因 | 建议 |
| --- | --- | --- |
| `Selno/Features/Calendar/AgendaRows 2.swift` | 已跟踪旧重复文件，当前被 target 排除；历史授权保留 | 由所有者确认后删除并从索引移除 |
| `Selno/Item.swift`、`Selno/ContentView.swift` | Xcode 模板遗留；README 说明不删除，避免覆盖用户旧模板数据 | 单独清理模板引用，先确认旧存储 |
| `Branding/SelnoIcon-master-4096.png` | 6.7 MB 主图，仓库体积主要来源 | 评估 LFS 或只保留生成源 |
| `Docs/Phase05Screenshots/` | 合成截图，作为 Phase 05 验收证据 | 保留；新增截图继续使用合成数据 |
| `/private/tmp` 下的旧 realcopy 日志与 `.xcresult` | 前序真库验收残留，可能含本机路径与测试元数据 | 由所有者确认后安全删除，不提交 |
| `LICENSE` | 当前没有许可证 | 所有者决定，不能由本轮擅自选择 |

## 14. 残留风险与待确认事项

### 高优先级

1. **Release 仍是 ad-hoc 签名，且没有 App Sandbox entitlement。** 已确认 Release 有 Hardened Runtime、没有 `get-task-allow`、双架构签名有效；但没有 Apple Development/Distribution 身份、没有沙盒 entitlement，也没有公证。不能在正式分发前把当前 Release 当成已加固发行版。启用沙盒会改变 Application Support 路径，可能让用户看不到非沙盒库中的既有数据；必须先设计一次性迁移并取得所有者确认。
2. **真实库副本的临时验收残留。** 前序 Phase 05 在系统临时目录留下了 realcopy 日志和 `.xcresult`。审计未发现可读的真实任务正文、数据库或截图，但存在本机路径和测试元数据；这些文件可被本机其他用户读取。删除需要所有者确认，未执行。
3. **导入解码阶段的内存峰值。** 本轮增加了集合与总量上限，但 JSON 仍先完整解码再校验；128 MiB 文件仍可能造成高内存占用。没有实现流式解析。

### 中优先级

4. `TaskWorkspaceView` 的 Inbox/All 查询在 10k 任务下仍需 1.2–2.5 秒；`TaskListView` 在 body 中重复过滤/排序/搜索。`DashboardWorkspace` 的 revision 仍构建全量字符串数组，逾期查询也没有下界，这两项未在本轮修改。
5. 工作台 `WorkspaceBoardData` 与投影仍随每次 body 重建；本轮只移除了不使用的月历投影。
6. V4/V5 复用可变模型类，V4 未完全冻结；未来加字段前应先补齐冻结定义。
7. 标签删除后持久化筛选可能保留悬空 UUID；加载时忽略，但没有清理。
8. 提醒协调、备份导出/导入和部分日期格式化仍在主线程执行；长任务可能造成界面停顿。
9. UI 测试包含原生面板、坐标拖拽、固定等待和 TCC 对话框，存在环境相关不稳定；本轮没有改造。
10. 本地 Release 尚无隐私清单（Privacy Manifest），而设置页使用 UserDefaults；是否提交需要产品与发布决策。

### 低优先级

11. 6.7 MB 品牌主图、模板遗留文件、旧重复 `AgendaRows 2.swift`。
12. CI Action 固定到版本标签而非 commit SHA；GitHub Secret Scanning、Push Protection、分支保护状态未确认。
13. 仓库没有 LICENSE；`SECURITY.md` 不能提供不存在的私密邮箱。
14. README 仍以阶段叙述为主，文档索引可以后续补充；本轮只修正事实错误，没有大规模重排。

## 15. 构建与测试结果

### Debug 构建

```sh
xcodebuild build-for-testing \
  -project Selno.xcodeproj -scheme Selno \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/SelnoPhase055DD \
  -only-testing:SelnoTests
```

结果：**成功**（`** TEST BUILD SUCCEEDED **`）。

### 单元与性能测试

```sh
xcodebuild test-without-building \
  -project Selno.xcodeproj -scheme Selno \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/SelnoPhase055DD \
  -only-testing:SelnoTests
```

结果：**通过**。最终数量以本轮最后一次执行输出为准：143 个 Swift Testing 用例（21 个 Suite）+ 3 个 XCTest 性能用例，共 146 条，0 失败；Swift Testing 套件 21.066 秒，性能套件 3/3、75.455 秒。此前基线为 142 + 3 条，0 失败；新增导入上限测试后为 146 条。

### 过程中修复的崩溃

第一次实现收件箱手工谓词时，`PredicateExpressions.build_KeyPath` 使用了多段可选链键路径（`project?.id`），Foundation 在构造谓词时触发 `Predicate does not support keypaths with multiple components` 并终止测试进程。修复方式是先构造 `\.project`，再用 `PredicateExpressions.build_flatMap` 读取项目 `id`；`DashboardTests`、任务工作区测试和最终全量单元测试均通过。

第一次 UI 复跑出现 3 个失败。检查系统状态后发现原因是此前崩溃留下的“Selno 意外退出”系统恢复对话框覆盖了应用窗口，使 `isHittable` 和菜单点击被阻塞，而不是最终二进制再次崩溃。关闭该对话框后，使用同一最终构建重跑 UI；最终结果见下。这个失败没有被删除或改记为通过。

### UI 测试

```sh
xcodebuild test-without-building \
  -project Selno.xcodeproj -scheme Selno \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/SelnoPhase055DD \
  -only-testing:SelnoUITests
```

结果：**通过**。2026-10-22 在最终 Debug 构建（`/tmp/SelnoPhase055DD`）上执行全量 `SelnoUITests`：

```text
Executed 20 tests, with 0 failures (0 unexpected) in 910.386 seconds
** TEST EXECUTE SUCCEEDED **
```

结果为 **20/20 通过，0 失败**，耗时约 15 分 10 秒；结果包位于 `/tmp/SelnoPhase055FinalUI2.xcresult`。按测试类统计：`CalendarUITests` 3、`DashboardUITests` 3、`Phase03UITests` 4、`Phase04DataManagementUITests` 1、`Phase05UITests` 4、`SelnoUITests` 3、`SelnoUITestsLaunchTests` 2。第一次复跑的 3 个失败由陈旧系统崩溃恢复对话框遮挡窗口导致，关闭对话框后同一最终构建重跑为 0 失败；失败没有被删除或改记为通过。

### Release 构建与签名

```sh
xcodebuild build \
  -project Selno.xcodeproj -scheme Selno \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/SelnoPhase055ReleaseFinal
```

结果：**成功**（`** BUILD SUCCEEDED **`，2026-10-22，基于最终源码从空的 DerivedData 重建）。

| 检查 | 结果 |
| --- | --- |
| 架构 | `x86_64 arm64` 通用二进制 |
| `codesign --verify --deep --strict` | 通过（valid on disk / satisfies its Designated Requirement） |
| 签名标志 | `flags=0x10002(adhoc,runtime)` |
| Hardened Runtime | 已启用（`runtime`） |
| `get-task-allow` | 未嵌入 |
| App Sandbox entitlement | **未嵌入**；`codesign -d --entitlements :-` 输出为空 |
| Bundle Identifier | `com.yexiaonan.Selno`，未变 |
| App Category | `public.app-category.productivity` |
| Release 签名身份 | ad-hoc，`TeamIdentifier` 未设置 |
| Runtime Version | `26.2.0` |

Debug 的 entitlement 包含 sandbox、用户选择文件读写、`get-task-allow` 和测试专用 Mach lookup 例外；这是测试配置，不等同于 Release 发行配置。

### 未运行

- Instruments（Time Profiler、SwiftUI、Core Data/SwiftData、Allocations）；
- 真实窗口的 FPS、CPU、内存、冷/热启动、首次可交互；
- VoiceOver、Reduce Motion、仅键盘人工验收；
- 真实用户库迁移（只使用合成 Fixture）；
- GitHub Actions 云端执行结果（push 已触发 workflow；本轮未等待云端完成）。

## 16. 门禁结论、提交与推送结果

### 门禁结论

| 门禁 | 结论 | 依据与边界 |
| --- | --- | --- |
| Gate 1 安全 | **有条件通过** | 全历史凭据扫描未命中；未发现真实用户数据库/备份进入仓库；Release 无 `get-task-allow`；导入数量上限与测试隔离已补。Release 仍为 ad-hoc、无 App Sandbox entitlement，临时目录残留待所有者清理。 |
| Gate 2 仓库 | **通过** | `.gitignore`、`.gitattributes`、`CONTRIBUTING.md`、`SECURITY.md` 已补齐；`git diff --check` 通过；提交前 `git fetch origin` 成功，`origin/main` 与本地基线同为 `e4e3986`，无分叉；随后普通 push 快进到 `4261d29`，无强推。 |
| Gate 3 构建 | **通过（带发布警告）** | Debug `build-for-testing` 成功；最终源码的 Release 通用二进制从空 DerivedData 重建成功，`codesign --verify --deep --strict` 通过，Hardened Runtime 开启，`adhoc,runtime`，无 `get-task-allow`、无 entitlement。Release 的正式签名、沙盒与公证仍未完成。 |
| Gate 4 测试 | **通过** | 143 个 Swift Testing + 3 个 XCTest，共 146 条单元/性能测试 0 失败；迁移、备份、替换/回滚测试均通过。最终 Debug 构建的 UI 测试 **20/20 通过，0 失败**（910.386 秒）。 |
| Gate 5 性能 | **已测路径通过** | 有 100/1,000/10,000 合成数据基线；已记录优化前后与回归测试；未运行 Instruments、FPS、CPU、内存，不能声明端到端性能已验收。 |

结论：不能把本报告等同于正式发行签核。安全门禁没有发现需要轮换的凭据、真实用户数据或已泄漏数据库，但 Release 仍为 ad-hoc、无 App Sandbox entitlement、未公证；正式分发前必须由所有者完成签名、沙盒数据迁移与公证。

### 提交与推送

提交前已执行：

```sh
git status --short
git diff --check
git diff --stat
git fetch origin
git status -sb
```

结果与边界：

- `git diff --check` 通过；暂存与提交均按显式路径逐项加入，没有使用 `git add -A`。
- 提交前的一次 `git fetch origin` 成功，`origin/main` 为 `e4e3986`，与本地基线一致，无分叉。
- 首次推送尝试因网络中断失败：先报连接 `github.com:443` 超时，后报 `Could not resolve host: github.com`。文档提交后重试，普通 `git push origin main` 成功：远程从 `e4e3986` 快进到 `4261d29`，没有使用强制推送。
- 没有创建 tag 或 Release，没有使用强推、历史重写、远程分支删除或仓库权限修改。

本轮实际提交（按顺序）：

1. `19bad34` `chore: improve repository hygiene and documentation`
2. `2d4dcbd` `security: harden backup import and test storage`
3. `539ba4a` `perf: narrow measured dashboard and task queries`
4. `f4d5af4` `test: cover task workspace query scoping`
5. `a213b26` `ci: add macOS validation workflow`
6. `4261d29` `docs: complete Phase 05.5 audit report`（本报告与 README）
7. 本次推送结果修正提交：`docs: record Phase 05.5 push result`（哈希见最终 `git log`）

第 6 个提交首次推送后，报告中的“尚未推送”已不准确；本修正提交按普通提交追加，不改写已推送历史。最终 `origin/main` 以最后一次正常 push 为准。

本轮没有把任何凭据、真实任务内容或用户数据库写入提交信息、报告或 CI 日志。

---

## 附录：关键文件索引

- 仓库规范：`CONTRIBUTING.md`、`SECURITY.md`、`.gitignore`、`.gitattributes`
- CI：`.github/workflows/ci.yml`
- 测试隔离：`Selno/Persistence/PersistenceController.swift`、`SelnoTests/Phase055TestIsolationTests.swift`
- 查询：`Selno/Features/Dashboard/DashboardDataQuery.swift`、`Selno/Features/Tasks/TaskWorkspaceView.swift`
- 筛选：`Selno/Models/TaskFilterExpression.swift`
- 备份：`Selno/Backup/BackupCodec.swift`、`Selno/Backup/BackupModels.swift`
- 投影：`Selno/Features/Dashboard/DashboardProjection.swift`、`Selno/Features/Workspace/WorkspaceDataQuery.swift`
- 性能取证：`SelnoTests/Phase055PerformanceTests.swift`、`.build/phase055/perf-before.log`、`.build/phase055/perf-after2.log`
- 历史阶段：`Docs/Phase01-Report.md` 至 `Docs/Phase05-Report.md`