# Smart Shadow MVP PRD

## 1. 产品定位

Smart Shadow 是一个运行在 iPhone 和本地 Mac 上的智能影子系统。系统需要建立入口层：入口可以是用户在电脑或手机应用中的操作，例如显式的 AI 智能影子、加星、收藏、分享、标记；也可以是电脑上的菜单栏应用入口，或通过快捷键唤起的语音交互入口；也可以是手机上的轻应用，扫码绑定后即可唤起。用户通过语音交互后，最终路由回电脑上的 `shadowd`。`shadowd` 是运行在 Mac 上的系统服务，负责感知、连接、调度、跟踪和反馈；Codex 是决策大脑，负责在主线、Project、Issue / 事项三层哲学下完成任务理解、分解、规划和判断，并在对应项目 Thread 中调用本机软件推进。

它的核心不是聊天、项目管理系统、全量环境信号自动接管系统或主动社交代理，而是一个“如影随形”的入口层和电脑响应桥梁：用户通过手机轻应用、扫码绑定入口、Mac 菜单栏、快捷键语音、应用内 AI 智能影子、加星、收藏、保存、分享、GitHub `@shadow`、Mail、微信、浏览器或确认建议等明确动作表达意图后，入口层将事件路由回 `shadowd`；`shadowd` 将意图和上下文连接给 Codex；Codex 规整为 Project / Issue，决定执行路径，并在对应项目下创建或恢复 Thread，调用本机软件推进；最后由 `shadowd` 给用户创建反馈，反馈位置默认使用用户发布任务的平台渠道。

从实现形态看，Smart Shadow 是围绕 Codex 和本机系统服务的二次开发，而不是另起炉灶的通用 AI 助手。Codex 承接推理、任务分解、规划、项目 Thread 创建/恢复、本机软件调用、工具选择和解释；`shadowd` 承接显式入口接收、隐式意图监测、来源去重、上下文整理、Codex 连接、状态跟踪、反馈回传、反馈渠道映射和审计；Smart Shadow 通过 Agent 规约、正式文档、skills、本地 `shadowd` 服务、自动化边界和 Apple native app 桥接，把两者组织成能使用电脑软件管理人生主线、Project 和 Issue 的智能影子。

核心原则是：User writes intent. Shadow executes work.

阶段性产品原则是：Smart Shadow 优先跟进用户显式表达出的意图，也可以把授权范围内的本机应用变化作为隐式意图候选，但不替用户接管 Mail、微信、新闻、信息流、联系人、日历或文件系统里的全量环境事件。用户仍然主动面对外部内容和社交关系；隐式意图默认先进入记录、解释、补全、dry-run 或审核流程，不自动产生高风险外部动作。

核心设计抓手是三层哲学和两个运行角色：

1. Codex：决策大脑，承接用户意图、主线判断、Project / Issue 规整、优先级、风险、任务分解、规划、复盘、解释和目标软件选择。
2. `shadowd`：系统服务和桥梁，承接感知、连接、调度、跟踪、审计、恢复、反馈渠道映射和反馈创建。

四个人生主线是一套设计哲学，不要求全部放在同一个软件里管理。当前默认准则是：工作相关任务使用用户当前的 Feishu 平台，通过 Feishu CLI 使用 Feishu 的任务看板跟踪；生活相关任务使用 Apple Reminders，在 Reminders 的对应看板或列表中跟踪。GitHub 主要承载代码、PR、Issue、CI、开源反馈和 repo-centered execution；Calendar 主要承载时间块和节奏；Finder、Notes、Contacts、Photos、Music 承载对应资料和资产。具体载体仍由 Project 语义、协作场景、隐私风险和用户习惯决定，但偏离默认准则时需要能解释原因并保留 Project / Issue 映射。

## 2. MVP 产品定义

### 2.1 MVP 核心目标

用户可以用最少操作完成：

