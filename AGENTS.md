# Smart Shadow Agent Rules

本文件是 Smart Shadow 的实现宪章，面向后续在本仓库工作的 Codex/Agent。README 和 `docs/` 负责公开项目说明、架构、运维和安全文档；本文件只保留会影响实现取舍的长期规则。

## Product Intent

Smart Shadow 是 iPhone-first、Mac-service-backed 的个人任务入口系统，加上运行在本地 Mac 上的 `shadowd` 系统服务闭环。系统需要建立独立入口层：入口可以是用户在电脑或手机应用中的操作，例如显式点击 AI 智能影子、加星、收藏、分享、标记；也可以是电脑上的菜单栏应用入口、快捷键唤起的语音交互入口；也可以是手机上的轻应用，扫码绑定后即可唤起。用户通过语音交互后，最终路由回电脑上的 `shadowd`；`shadowd` 连接入口层、本机应用和 Codex；Codex 作为决策大脑完成任务理解、分解、规划和判断，并在对应项目下创建或恢复 Thread，调用本机软件完成推进；最后由 `shadowd` 给用户创建反馈，反馈位置默认使用用户发布任务的平台渠道。

它的核心不是聊天、项目管理系统、Feishu 工作台或 GitHub 替代品，而是一个“如影随形”的意图入口和本机软件桥梁。用户只需要把任务交给统一 agent 身份 `shadow`；`shadowd` 负责持续感知、连接、转交 Codex、维护状态、创建反馈并形成可追踪闭环；Codex 在对应项目 Thread 中调用本机软件推进任务。

从第一性原理看，Smart Shadow 本质上是围绕 Codex 和本机系统服务的二次开发：Codex 是决策大脑，负责主线、Project、Issue / 事项三层哲学下的理解、分解、规划、取舍和解释；`shadowd` 是智能影子的系统服务，是感知和响应的媒介、中介、桥梁；Smart Shadow 通过 Agent 规约、正式文档、可发布 skills、本地 `shadowd`、系统自动化和本机应用桥接，把 Codex 和电脑上的软件组织成用户的智能影子。不得把 Smart Shadow 设计成与 Codex 平行竞争的另一个 AI 助手、聊天入口或任务系统。

用户在手机端、Mac 端或外部入口与智能影子交互时，只要语义属于 Smart Shadow 范围，`shadowd` 都应把意图和上下文连接到 Codex；Codex 按本文件、README、`docs/`、skills 和可测试代码中的产品规约响应：维护人生主线、Project 和 Issue / 事项三层设计哲学，决定处理策略、执行路径、目标软件和反馈方式，并在授权边界内让 `shadowd` 响应外部应用中的用户操作。

当前语音与外部输入链路的核心原则是：User writes intent. Shadow executes work. 原始语音只在 iOS/macOS 本地短暂缓存并处理；入口层统一承接手机轻应用、Mac 菜单栏、全局快捷键语音、应用内 AI 智能影子、加星收藏、分享、标记等用户动作；语音交互最终必须路由回 Mac 上的 `shadowd`，再由 `shadowd` 连接 Codex 和本机软件。电脑上的应用软件也可能通过用户操作、轮询或监测成为隐式意图来源。GitHub、Feishu、Mail、微信、Calendar、Finder 等都可以承载具体 Project / Issue 的入口、动作、协作记录或上下文，但不强制成为统一管理本体。

系统应优先服务四条人生主线：

- 健康：睡眠、运动、饮食、心理和认知质量。
- 搞钱：收入、成本、财务风险、可执行副业机会。
- 关系：亲情、爱情、友情、协作关系和低内耗沟通。
- 工作：推进关键项目、降低沟通成本、提升交付质量、沉淀复用能力。

四个人生主线是一套长期设计哲学，不要求全部放在同一个软件里管理。当前默认准则是：

- 工作相关：用户当前使用 Feishu 平台；工作 Project / Issue 默认通过 Feishu CLI 使用 Feishu 的任务看板跟踪。GitHub 主要承载代码、PR、Issue、CI、开源反馈和 repo-centered execution，不替代 Feishu 的工作任务看板。
- 生活相关：用户当前使用 Apple Reminders；健康、搞钱、关系和个人生活事项默认在 Reminders 的对应看板或列表中跟踪。Calendar 只承载明确时间块、截止点和节奏安排；Finder、Notes、Contacts、Photos、Music 等承载对应资料和资产。
- 跨域或特殊项目：具体软件仍由 Project 语义、协作场景、隐私风险和用户习惯决定，但偏离上述默认准则时需要能解释原因并保留 Project / Issue 映射。

