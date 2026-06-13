# Smart Shadow Agent Rules

本文件是 Smart Shadow 的实现宪章，面向后续在本仓库工作的 Codex/Agent。README 和 `docs/` 负责公开项目说明、架构、运维和安全文档；本文件只保留会影响实现取舍的长期规则。

## Product Intent

Smart Shadow 是 iPhone-first 的个人任务入口 App，加上运行在本地 Mac 上的 `shadowd` 执行闭环。目标是用最少操作完成“语音输入 -> 任务规整 -> 用户确认 -> shadow 执行 -> GitHub Issue/PR/Comment 追踪 -> App 反馈 -> 用户验收”。

它的核心不是聊天、项目管理系统、Feishu 工作台或 GitHub 替代品，而是一个“如影随形”的极简任务入口。用户只需要把任务交给统一 agent 身份 `shadow`；`shadowd` 再负责承接任务、分配给本地 Codex agent、回写进展并形成可追踪闭环。

当前 GitHub 与语音链路的核心原则是：User writes intent. Shadow executes work. 原始语音只在 iOS/macOS 本地短暂缓存并处理，不上传 GitHub、不进入 `shadowd`、不进入云端中转；GitHub Issue / Comment 只承载用户确认后的最终文本任务。

系统应优先服务四条人生主线：

- 健康：睡眠、运动、饮食、心理和认知质量。
- 搞钱：收入、成本、财务风险、可执行副业机会。
- 关系：亲情、爱情、友情、协作关系和低内耗沟通。
- 工作：推进关键项目、降低沟通成本、提升交付质量、沉淀复用能力。

Smart Shadow 的 Reminders 看板应同时吸收 GTD 和四象限工作法。四个长期列表承载人生主线；每个列表内部统一使用四个栏目：

- `IMPORTANT`：对安身立命重要、需要长期规划和复盘的事项。
- `URGENT`：需要立即处理、阻塞当前节奏或有明确时限的事项。
- `DOING`：正在推进、需要持续关注但不应重复生成的新事项。
- `TODO`：待处理、待分派、待确认或可交给别人处理的事项。

无法归入这些方向、或没有明确正向投入产出比的事项默认降级，不要制造新的噪音和中间产物。

## Architecture Rules

- 主实现保持 Swift-native：iOS App 是主要产品入口，Mac 上的 `shadowd` 是本地长期服务；不要重新引入 Python 服务层、Python CLI 或 Python 常驻进程。
- `shadowd` 应作为 macOS 用户级长期服务运行，具备启动、停止、健康检查、日志、状态快照和崩溃恢复路径。
- MVP 的主记录是 GitHub Issue / Comment / PR。App 内 Draft 只有在用户确认后才投递给 `shadow` 并创建或更新 GitHub 记录。
- iOS/macOS 前端负责 GitHub 登录、默认任务仓库选择、录音、本地短暂音频缓存、本地 ChatType Runtime 转写、本地 ChatType Polish 润色、用户确认/编辑，以及用用户本人 GitHub 身份创建 issue 或 comment。
- 前端只能写用户本人明确发起的 GitHub 内容：新任务 issue、补充说明 comment、用户回复 Shadow 问题的 comment；前端不负责 agent 调度、任务执行、branch/commit/PR 创建、Shadow 进展汇报、原始音频上传或云端语音处理。
- `shadowd` 只负责自动化执行和 Shadow GitHub App bot 身份回写：接收 webhook、识别 Smart Shadow 创建的 issue/comment、读取最终文本任务、更新 title/labels、评论已接收和执行计划、分配本地 Codex、执行任务、创建 branch/commit/PR、持续追加进展并更新状态。
- `shadowd` 不负责录音、音频存储、语音转写、用户身份写入或创建用户型 GitHub bot 账号。
- PR 只用于已经达到可 review 状态的代码变更；阶段性进展、阻塞、补充说明和完成总结优先写 Issue comment。
- 优先事件驱动、系统通知、应用官方接口、网页回调、文件变更监听和消息队列；定时扫描只能作为补偿机制。
- 模块职责要清晰：iOS 入口、语音转写、意图识别、任务规整、用户确认、GitHub 任务记录、`shadowd` 调度、Codex agent 执行、App 状态同步、模型路由器、审计日志、CLI 控制面和 launchd 配置。
- 任何自动化都必须能 dry-run、能回放、能解释、能停机。
- 先识别已有能力，再新增系统；优先复用本仓库已有 Swift 代码、规则、测试、配置和正式文档。
- Feishu 进入的 Codex main session 默认创建在 Smart Shadow 项目；dispatcher 只做路由决策，实际工作仍按任务归属分发到合适项目或线程。
- Smart Shadow 是用户与 Codex 定义、沉淀和迭代工作流规则的主场；已确认规则应进入本文件、正式 docs、可发布 skill 或可测试代码，而不是停留在临时聊天记录。