1. 从入口层表达一个想法/事项：手机轻应用、扫码绑定入口、Mac 菜单栏、快捷键语音、应用内 AI 智能影子、加星收藏、分享标记、Mail、浏览器、ChatGPT、GitHub、微信、Feishu、Finder、Calendar 等。
2. 入口层将语音和操作事件路由回电脑上的 `shadowd`；`shadowd` 感知显式或隐式意图，整理来源、上下文、去重键和风险线索。
3. Codex 识别人生主线、Project、Issue、优先级、风险、时间含义和目标软件，并在对应项目下创建或恢复 Thread。
4. 用户确认或规则允许后，Codex 在该项目 Thread 中调用本机应用、本地 Codex agent 或外部协作面推进事项。
5. 用户通过手机轻应用、Codex / shadow、本机应用或外部协作面查看状态、补充信息和验收结果。
6. 最后由 `shadowd` 创建反馈；反馈位置默认使用用户发布任务的平台渠道，同时结果在对应软件中保持 Project / Issue 内部身份和映射，避免重复、断链和不可追踪副本。

### 2.2 MVP 不做什么

MVP 阶段不做：

1. 不做完整 ChatGPT 聊天产品。
2. 不做替代 GitHub 的 Issue / PR / CI / Wiki 系统。
3. 不做复杂飞书工作台。
4. 不做多人协同项目管理平台。
5. 不做完整原型设计工具。
6. 不做复杂自动化工作流编排。
7. 不做独立代码托管或版本管理系统。
8. 不做大而全的信息流产品。
9. 不做全量环境信号自动接管系统。
10. 不做主动社交代理，不替用户回复、沟通或对外承诺。
11. 不做 Mail、消息、新闻、日历、联系人或浏览历史的全量事件源筛选。
12. 不默认开启 daemon sensing，不默认自动归档、删除、回复、转发或向外部系统写入。

## 3. 用户角色

### 3.1 用户

产品的主要使用者。通过 iPhone 语音输入任务，确认任务，查看进展，处理阻塞，验收结果。

### 3.2 shadow

统一的 agent 身份。对用户来说，所有任务都交给 shadow。

### 3.3 shadowd

运行在本地设备上的系统服务，是智能影子的感知和响应桥梁，而不是另一个大模型后端。它负责接收显式输入或 webhook、监测授权范围内的隐式意图、来源去重、上下文整理、维护 Project / Issue 映射、连接 Codex 完成任务分解和规划、桥接 Reminders、Calendar、Finder、Notes、Contacts、Photos、Music、Feishu、GitHub、Mail、微信等目标软件或外部接口、记录审计和健康状态、回写进展、必要时创建 branch/commit/PR。shadowd 不负责录音、音频存储、语音转写、用户身份写入或创建用户型 GitHub bot 账号。

技术路径上，shadowd 以 `smart-shadow` 项目作为任务承接和 dispatcher 入口，复用 Codex App 正在使用的 App Server，不启动或引入第二套 App Server。任务被解析后，shadowd 根据 Codex 的路由决策打开、恢复或创建目标项目下的合适 thread；Codex 在该项目 thread 中推进任务并调用本机软件；shadowd 保存 intake thread、目标 project、目标 thread、决策原因和反馈渠道映射。

### 3.4 Codex agent

具体承接用户意图、解释 Smart Shadow 规约、维护主线 / Project / Issue 三层哲学、分解任务、制定计划、选择工具并执行任务的本地 agent。用户不需要直接管理多个 Codex agent；Smart Shadow 的目标是让 Codex 在这些规约下表现为统一的 shadow。

## 4. Feature List

