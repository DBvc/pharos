# Pharos MVP PRD v0.3

版本：v0.3
状态：v0.2 的产品心智对齐版，可作为后续 Codex 迭代的产品源头
目标用户：DBvc 本人
项目名：Pharos

## 0. v0.3 变更摘要

v0.3 不扩大 MVP 范围。v0.3 只把用户心智、页面语言、API DTO、迭代顺序与当前产品方向对齐。

v0.2 仍然定义大范围 MVP：本地优先、macOS App、OCaml core、SwiftUI UI、飞书聊天、飞书项目、私有 GitLab、飞书文档、Review Gate、Evidence、Timeline、Metrics。

v0.3 对 v0.2 做以下覆盖：

1. Today 默认不再使用 `Needs Review / Running / Needs Context / New / Done Today` 作为用户主分区。
2. Today 默认使用 `Needs Decision / Needs Input / Watching / Handled / Noise`。
3. `Proposed Action` 在用户界面中称为 `Prepared next move`。
4. Request Detail 按四个问题组织，而不是按内部实体表组织。
5. Merge identity 提前到真实 source 之前。
6. GitLab read-only adapter 先于飞书 source 进入真实集成。
7. 所有旧内部状态、风险等级、hash、approval、evidence、timeline 继续保留在 core。

## 1. 产品一句话

```text
Pharos watches work systems, prepares the next move, and asks before it acts.
```

中文：

```text
Pharos 帮你看住工作系统，整理证据、准备下一步；真正行动前一定问你。
```

用户心智：

```text
看住信号 -> 整理证据 -> 准备动作 -> 等我拍板 -> 执行留痕
```

## 2. 产品定位

Pharos 是一个 local-first 的 AI 工作塔台。它不应该变成另一个 inbox，也不应该变成一个需要用户每天维护状态的任务管理器。

Pharos 的日常价值是：

1. 看住配置过的工作系统。
2. 把散落信号过滤成少量真正需要处理的决策卡。
3. 在打扰用户前说明为什么这件事值得注意。
4. 准备一个具体下一步，而不只是提醒。
5. 外部写入前一定停下来等用户拍板。
6. 执行后留下证据和时间线。

## 3. v0.3 用户界面模型

用户看到的是 Decision Cockpit。

用户不需要理解这些内部词才能使用 Pharos：

```text
SourceSignal
WorkRequest
ProposedAction
Approval
payload_hash
request_status
policy gate internals
SQLite rows
adapter payloads
```

这些仍然是 core 的事实来源和审计结构，但不应该成为普通日常使用的主语言。

## 4. Today

Today 只回答一个问题：

```text
What needs my attention now?
```

Today 必须按用户注意力分组，而不是按完整内部生命周期分组。

| 用户分组 | 用户问题 | 内部示例 |
|---|---|---|
| Needs Decision | 我现在要批准、编辑、拒绝还是归档吗？ | `ReadyForReview` 且有 reviewable action |
| Needs Input | Pharos 缺什么才能继续？ | `NeedsContext`、缺权限、上下文抓取失败、需要用户补充 |
| Watching | Pharos 正在准备、等待或观察什么？ | `New`、`Triaging`、`Running`、`Waiting`、`Approved`、`Executing`、`Snoozed` |
| Handled | 今天已经处理了什么？ | `Done` |
| Noise | 哪些被过滤、归档或标记误报？ | `Archived`、false positive、ignored signal |

内部状态可以作为 filter、debug metadata、metrics 或 detail 中的二级信息保留。

### 4.1 Today Card 最小信息

每张 decision card 必须显示：

1. 标题。
2. 简短摘要。
3. 来源系统。
4. 为什么现在出现。
5. 准备好的下一步。
6. 风险的人类可读标签。
7. 证据数量。
8. 更新时间。
9. 原始来源入口。

### 4.2 Today API v0.3

`GET /v0/today` 返回：

```json
{
  "needs_decision": [],
  "needs_input": [],
  "watching": [],
  "handled": [],
  "noise": { "count": 0 }
}
```

不再返回旧顶层字段：

```text
needs_review
running
needs_context
new_items
done_today
archived_noise_count
```

若需要调试旧生命周期桶，新增 `/v0/debug/today-internal`，不要让 SwiftUI 默认消费它。

## 5. Request Detail

Request Detail 回答四个问题，顺序不能反过来：

1. What is this?
2. Why did Pharos bring it to me?
3. What evidence did Pharos use?
4. What exactly will happen if I approve?

详情页在要求用户批准前必须展示：

1. 来源系统和来源链接。
2. 普通语言摘要。
3. 进入原因。
4. 相关证据和上下文。
5. 准备动作正文或草稿。
6. 目标系统和目标对象。
7. 是否会写外部系统。
8. 风险的人类可读解释。
9. 可用操作：approve、edit and approve、reject、request more context、snooze、archive。

Timeline 和 payload hash 很重要，但默认应作为审计/诊断信息放在后面或折叠展示。

## 6. Review Gate