## iOS Development and Acceptance

- iOS 开发测试链路必须先在 iOS Simulator 上完成 Codex 自测和交互验收，再交给用户做真机验收。
- Simulator 自测至少包括 fresh build、相关单元测试、安装启动、关键界面截图，以及本轮核心交互路径验证；不能只用 `xcodebuild` 成功替代交互验收。
- 只有 Simulator 自测通过后，才构建/安装到用户的 iPhone Air 或其他真机；真机阶段主要用于用户最终验收、设备权限、登录、音频输入、系统弹窗和真实外部服务闭环。
- 如果真机签名、provisioning、DDI、设备锁定或账号授权阻塞，不得把未通过 Simulator 交互验收的问题转嫁给用户；先收口 Simulator 可验证的问题，再报告真机阻塞。
- 涉及 GitHub OAuth token、Apple ID、2FA、个人账号或真机私密内容时，Codex 只能引导用户操作，不读取、不记录、不代填凭证。

## Apple Calendar and Reminders

- Calendar 和 Reminders 的生产路径必须优先使用 Swift + EventKit，包括 `EKEventStore`、`EKEvent`、`EKReminder` 和官方权限授权流程。
- 禁止直接写 Apple Calendar / Reminders 本地数据库。直接数据库只读最多作为受控迁移诊断。AppleScript 只能作为临时诊断或兜底，不是长期产品路径。
- Reminders 是可完成事项表面：审核卡、待办、跟进、授权、阻塞处理、复盘任务和无固定时间段的行动。
- Calendar 是时间占用表面：会议、预约、明确开始结束时间的工作块、健康作息、关键截止点、里程碑和当天需要看到的时间安排。
- Reminders 的列表维度表示人生主线，栏目维度表示处理状态和优先级象限；不要用四象限替代四条人生主线列表。
- Calendar 不承载 GTD 或四象限栏目语义，只承载明确时间窗口、里程碑和时间占用。
- 与 Reminders 交互采用分层控制面：P0 内部语义和审计状态留在 Smart Shadow；P1 生产写入只走 Swift + EventKit；P2 AppleScript 只做脚本字典明确暴露的小范围补充；P3 原生 section/column 只通过 Reminders App UI 或受控 Accessibility 验收；P4 私有 ReminderKit 和 SQLite 只做只读诊断。
- 不得用标题前缀、备注元数据或伪列表冒充 Reminders 原生 section；不得直接写 Reminders SQLite、CloudKit 状态、WAL 或私有变更队列。
- 同一工作项必须有统一内部身份和投影映射；不得在 Calendar 和 Reminders 中制造互不关联的重复事项。
- 一个工作项可以同时投影到两者，但语义必须不同：Calendar 表示时间窗口，Reminders 表示需要完成的动作。
- 有 due date、priority、start/end time 等官方字段时，优先写原生字段；审计元数据留在内部日志，不塞进用户可见备注。
- Reminder 标题保持干净，不添加内部系统前缀；备注只写人类可读的任务描述、背景和建议动作。
- 每次调试或实现会写入 Calendar / Reminders 的新功能后，完成验收前必须打开对应 Apple 原生界面做视觉验证，确认本轮产生或更新的事件/提醒实际可见、字段合理且没有明显重复；CLI 输出、SQLite 记录、EventKit 返回值和截图只能作为辅助证据，不能替代这一步。
- 只要当前目标涉及 Calendar / Reminders 的真实投影、删除、修复或用户可见语义变更，在没有完成 Apple 原生界面交互验收前，禁止把 Goal 标记为 complete；最多只能报告“代码/测试预检查通过，等待交互验收”。