| Feature ID | Feature 名称 | MVP 是否包含 | 功能定位 |
|---|---|---:|---|
| F1 | 入口层 | 是 | 统一承接手机轻应用、扫码绑定、Mac 菜单栏、快捷键语音、应用内 AI 智能影子、加星收藏、分享标记等入口 |
| F2 | 语音转文字 | 是 | 将用户口述转为文本 |
| F3 | 意图识别 | 是 | 判断用户输入属于什么类型任务 |
| F4 | 任务规整 | 是 | 将自然语言整理为结构化任务 |
| F5 | 用户确认 | 是 | 投递前让用户确认任务内容 |
| F6 | 项目上下文识别 | 是 | 判断事项关联哪条人生主线和哪个 Project |
| F7 | 投递给 shadow | 是 | 将用户确认后的 Project / Issue 发送给统一 agent 身份 |
| F8 | 目标软件响应与同步 | 是 | 将 Project / Issue 更新到 Reminders、Calendar、Finder、Notes、Contacts、Photos、Music、GitHub、Feishu、Mail 等语义合适的软件表面 |
| F9 | shadowd 系统服务承接 | 是 | 本地服务感知、连接、调度、跟踪、反馈渠道映射和反馈 |
| F10 | Codex 决策与 agent 执行 | 是 | 将任务交给 Codex 完成分解、规划、项目 Thread 推进和本机软件调用 |
| F11 | 执行进展回写 | 是 | 将阶段性进展回写到 Project / Issue，并按需要同步到外部协作面 |
| F12 | 外部协作记录创建与关联 | 是 | 代码变更、团队协作或外部反馈需要时创建 GitHub PR/Issue、Feishu 文档或 Mail 跟进 |
| F13 | App 任务状态展示 | 是 | 用户查看任务进行到哪一步 |
| F14 | Push 通知 | 是 | 关键状态变化时提醒用户 |
| F15 | 信息流刷新 | 是 | 展示近期任务和状态变化 |
| F16 | 任务完成确认 | 是 | 用户查看结果并完成闭环 |
| F17 | 飞书项目资料拉取 | 部分包含 | 仅作为管理型资料来源，不做复杂飞书工作台 |
| F18 | 本地目录策略 | 是 | 区分管理型项目与开发型项目 |
| F19 | GitHub 替代系统 | 否 | MVP 不自建 Issue / PR / CI / Wiki |
| F20 | 多人协作后台 | 否 | MVP 聚焦个人 shadow 工作流 |
| F21 | 意图来源适配器 | 是 | 接收入口层事件、用户标记、收藏、保存、分享、确认后的输入或授权范围内的隐式候选 |

## 5. 功能定义

### F1. 入口层

Smart Shadow 需要一个统一入口层，而不是只有单一手机按钮。

入口可以来自：

1. 用户在电脑或手机应用中的操作，例如显式的 AI 智能影子、加星、收藏、分享、标记、对某个对象说“交给 shadow”。
2. 电脑上的菜单栏应用入口。
3. 通过快捷键唤起的语音交互入口。
4. 手机上扫码绑定后的轻应用入口。

用户通过语音交互后，最终路由回电脑上的 `shadowd`。入口层负责捕捉来源、用户动作、语音/文本、目标对象、应用上下文和反馈渠道；`shadowd` 负责把这些输入连接到 Codex。

### F2. 语音转文字

App 优先复用或抽象本地 ChatType Runtime 将用户语音转为文字，并保留原始语义。原始语音只允许在 iOS/macOS 本地短暂缓存，不上传 GitHub、不进入 shadowd、不进入云端中转。

语音转文字结果不直接成为任务，而是先进入本地 ChatType Polish、意图识别和任务规整，再由用户确认或编辑。

### F3. 意图识别

系统需要识别用户输入的任务类型。

MVP 阶段至少支持以下意图：

| 意图类型 | 定义 |
|---|---|
| 开发任务 | 需要修改代码、创建 PR、运行测试的任务 |
| 产品任务 | 需要输出方案、PRD、交互流程、设计说明的任务 |
| 项目管理任务 | 需要整理计划、同步进度、拆分任务的任务 |
| 资料整理任务 | 需要从已有项目资料中整理、归纳、总结的任务 |
| 补充说明 | 用户对已有任务追加上下文 |
| 任务查询 | 用户询问某个任务当前状态 |
| 完成确认 | 用户确认任务结果可接受 |

### F4. 任务规整

App 将用户的自然语言整理为结构化任务卡片。

任务卡片至少包含：

| 字段 | 定义 |
|---|---|
| 任务标题 | 一句话描述任务 |
| 任务类型 | 开发 / 产品 / 管理 / 资料整理等 |
| 关联项目 | 对应 repo、文档项目或管理型项目 |
| 背景信息 | 用户口述中的上下文 |
| 目标产出 | 希望 shadow 输出什么 |
| 验收标准 | 什么情况下算完成 |
| 优先级 | 默认普通，可由用户语音指定 |
| 是否需要 PR | 开发类任务通常需要 |
| 是否需要用户确认 | 默认需要 |

### F5. 用户确认

任务投递前，App 展示规整后的任务内容。

用户可以：

1. 确认投递。
2. 重新说一遍。
3. 追加说明。
4. 修改任务标题或目标。
5. 取消任务。

MVP 不要求复杂编辑器，优先通过语音补充和少量文本编辑完成确认。

### F6. 项目上下文识别

系统需要判断任务属于哪个项目。

MVP 的项目上下文来源包括：