当 Project / Issue 需要投影到 Reminders 时，Reminders 视图应同时吸收 GTD 和四象限工作法。四个长期列表可承载人生主线；每个列表内部统一使用四个栏目：

- `IMPORTANT`：对安身立命重要、需要长期规划和复盘的事项。
- `URGENT`：需要立即处理、阻塞当前节奏或有明确时限的事项。
- `DOING`：正在推进、需要持续关注但不应重复生成的新事项。
- `TODO`：待处理、待分派、待确认或可交给别人处理的事项。

无法归入这些方向、或没有明确正向投入产出比的事项默认降级，不要制造新的噪音和中间产物。

Smart Shadow 的核心管理主线是“智能影子闭环”。入口层负责在手机和电脑上接住用户主动表达的意图；`shadowd` 是智能影子的系统服务，负责不间断感知、连接和响应；Codex 是决策大脑，负责在“人生主线 -> Project -> Issue / 事项”层级下理解、分解、规划和判断；电脑上的应用软件是意图入口、上下文来源、响应工具、协作表面和反馈表面。

Calendar 和 Reminders 不再是核心管理中枢，而是与 Finder、Contacts、Notes、Photos、Music 等同类的本机软件表面：

- Reminders：承载可完成动作、提醒、审核卡、跟进、阻塞处理和复盘任务。
- Calendar：承载时间块、会议、预约、截止点、里程碑和生活节奏。
- Finder：承载项目文件夹、工作产物、状态记录和可复用资料。
- Notes：承载轻量知识、项目资料入口、用户笔记和可读文档。
- Contacts、Photos、Music 等：承载围绕主线、Project 和 Issue 沉淀的人、图像、音乐和其他个人资产。

ShadowD 不再按旧的三分区界面模型组织。新的交互与架构方向是：入口层接住手机轻应用、Mac 菜单栏、快捷键语音、应用内 AI 智能影子、加星收藏、分享、标记等显式入口，或本机应用产生的隐式意图 -> 语音和入口事件路由回 Mac 上的 `shadowd` -> `shadowd` 感知并整理上下文 -> Codex 决策大脑完成分解和规划 -> Codex 在对应项目下创建或恢复 Thread 并调用本机软件推进 -> `shadowd` 创建用户反馈，默认回到用户发布任务的平台渠道。

## Architecture Rules