## Sensing and Rules

- 感知层尽量保留原始事件、来源、时间、置信度和去重键。
- 先用结构化采集和规则过滤降噪，不要过早让大模型解释一切。
- 对同一来源的重复信号要去重、合并、降噪。
- 规则库必须可维护、可验证、可审计；每条规则应说明范围、触发条件、默认动作、风险等级和是否需要用户确认。
- 规则冲突必须能解释优先级；规则更新要记录新增、修改或废弃原因。
- 涉及金钱、身份、隐私、账号、对外承诺、法律、医疗、人际关系敏感内容时，默认进入审核。
- 不允许为了完成任务绕开用户已经设定的安全边界。

## Actions and Review

- 低风险、可逆、规则明确且已授权的动作可以自动执行。
- 中高风险动作必须进入审核或授权流程，并准备简洁材料：背景、建议、影响、替代方案和默认推荐。
- 对外发送内容前，按风险等级、关系敏感度、承诺强度和用户授权决定是自动发送、起草待审，还是只生成建议。
- 不自动进行高金额支付、转账、投资、借贷或合同承诺。
- 不自动发送可能影响关系、声誉、法律责任或工作承诺的敏感消息。
- 不自动删除不可恢复数据，不自动公开发布私人内容，不绕过应用、网站、平台或公司的安全机制。
- 不要把随手完成的小事升级成看板任务。
- GitHub push、Feishu 写入、X 发帖和其他外部可见发布动作必须有明确授权；夜间维护可以准备 skill 更新和 X 文案草稿，但不能在缺少批准与成功发帖验收路径时自动发布。

## Model and Cost Policy

- 不要用一个大模型驱动所有工作。
- 结构化规则、轻量分类、去重和优先级判断优先用本地规则和小模型。
- 高上下文、低风险文本分析可以走低成本模型或已配置的本地桥接工具，但最终安全判断、代码编辑、浏览器验证和高风险决策仍由 Codex 主控。
- 图片、截图、票据、照片和混合文本图像理解可以走低成本多模态工具，但要先判断隐私和外发必要性。
- 不把 API keys、cookies、支付信息、浏览器凭证或供应商密钥写入仓库、日志、报告、截图或聊天可见文本。
- 私人文件、照片、聊天记录和邮件全文不得批量发给第三方模型，除非当前任务明确需要且已经说明外发风险。

## Evidence and Reporting

- 技术日志和用户报告分离：用户报告讲结果和判断，技术日志用于排错和审计。
- 运行证据保存在忽略的本地 runtime 目录，例如 `var/`；不要把运行报告、SQLite 状态、审计 JSONL 或个人数据提交进仓库。
- 规则、架构约定和安全边界沉淀到本文件或正式 docs；不要依赖临时聊天记录。
- 用户可见报告优先包含：本轮重要事项、需要审核的事项、规则变化、投入产出比、失败根因和下一步修复。

## Shipping

- Smart Shadow 是自有项目；完成验证后默认直接推送到远端 `main` 分支，不创建 PR，除非用户临时明确要求走 PR。

## Completion Standard

本项目功能只有满足以下条件才算完成：

- 能在真实本机环境运行。
- 有明确启动、停止、健康检查和日志位置。
- 能说明输入来源、决策依据、执行动作和结果。
- iPhone App 入口能完成语音任务捕捉、结构化任务确认、投递给 `shadow`、状态展示、补充说明和完成验收。
- GitHub Issue / Comment / PR 能承载任务主记录、执行进展、阻塞、PR 链接和完成摘要。
- 对用户可见的重要工作按语义同步到 Calendar 与 Reminders，并避免重复事项。
- 涉及 Calendar / Reminders 投影的变更，必须完成 Apple 原生 Calendar 或 Reminders 界面的视觉验收。
- 涉及 Calendar / Reminders 的 Goal 只有在原生界面交互验收完成后才能标记完成；仅有单元测试、CLI 验证、EventKit 返回值或 acceptance preview 不足以完成 Goal。
- 高风险动作进入审核流程。
- 成本、隐私和安全边界可解释。
- 至少有一个真实或接近真实的闭环案例完成验证。
- 回归测试和相关 CLI 验证已经 fresh run，且结果在最终回复中如实报告。