1. 用户语音中明确提到的项目名。
2. 最近活跃项目。
3. 当前页面上下文。
4. GitHub repo 列表。
5. 本地 shadowd 已知项目映射。
6. 飞书拉取到的管理型项目资料。

项目上下文不明确时，App 只做最小确认，不进入复杂选择流程。

### F7. 投递给 shadow

用户确认后，App 以用户本人 GitHub 身份创建 issue 或 issue comment。GitHub 上表达的是“这是用户本人发起的任务 / 补充说明 / 回复”。

对用户来说，不需要选择具体 Codex agent，也不需要理解本地调度细节。

### F21. 意图来源适配器

Smart Shadow 的入口不是所有外部事件，而是用户的明确动作和授权范围内的隐式意图候选。MVP 允许的入口包括：

| 入口 | 显式动作 | 后续处理 |
|---|---|---|
| 语音任务 | 用户通过手机轻应用、Mac 菜单栏或快捷键说出任务 | 本地转写、任务规整、用户确认后路由回 Mac 上的 shadowd |
| Mac 菜单栏 | 用户从菜单栏唤起 Smart Shadow | 创建本机入口事件，可进入语音、文本或当前上下文任务 |
| 快捷键语音 | 用户按全局快捷键后说出任务 | 本地语音交互后路由回 Mac 上的 shadowd |
| 手机轻应用 | 用户扫码绑定后在手机上唤起 | 作为移动入口采集语音/文本/补充说明，最终路由回 Mac 上的 shadowd |
| 应用内 AI 智能影子 | 用户点击应用内可见的 AI 智能影子入口 | 绑定当前对象和应用上下文，生成显式任务候选 |
| 加星/收藏/分享/标记 | 用户在电脑或手机应用中执行明确操作 | 作为显式意图入口，提取目标对象和期望动作 |
| Mail | 用户标记、转发、分享、选择某封邮件，或确认 mail decision | 将邮件 thread 作为外部事项候选，归入某个 Project 并创建/更新 Issue；必要时再投影到 Reminders、Calendar、Finder、Notes、GitHub、Feishu 或 Mail 跟进 |
| 收藏文章 | 用户收藏文章 | 生成阅读、总结、调研或响应跟进草稿 |
| 添加书签 | 用户保存链接/书签 | 作为保存链接后的跟进，不分析全量浏览历史 |
| 分享内容 | 用户通过系统分享入口发送给 Smart Shadow | 提取目标、背景、链接和期望动作，等待确认 |
| 项目文件夹 | 用户在已映射 Project 文件夹下创建或修改文件 | 生成隐式事项候选、补全上下文、询问是否需要跟进 |
| Calendar | 用户创建或调整日程 | 生成时间语义候选，可建议补充地点、材料、提醒或关联 Project |
| 微信文件传输助手 | 用户向文件传输助手发送文本、文件或链接 | 作为个人输入候选，先整理并等待确认，不自动对外发送 |
| Feishu | 用户发送、标记、分配或在规则范围内暴露事项 | 作为工作 Project 候选，可落在 Feishu 管理，但高风险写入需授权 |
| GitHub | 用户创建 issue/comment 或明确 `@shadow` | 由 shadowd 接收并进入执行闭环 |
| 系统建议 | 系统生成待处理建议后用户确认 | 才能进入 follow-up pipeline |

每个输入至少记录：

| 字段 | 定义 |
|---|---|
| origin.user_action | 用户触发输入的明确动作，可为空 |
| origin.intent_mode | `explicit` 或 `implicit_candidate` |
| source | 来源适配器，如 voice、mail_marked、bookmark_saved、share_extension、github_comment |
| captured_at | 捕捉时间 |
| payload | 被用户选择或确认的内容 |
| requires_confirmation | 是否需要投递前确认 |
| user_approved | 用户是否已经确认 |
| follow_up_task_id | 后续任务 ID，可为空 |

只有存在明确 `origin.user_action`，或 `user_approved=true` 的输入，才能进入执行型 follow-up pipeline。`implicit_candidate` 可以进入记录、解释、补全、dry-run、建议或审核流程，但不能触发提醒、归档、删除、回复、转发、对外承诺或共享系统写入，除非规则明确允许且风险等级满足自动执行边界。

### F8. 目标软件响应与同步