- 主实现保持 Swift-native：入口层可以出现在 iOS 轻应用、Mac 菜单栏、全局快捷键语音、应用内 AI 智能影子、分享/收藏/标记等位置，Mac 上的 `shadowd` 是智能影子的本地长期系统服务；不要重新引入 Python 服务层、Python CLI 或 Python 常驻进程。
- `shadowd` 应作为 macOS 用户级长期服务运行，具备启动、停止、健康检查、日志、状态快照和崩溃恢复路径。
- Codex 是主线、Project、Issue / 事项的决策大脑，负责任务理解、分解、规划、取舍、解释、高风险判断、项目 Thread 创建/恢复和本机软件调用；`shadowd` 是感知和反馈桥梁，负责显式入口接收、隐式意图监测、来源去重、上下文整理、Codex 连接、状态跟踪、反馈回传、审计、恢复和 native app 桥接通道，不应复制一套独立的大模型后端、聊天后端或 ChatType 式转写后端。
- Smart Shadow 规则必须优先沉淀在全局/项目 `AGENTS.md`、正式 docs、skills、配置和测试中；临时聊天结论只有固化后才算产品规则。
- MVP 的核心闭环是入口层表达意图，`shadowd` 感知并连接 Codex，Codex 决策并在对应项目下创建或恢复 Thread，调用本机软件推进任务，最后由 `shadowd` 创建反馈。App 内 Draft 或入口层 Draft 只有在用户确认后才投递给 `shadow`，再由 Codex / `shadowd` 按 Project / Issue 语义落到 Reminders、Calendar、Finder、Notes、GitHub、Feishu、Mail 或其他本机/协作表面；反馈位置默认使用用户发布任务的平台渠道。
- iOS/macOS 前端负责 GitHub 登录、默认任务仓库选择、录音、本地短暂音频缓存、本地 ChatType Runtime 转写、本地 ChatType Polish 润色、用户确认/编辑，以及用用户本人 GitHub 身份创建 issue 或 comment。
- 前端只能写用户本人明确发起的内容：新 Project / Issue、补充说明、用户回复 Shadow 问题、或用户确认后的外部系统记录；前端不负责 agent 调度、任务执行、branch/commit/PR 创建、Shadow 进展汇报、原始音频上传或云端语音处理。
- `shadowd` 负责感知、连接、状态跟踪和反馈：接收显式输入、监测授权范围内的隐式意图、识别 Smart Shadow 创建或接入的 Project / Issue、读取最终文本任务、连接 Codex 完成任务分解和规划、维护本机应用桥接和反馈渠道映射；Codex 在对应项目 Thread 中调用本机应用或分配本地 Codex agent 推进任务，必要时创建 branch/commit/PR，并把结果更新到 Reminders、Calendar、Finder、Notes、Contacts、Photos、Music、GitHub、Feishu、Mail 等本机和外部协作面。
- `shadowd` 不负责录音、音频存储、语音转写、用户身份写入或创建用户型 GitHub bot 账号。
- PR 只用于已经达到可 review 状态的代码变更；阶段性进展、阻塞、补充说明和完成总结优先回到 Project / Issue 的中心状态，再按需要同步到 GitHub issue comment、Feishu、Mail 或本地文档。
- 优先事件驱动、系统通知、应用官方接口、网页回调、文件变更监听和消息队列；定时扫描只能作为补偿机制。
- 模块职责要清晰：入口层、iOS 轻应用、Mac 菜单栏、快捷键语音入口、语音转写、意图识别、任务规整、用户确认、GitHub 任务记录、`shadowd` 调度、Codex agent 执行、App 状态同步、模型路由器、审计日志、CLI 控制面和 launchd 配置。
- 任何自动化都必须能 dry-run、能回放、能解释、能停机。
- GitHub、Feishu、Mail、微信、小红书、Twitter、知乎、Finder、Calendar 等外部或本机系统都可能成为显式入口、隐式意图来源、响应工具或反馈表面，但不是 Smart Shadow 的唯一核心项目管理本体；其中单封 Mail 天然对应一个 Issue / 事项，归属哪个 Project 由 Smart Shadow 看板、用户确认或规则映射决定。
- Mail 不应被降级为普通提醒来源。用户标记、转发、筛选或确认后的邮件可以进入 Project / Issue 流程，并以原邮件 thread 作为外部上下文和后续沟通面；但 `shadowd` 不得自动接管全量邮箱或未经授权回复、归档、删除、转发邮件。
- 同一个 Project / Issue 投影到 Reminders、Notes、Calendar、Finder、GitHub、Feishu、Contacts、Photos、Music 等多个 native app 或外部系统时，必须有稳定内部身份和显式映射表；不得靠标题、内容、日期、路径片段或模糊匹配执行更新、删除、完成、移动或去重。
- 跨 App 同步默认只允许创建或更新有映射的对象；缺少映射、映射冲突、目标对象被用户手动移动/改名/删除时，必须进入 dry-run 预览、修复建议或用户确认流程，不得自动制造重复项、断链项或误删用户资产。
- 长期产品方向是让用户通过智能影子更好地使用电脑上的软件：Smart Shadow 负责感知意图、连接 Codex 决策、创建、打开、更新、同步、修复和解释相关对象，本机和外部应用负责承载用户熟悉的查看、编辑、协作和反馈体验。
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
- Reminders 是可完成事项表面：审核卡、待办、跟进、授权、阻塞处理、复盘任务和无固定时间段的响应事项。
- Calendar 是时间占用表面：会议、预约、明确开始结束时间的工作块、健康作息、关键截止点、里程碑和当天需要看到的时间安排。
- Reminders 的列表维度表示人生主线，栏目维度表示处理状态和优先级象限；不要用四象限替代四条人生主线列表。
- Calendar 不承载 GTD 或四象限栏目语义，只承载明确时间窗口、里程碑和时间占用。
- 与 Reminders 交互采用分层控制面：P0 内部语义和审计状态留在 Smart Shadow；P1 生产写入只走 Swift + EventKit；P2 AppleScript 只做脚本字典明确暴露的小范围补充；P3 原生 section/column 只通过 Reminders App UI 或受控 Accessibility 验收；P4 私有 ReminderKit 和 SQLite 只做只读诊断。
- 不得用标题前缀、备注元数据或伪列表冒充 Reminders 原生 section；不得直接写 Reminders SQLite、CloudKit 状态、WAL 或私有变更队列。
- 同一工作项必须有统一内部身份和投影映射；不得在 Calendar 和 Reminders 中制造互不关联的重复事项。
- Reminders、Calendar、Notes、Finder、GitHub、Feishu 等跨面投影必须共享同一个 Project / Issue 内部身份；投影映射是功能正确性的前置条件，不是可选审计字段。
- 一个工作项可以同时投影到两者，但语义必须不同：Calendar 表示时间窗口，Reminders 表示需要完成的动作。
- 有 due date、priority、start/end time 等官方字段时，优先写原生字段；审计元数据留在内部日志，不塞进用户可见备注。
- Reminder 标题保持干净，不添加内部系统前缀；备注只写人类可读的任务描述、背景和建议动作。
- 每次调试或实现会写入 Calendar / Reminders 的新功能后，完成验收前必须打开对应 Apple 原生界面做视觉验证，确认本轮产生或更新的事件/提醒实际可见、字段合理且没有明显重复；CLI 输出、SQLite 记录、EventKit 返回值和截图只能作为辅助证据，不能替代这一步。
- 只要当前目标涉及 Calendar / Reminders 的真实投影、删除、修复或用户可见语义变更，在没有完成 Apple 原生界面交互验收前，禁止把 Goal 标记为 complete；最多只能报告“代码/测试预检查通过，等待交互验收”。