Review Gate 不是一个 approve 按钮。它是控制权回到用户手里的时刻。

Review Gate 必须明确三件事：

```text
what Pharos will do
where Pharos will do it
why this action is justified
```

用户操作：

1. Approve：按展示内容执行。
2. Edit and Approve：执行编辑后的内容，不是原草稿。
3. Reject：不执行该动作。
4. Request More Context：进入新的上下文收集流程。
5. Snooze：延后处理。
6. Archive：归档。
7. Mark False Positive：记录误报反馈并归档。
8. Disable Similar Automation：降低或关闭同类自动化。

## 7. 内部模型边界

core 继续保留以下内部模型：

```text
SourceSignal
WorkRequest
Evidence
ProposedAction
Approval
Timeline
risk levels
payload hashes
request statuses
action statuses
```

映射关系：

| 用户概念 | Core 概念 |
|---|---|
| watched signal | `SourceSignal` |
| decision card | `WorkRequest` + 当前 review 状态 |
| evidence used | `Evidence` + context bundle |
| prepared next move | `ProposedAction` |
| user decision | `Approval` 或 rejection decision |
| execution record | `Timeline` + action status |
| safety level | risk level + policy gate |
| ask before acting | approval hash verification before execution |

## 8. 安全不变量

这些不变量不能被任何 UI、adapter、skill 或便利性需求打破：

1. 所有外部写入必须有用户批准记录。
2. 所有外部写入必须校验 approval hash 等于当前 action payload hash。
3. L4/L5 在 MVP 中不可执行，只能生成建议。
4. skill 可以提议动作，但不能授权动作。
5. adapter 不能直接创建 approval，不能绕过 policy gate 写外部系统。
6. 用户必须知道批准后会写到哪里。
7. 进入 Needs Decision 的卡片必须有证据。
8. 失败不能静默吞掉，必须记录到 timeline 或 source status。
9. token、secret、authorization header、完整敏感 payload 不得进入日志、UI 或 metrics export。
10. 未审批外部写入次数必须保持为 0；被阻止的未审批尝试必须记录为 blocked attempt。

## 9. v0.3 迭代顺序

### Iteration 0: Docs and API mental-model alignment

产出：

1. `docs/PRD_v0.3.md`。
2. `docs/API.md` 更新 `/v0/today`。
3. `protocol/openapi.yaml` 更新 Today schema。
4. README 写清 docs 优先级。
5. SwiftUI 仍可编译。

验收：新旧文档不再互相打架。

### Iteration 1: DecisionCard DTO and Today mapping

产出：

1. OCaml `attention_group`。
2. OCaml `decision_card`。
3. OCaml `today_decision_snapshot`。
4. `/v0/today` 返回用户分组。
5. 可选 `/v0/debug/today-internal` 返回旧桶。

验收：M0 manual capture 出现在 `Needs Decision`。

### Iteration 2: Swift Today decision cockpit

产出：

1. Swift `DecisionCard` model。
2. Swift `TodaySnapshot` 新 shape。
3. Swift `TodayView` 用新分组。
4. Request selection 通过 `requestId` 加载 detail。

验收：UI 不再显示旧顶层 section。

### Iteration 3: Request Detail judgment view

产出：详情页按四问组织，payload hash 进入 audit details。

验收：用户不打开外部系统也能判断本地 M0 请求。

### Iteration 4: Policy safety tests

产出：补齐 approval、edit approval、reject、L4/L5、external target blocked 的测试。

验收：`dune runtest` 证明安全不变量。

### Iteration 5: Fake adapter replay and merge identity

产出：fixture replay、source signal endpoint、request identity、merge update。

验收：重复 replay 同一个 MR/thread 不产生重复 active card。

### Iteration 6: Source settings shell

产出：source 设置表、API、Swift Sources page。

验收：四类 P0 source 状态可见，写权限默认 off。

### Iteration 7: GitLab read-only adapter

产出：GitLab MR read-only sync、bounded context、evidence。

验收：测试 MR review request 进入 Pharos，同一 MR 更新同一 request。

### Iteration 8: Built-in skills v0

产出：triage、context summary、draft reply、GitLab MR review typed skill outputs。

验收：至少 3 类请求能自动推进到摘要、草稿或建议动作。

### Iteration 9: Controlled GitLab writeback

产出：批准后 GitLab comment 写回。

验收：未批准被阻止；编辑后批准写 edited body；timeline 可追溯。

### Iteration 10: Metrics and dogfood readiness

产出：7-day metrics、Markdown/JSON export、dogfood template。

验收：能进入 10 个工作日 dogfood。

## 10. v0.3 非目标

v0.3 不做：

1. 多用户。
2. 云同步。
3. 通用插件市场。
4. 自动改代码。
5. 自动合并 MR。
6. 自动改飞书文档正文。
7. 自动发布或线上配置修改。
8. 真实飞书写入，除非前置 GitLab writeback 已证明安全路径。
9. 让 SwiftUI 承担 triage、merge、risk 或 writeback policy。