用户确认后的 Project / Issue 应由 `shadowd` 连接到 Codex，由 Codex 判断需要更新哪些目标软件。Reminders、Calendar、Finder、Notes、Contacts、Photos、Music、GitHub、Feishu、Mail、微信等都是可选入口、上下文、执行、协作或反馈表面，而不是统一强制的核心管理本体。

Feishu 是当前工作任务默认跟踪面：工作相关 Project / Issue 默认通过 Feishu CLI 落到 Feishu 任务看板，除非该事项本质上是代码、PR、CI、开源反馈或 repo-centered execution。Reminders 是当前生活任务默认跟踪面：生活相关 Project / Issue 默认落到 Reminders 的对应看板或列表。Calendar 只承载会议、预约、时间块、截止点、里程碑和节奏。Finder 承载项目文件和工作产物，Notes 承载轻量知识和资料入口，Contacts / Photos / Music 承载对应的人和媒体资料。所有目标软件都必须保留 Project / Issue 内部身份和映射。

开发型任务、开源反馈、代码 review 或外部协作任务，可以创建或更新 GitHub Issue / Comment / PR 作为外部投影记录。GitHub Issue 不是 Smart Shadow 的核心管理本体。

Issue / Comment 只承载用户确认后的最终文本任务和紧凑来源元数据，不承载原始音频、音频路径、临时录音仓库或未整理的长原始转写。

Issue 中至少包含：

1. 任务标题。
2. 背景说明。
3. 目标产出。
4. 验收标准。
5. 关联项目 / repo。
6. 来源：Smart Shadow。
7. 执行者：shadow。
8. 当前状态 label。

### F9. shadowd 系统服务承接

shadowd 是本地系统服务，是感知、连接和反馈的媒介、中介、桥梁。

它负责：

1. 接收手机轻应用、GitHub webhook、Feishu、Mail、微信、Finder、Calendar 等入口中的显式任务。
2. 在授权范围内轮询或监测本机应用，生成隐式意图候选。
3. 保留来源、时间、置信度、去重键、上下文和风险线索。
4. 识别由 Smart Shadow 创建或接入的 Project / Issue。
5. 将任务送入 `smart-shadow` 项目的 dispatcher/intake thread，并连接 Codex 完成分解和规划。
6. 通过复用的 Codex App Server 打开、恢复或创建目标项目下的合适 thread。
7. 让 Codex 在目标项目 thread 中调用目标软件或本地 Codex agent 执行允许的动作。
8. 记录执行状态、审计日志、映射关系和反馈。
9. 以 Shadow bot 身份或对应授权身份创建用户反馈；反馈位置默认使用用户发布任务的平台渠道，也可以按规则同步到 GitHub、Feishu、Mail、App 或本机软件表面。

### F10. Codex 决策与 agent 执行

Codex 是决策大脑，Codex agent 是实际执行者之一。

MVP 阶段，用户不直接管理多个 agent。`shadowd` 根据入口来源、任务所属 repo、任务类型、当前执行状态和 Codex dispatcher 路由结果，打开、恢复或创建目标项目的 Codex thread。Codex 应在该项目 thread 中调用合适的本地 Codex agent 或本机应用动作推进任务；`smart-shadow` dispatcher thread 只负责 intake、解析和分发，除非任务只是低风险直接回复。

### F11. 执行进展回写

agent 执行过程中的阶段性进展，应优先写入 Issue comment。

Issue comment 用于：

1. 已开始执行。
2. 当前理解。
3. 阶段性总结。
4. 遇到阻塞。
5. 需要用户补充信息。
6. 已创建 PR。
7. 执行完成摘要。

### F12. PR 创建与关联

当任务产生代码变更，并且达到可 review 状态时，agent 创建 Pull Request。

PR 用于：

1. 展示代码修改。
2. 展示 summary。
3. 展示测试结果。
4. 关联原 Issue。
5. 支持用户 review 和 merge。

阶段性汇报不应都创建 PR。PR 只在有明确代码变更、可 review、可合并时创建。

### F13. App 任务状态展示

App 中需要展示任务当前状态。

MVP 状态模型：

| 状态 | 定义 |
|---|---|
| Draft | 已识别但未投递 |
| Submitted | 已投递给 shadow |
| Queued | shadowd 已接收，等待执行 |
| Running | Codex agent 正在执行 |
| Need Input | 需要用户补充信息 |
| PR Ready | 已创建 PR，等待 review |
| Done | 已完成 |
| Failed | 执行失败 |
| Cancelled | 用户取消 |