## Sensing and Rules

- 感知层尽量保留原始事件、来源、时间、置信度和去重键。
- 感知层同时支持显式意图和授权范围内的隐式意图候选；隐式候选来自项目文件夹变化、Calendar 事项、微信文件传输助手消息、Mail/Feishu 选中或规则命中内容等场景时，默认只记录、解释、补全上下文、dry-run 或请求确认。
- `shadowd` 可以轮询或监测电脑上的一系列应用以发现意图候选，但不得因此自动接管全量 Mail、微信、Feishu、Calendar、Finder、浏览器历史或社交平台。
- 先用结构化采集和规则过滤降噪，不要过早让大模型解释一切。
- 对同一来源的重复信号要去重、合并、降噪。
- 规则库必须可维护、可验证、可审计；每条规则应说明范围、触发条件、默认动作、风险等级和是否需要用户确认。
- 规则冲突必须能解释优先级；规则更新要记录新增、修改或废弃原因。
- 涉及金钱、身份、隐私、账号、对外承诺、法律、医疗、人际关系敏感内容时，默认进入审核。
- 不允许为了完成任务绕开用户已经设定的安全边界。

## Responses and Review

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
- 能说明输入来源、决策依据、响应方式和结果。
- iPhone App 入口能完成语音任务捕捉、结构化任务确认、投递给 `shadow`、状态展示、补充说明和完成验收。
- Codex 能作为用户可见和可操作的主线、Project、Issue 决策大脑；Reminders、Calendar、Finder、Notes、Contacts、Photos、Music、GitHub、Feishu、Mail 等软件表面能承载对应投影、响应进展、阻塞、时间安排、PR 链接、完成摘要和项目资产。
- 对用户可见的重要工作按语义投影到需要的软件表面，并避免在 Reminders、Calendar、Finder、Notes、GitHub、Feishu 等表面制造重复事项或断链资产。
- 涉及 Calendar / Reminders 投影的变更，必须完成 Apple 原生 Calendar 或 Reminders 界面的视觉验收。
- 涉及 Calendar / Reminders 的 Goal 只有在原生界面交互验收完成后才能标记完成；仅有单元测试、CLI 验证、EventKit 返回值或 acceptance preview 不足以完成 Goal。
- 高风险动作进入审核流程。
- 成本、隐私和安全边界可解释。
- 至少有一个真实或接近真实的闭环案例完成验证。
- 回归测试和相关 CLI 验证已经 fresh run，且结果在最终回复中如实报告。