### F14. Push 通知

Push 只用于关键状态变化，不做高频打扰。

MVP 需要通知：

1. 任务需要用户补充信息。
2. PR 已创建。
3. 任务已完成。
4. 任务失败。
5. 长时间阻塞。
6. 用户明确关注的任务有更新。

### F15. 信息流刷新

App 信息流展示最近任务和关键状态变化。

信息流不是社交 feed，也不是知识流，而是用户与 shadow 的任务流。

刷新策略：

1. App 打开时刷新。
2. 用户下拉时刷新。
3. Push 点击进入时刷新相关任务。
4. 任务状态变化时局部刷新。
5. 后台只同步关键状态，不做高频轮询。

### F16. 任务完成确认

任务完成后，用户可以查看结果。

结果可能是：

1. PR。
2. Issue comment 总结。
3. 文档输出。
4. 产品方案。
5. 项目计划。
6. 执行失败说明。

用户可以选择：

1. 确认完成。
2. 要求修改。
3. 追加新任务。
4. 关闭任务。

### F17. 飞书项目资料拉取

MVP 可支持从飞书拉取管理型项目资料，但不把飞书做成主要交互入口。

飞书资料进入本地管理型项目目录，用于作为任务上下文。

### F18. 本地目录策略

Smart Shadow 遵循两类目录：

| 目录 | 用途 |
|---|---|
| ~/Documents | 存储从飞书等来源拉回来的管理型项目，并同步到 iCloud |
| ~/Projects | 存储从 GitHub clone 的开发型项目，用 Git 管理版本 |

开发型项目不建议放在 iCloud Drive / Documents 下持续开发，避免与 Git、Codex、本地构建文件产生同步冲突。

## 6. 最小页面流

MVP 只需要 5 个核心页面。

### P1. 首页 / Shadow Button

功能：

1. 展示一个核心语音按钮。
2. 展示最近任务的简要状态。
3. 允许用户快速发起新任务。
4. 允许用户进入任务流。

页面目标：让用户随时把事情交给 shadow。

### P2. 语音输入页

功能：

1. 录音。
2. 展示实时或完成后的转写文本。
3. 支持重新录音。
4. 支持追加说明。
5. 进入任务规整。

页面目标：捕捉用户的自然语言任务。

### P3. 任务确认页

功能：

1. 展示规整后的任务卡片。
2. 展示识别出的任务类型。
3. 展示关联项目。
4. 展示目标产出和验收标准。
5. 用户确认投递或修改。

页面目标：避免错误任务被直接交给 agent 执行。

### P4. 任务详情页

功能：

1. 展示任务状态。
2. 展示执行进展。
3. 展示 Issue 链接。
4. 展示 PR 链接。
5. 展示阻塞问题。
6. 支持用户补充说明。
7. 支持确认完成或要求修改。

页面目标：承载单个任务从投递到完成的闭环。

### P5. 任务流 / 信息流页

功能：

1. 展示所有近期任务。
2. 按状态展示任务。
3. 展示 shadow 的关键更新。
4. 支持点击进入任务详情。
5. 支持刷新。
6. 支持从 Push 落地到对应任务。

页面目标：让用户知道 shadow 当前在做什么、做完了什么、卡在哪里。

## 7. 核心交互流程

### Flow A：首页语音发起开发任务

1. 用户打开 App。
2. 点击首页 Shadow Button。
3. 用户语音描述开发任务。
4. App 转写语音。
5. App 识别为开发任务。
6. App 规整为任务卡片。
7. App 识别关联 repo。
8. 用户确认投递。
9. App 以用户本人 GitHub 身份创建 GitHub Issue。
10. shadowd 通过 webhook 接收 Issue。
11. shadowd 拉取最终文本任务。
12. shadowd 分配给 Codex agent。
13. agent 开始执行，并在 Issue comment 中写入开始状态。
14. App 任务状态变为 Running。
15. agent 完成代码修改后创建 PR。
16. App 收到 PR Ready 通知。
17. 用户查看 PR。
18. 用户确认完成或要求修改。
19. 任务关闭或进入下一轮修改。

### Flow B：首页语音发起产品 / 文档任务

1. 用户点击 Shadow Button。
2. 用户语音描述要产出的 PRD、计划或交互流程。
3. App 转写并识别为产品任务。
4. App 规整为任务卡片。
5. 用户确认任务目标和产出格式。
6. App 以用户本人 GitHub 身份创建或更新 Issue。
7. shadowd 分配给合适的 agent。
8. agent 输出文档或方案。
9. 执行进展写入 Issue comment 或任务记录。
10. App 通知用户任务完成。
11. 用户查看结果。
12. 用户确认完成或追加修改要求。

### Flow C：从任务详情追加说明

1. 用户打开某个任务详情页。
2. 用户点击补充说明入口。
3. 用户语音追加上下文。
4. App 将补充内容规整为任务 comment。
5. 用户确认。
6. App 以用户本人 GitHub 身份将补充说明写回 Issue comment。
7. shadowd 感知补充信息。
8. agent 继续执行。
9. App 更新任务状态。

### Flow D：从 Push 进入阻塞任务

1. agent 执行时遇到问题。
2. agent 在 Issue comment 中写明阻塞点。
3. 任务状态变为 Need Input。
4. App 发送 Push。
5. 用户点击 Push。
6. App 进入对应任务详情页。
7. 用户查看问题。
8. 用户语音补充说明。
9. App 以用户本人 GitHub 身份写回补充信息。
10. agent 继续执行。

### Flow E：从信息流查看任务进展

1. 用户打开 App。
2. App 刷新任务流。
3. 用户看到多个任务状态。
4. 用户点击某个任务。
5. 进入任务详情页。
6. 查看最近进展、Issue comment、PR 状态。
7. 用户决定是否补充、确认完成或继续等待。

### Flow F：任务完成与验收

1. agent 完成任务。
2. 若有代码变更，创建 PR。
3. 若无代码变更，写入完成总结。
4. 任务状态变为 Done 或 PR Ready。
5. App 通知用户。
6. 用户进入任务详情页。
7. 用户查看结果。
8. 用户选择确认完成、要求修改或追加新任务。
9. 系统更新 Issue / PR 状态。
10. 任务闭环结束。

### Flow G：标记重要邮件后的跟进

1. 用户在 Mail 或自动化审核界面中明确标记某封邮件重要。
2. 适配器生成带 `origin.user_action=mark_mail_important` 的输入。
3. Smart Shadow 提取发件人、主题、摘要、风险和建议动作。
4. App 展示待确认任务卡，不自动回复、转发、归档或承诺。
5. 用户确认后，Codex / shadowd 创建 Project / Issue，并按需要投影到 GitHub、Reminders、Calendar、Finder、Notes 或 Mail 跟进。
6. shadowd 只跟进用户确认后的文本任务。

### Flow H：收藏文章 / 添加书签 / 保存链接后的跟进

1. 用户收藏文章、添加书签、保存链接或通过 share sheet 分享到 Smart Shadow。
2. 适配器记录 `origin.user_action=save_link`、链接、标题、来源和捕捉时间。
3. Smart Shadow 将内容整理为阅读、总结、调研、购买比较或响应跟进草稿。
4. 用户确认是否跟进以及希望的产出。
5. 确认后才创建 Project / Issue，并按需要投影为 GitHub Issue / Comment、本地提醒、阅读资料、笔记或项目文件。
6. Bookmark 语义只代表用户保存链接后的跟进，不代表全量浏览历史分析。

## 8. GitHub 工作流规则

### 8.1 Issue 的角色

Project / Issue 在 Codex 中是用户可见的核心处理对象。GitHub Issue 是开发、开源反馈、代码 review 或外部协作场景下的投影记录。

所有需要追踪的任务都应该有 Project / Issue 内部身份和投影映射。开发任务默认可以创建 GitHub Issue，但不得因此绕过 Codex 的主线、Project、Issue 处理语义。

### 8.2 Issue comment 的角色

Issue comment 用于进展汇报。

适合写入：

1. 开始执行。
2. 当前理解。
3. 阶段性总结。
4. 阻塞点。
5. 用户补充信息。
6. PR 链接。
7. 完成总结。

### 8.3 PR 的角色

PR 只用于代码变更已达到可 review 状态的情况。

不应为了每一次阶段性进展都创建 PR。

### 8.4 Issue 与 PR 的关联

PR 必须关联原 Issue。

Issue comment 中应写入 PR 链接，并说明当前 PR 的目的、修改范围和 review 状态。

### 8.5 看板状态

GitHub Issue 看板应体现 agent 执行状态。

建议状态包括：

1. New。
2. Assigned to shadow。
3. In Progress。
4. Need Input。
5. PR Ready。
6. Done。
7. Failed。

## 9. 数据对象定义

### 9.1 Task

Task 是 App 内部的核心对象。

字段包括：

| 字段 | 定义 |
|---|---|
| task_id | App 内部任务 ID |
| title | 任务标题 |
| type | 任务类型 |
| status | 当前状态 |
| project_id | 关联项目 |
| repo | 关联 GitHub repo |
| issue_url | GitHub Issue 地址 |
| pr_url | Pull Request 地址 |
| transcript | 本地语音转写文本，仅用于 App 内确认和纠错，不作为 GitHub 原始转写区块 |
| structured_brief | 规整后的任务说明 |
| acceptance_criteria | 验收标准 |
| created_at | 创建时间 |
| updated_at | 更新时间 |

### 9.2 Project

Project 表示一个可被 shadow 识别的项目。

字段包括：

| 字段 | 定义 |
|---|---|
| project_id | 项目 ID |
| name | 项目名称 |
| type | 管理型项目 / 开发型项目 |
| local_path | 本地路径 |
| github_repo | GitHub repo |
| source | GitHub / 飞书 / 手动创建 |
| active | 是否活跃 |

### 9.3 Agent Run

Agent Run 表示一次具体执行。

字段包括：

| 字段 | 定义 |
|---|---|
| run_id | 执行 ID |
| task_id | 关联任务 |
| agent | 执行 agent |
| status | 执行状态 |
| started_at | 开始时间 |
| finished_at | 结束时间 |
| summary | 执行总结 |
| issue_comment_url | 进展 comment |
| pr_url | 关联 PR |

### 9.4 ExplicitIntentSignal

ExplicitIntentSignal 是所有非语音入口进入 follow-up pipeline 前的统一输入对象。

字段包括：

| 字段 | 定义 |
|---|---|
| source | 来源适配器名称 |
| origin.user_action | 用户明确动作 |
| captured_at | 捕捉时间 |
| payload | 用户选择、保存、标记、分享或确认的内容 |
| requires_confirmation | 是否需要确认 |
| user_approved | 用户是否已确认 |
| follow_up_task_id | 已生成任务 ID |

缺少 `origin.user_action` 且未被用户确认的输入不能触发 follow-up 动作。

## 10. MVP 成功标准

MVP 成功的判断标准不是功能数量，而是是否形成稳定闭环。

### 10.1 用户体验成功标准

1. 用户可以在 10 秒内发起一个任务。
2. 用户不需要理解 GitHub / Codex / shadowd 的内部细节。
3. 用户能清楚知道任务是否已开始、是否卡住、是否完成。
4. 用户可以通过语音补充任务信息。
5. 用户能从 App 回到 PR / Issue 查看结果。

### 10.2 系统闭环成功标准

1. 语音可以变成结构化任务。
2. 结构化任务可以创建或更新 GitHub Issue。
3. shadowd 可以接收任务。
4. Codex agent 可以执行任务。
5. 执行进展可以回写 Issue comment。
6. 代码变更可以创建 PR。
7. App 可以展示任务状态。
8. Push 可以提醒关键节点。
9. 用户可以完成验收。

## 11. MVP 范围总结

Smart Shadow MVP 的本质是：

一个 iPhone 轻量任务入口，加上一个运行在 Mac 上的 `shadowd` 系统服务和统一 agent 身份 shadow：`shadowd` 感知显式与隐式意图，Codex 按主线、Project、Issue / 事项三层哲学进行分解和规划，并在对应项目下创建或恢复 Thread 调用 Reminders、Calendar、Finder、Notes、GitHub、Feishu、Mail、微信等目标软件推进；最后由 `shadowd` 创建用户反馈，默认回到用户发布任务的平台渠道，形成可执行、可追踪、可验收的工作闭环。

MVP 的核心价值不是替代现有工具，也不是接管全量环境信号，而是把“用户在手机或电脑上表达出的意图”到“Codex 完成决策、shadowd 使用电脑软件推进并持续回报”的路径压缩到最短。
