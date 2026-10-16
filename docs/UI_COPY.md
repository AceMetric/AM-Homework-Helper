# 1.13.3 界面文案清单

## 判断规则

保留字段、按钮、数量和实际状态；错误说明当前原因与可执行恢复动作。发送范围、费用、目标仓库和不可撤销后果留在对应确认处。仅移动应用生成的教学文字，不改用户备注、老师原文、证据或检查报告正文。

常规页面不另设帮助入口。完整说明统一在侧栏“开始使用”。

## 逐项处理

|位置|原文／界面片段|处理|结果|
|---|---|---|---|
|Sources/AMWorkspace.swift|备注（可修改或清空）|缩短|备注|
|Sources/AMWorkspace.swift|Text("已加入任务，修改后保存即可同步。").foregroundStyle(.secondary)|缩短|Text("已加入任务").foregroundStyle(.secondary)|
|Sources/AMWorkspace.swift|请补全并核对截止日期和时间；当前日期不会自动保存。|缩短|请确认完整截止时间。|
|Sources/AMWorkspace.swift|Label("规则检查免费可用；复杂文档可交给助手识别。",systemImage:"checkmark.shield").foregroundStyle(.secondary)|删除，教程归位|移入对应教程章节；不留空占位|
|Sources/AMWorkspace.swift|检测后选择这台 Mac 已安装的模型。|缩短|尚未选择模型|
|Sources/AMWorkspace.swift|Text("关闭后仍可在课程“更多”中手动重新识别。规则结果先显示，模型随后补充。").foregroundStyle(.secondary)|删除，教程归位|移入对应教程章节；不留空占位|
|Sources/AMWorkspace.swift|先在课程页添加课程，再启用云端识别。|缩短|尚未添加课程|
|Sources/AMWorkspace.swift|后台检查只用规则。点击课程中的 AI 增强识别并确认材料后才发送；不发送个人任务或凭据。每天最多20次请求，包含失败；可能产生服务费用。|缩短|仅发送确认材料，不发送个人任务或凭据。每天最多20次请求（含失败），可能产生费用。|
|Sources/AMWorkspace.swift|仅使用本机已安装模型，不自动下载；失败后继续规则识别。|缩短|模型失败时保留规则结果。|
|Sources/AMWorkspace.swift|相对日期、缺失时间和考试不会自动加入；已有任务更新仍需审核。|缩短|相对日期、缺少时间、考试及更新建议需审核。|
|Sources/AMWorkspace.swift|Text("准备多门课程的新材料，复制指令交给助手；结果自动接回待审核，无需手动导入。").foregroundStyle(.secondary);|删除，教程归位|移入对应教程章节；不留空占位|
|Sources/AMWorkspace.swift|;Text("不会自动发送老师原文或启动付费分析。").font(.caption).foregroundStyle(.secondary)|删除，教程归位|移入对应教程章节；不留空占位|
|Sources/AMWorkspace.swift|Text("Gemini 综合检查整份项目、代码与图片。使用自己的免费项目，仅主动复核时发送所选材料。").foregroundStyle(.secondary);|删除，教程归位|移入对应教程章节；不留空占位|
|Sources/AMWorkspace.swift|;Text("与老师作业识别分开；本机检查和 Skill 仍然可用。").font(.caption).foregroundStyle(.secondary)|删除，教程归位|移入对应教程章节；不留空占位|
|Sources/AMWorkspace.swift|;Text("默认标记中国大陆周末、法定假期和调休；不会修改老师截止时间。").font(.caption).foregroundStyle(.secondary)|删除，教程归位|移入对应教程章节；不留空占位|
|Sources/AMWorkspace.swift|subtitle:state.step==0 ? "连接课程，或直接使用本机作业功能。":"每一步成功的配置都会保留。"|缩短|subtitle:""|
|Sources/AMWorkspace.swift|正在等待登录，其他课程数据会保留。|缩短|等待 GitHub 登录…|
|Sources/AMWorkspace.swift|正在逐门处理；可以收起引导，成功结果会保留。|缩短|正在配置课程…|
|Sources/AMWorkspace.swift|Label("用浏览器连接 GitHub，无需 SSH 或额外安装工具。",systemImage:"person.crop.circle.badge.checkmark")|删除，教程归位|移入对应教程章节；不留空占位|
|Sources/AMWorkspace.swift|在网页输入上方代码并确认。完成后这里会自动继续。|缩短|等待网页授权…|
|Sources/AMWorkspace.swift|Text("勾选自己的课程 fork，老师仓库和读取权限将自动核验。").foregroundStyle(.secondary)|删除，教程归位|移入对应教程章节；不留空占位|
|Sources/AMWorkspace.swift|Text("选择课程总文件夹可批量匹配；缺少文件的课程可下载到同一个位置。").foregroundStyle(.secondary)|删除，教程归位|移入对应教程章节；不留空占位|
|Sources/AMWorkspace.swift|Text("检查只读取老师内容，不合并文件、不提交或推送。失败课程可单独处理，已有结果保留。").foregroundStyle(.secondary)|删除，教程归位|移入对应教程章节；不留空占位|
|Sources/AMWorkspace.swift|WorkspaceHint(key:"skill",text:"准备材料 → 复制指令给助手 → 结果自动接回；不会自动发送材料。")|删除，教程归位|移入对应教程章节；不留空占位|
|Sources/AMWorkspace.swift|Text("等待助手期间可以继续使用。接回后仍需审核；重试只准备尚未成功的材料。").foregroundStyle(.secondary)|删除，教程归位|移入对应教程章节；不留空占位|
|Sources/AMWorkspace.swift|;Text("提交记录与作业完成状态分别管理。").foregroundStyle(.secondary)|删除，教程归位|移入对应教程章节；不留空占位|
|Sources/AMWorkspace.swift|;Text("应用或终端产生的提交会显示在这里；本地提交与已推送分别核验。").foregroundStyle(.secondary)|删除，教程归位|移入对应教程章节；不留空占位|
|Sources/AMWorkspace.swift|选择一条记录查看详情|缩短|未选择提交记录|
|Sources/AMWorkspace.swift|Text("概括和提交要求已预填，可修改或清空。").font(.caption).foregroundStyle(.secondary)|删除，教程归位|移入对应教程章节；不留空占位|
|Sources/AMWorkspace.swift|识别后选中一项，在这里核对和修改。|缩短|未选择作业|
|Sources/AMWorkspace.swift|Text("粘贴通知、输入一句话或识别截图；核对后加入安排。").foregroundStyle(.secondary)|删除，教程归位|移入对应教程章节；不留空占位|
|Sources/AMWorkspace.swift|WorkspaceDisclosure("范围与安全说明"){Text("包含子文件夹；Markdown 图片自动关联并去重。只读取所选范围，越界图片需要选择共同父目录。隐藏配置、依赖、缓存、构建目录和敏感文件已排除；未检查不算通过。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}|删除，教程归位|移入对应教程章节；不留空占位|
|Sources/AMWorkspace.swift|Text(subtitle).font(.system(size:12)).foregroundStyle(.secondary)|保留条件显示|if !subtitle.isEmpty {Text(subtitle).font(.system(size:12)).foregroundStyle(.secondary)}|
|Sources/App.m|\n点击查看详情|删除，教程归位|移入对应教程章节；不留空占位|
|Sources/App.m|%ld 项待完成 · 点击打开 / 右键菜单|缩短|%ld 项待完成|
|Sources/App.m|请先在提醒设置发送测试，等待约5秒。通知已经交给系统后，是否展示仍取决于权限、专注模式和系统状态。|缩短|测试提醒约5秒送达，可能受通知权限或专注模式影响。|
|Sources/App.m|当前是界面预览，任务只存在内存中，系统通知未注册。正常启动后，可以在这里开启通知、发送测试提醒。|缩短|预览不发送系统通知。|
|Sources/SSSubmission.inc|点击文件旁的“查看”检查变更。|缩短|未选择预览文件|
|Sources/SSSubmission.inc|提交说明，例如：完成第四次物理作业|缩短|提交说明|
|Sources/SSSubmission.inc|关联作业（可选，不会自动选择文件）|缩短|关联作业（可选）|
|Sources/SSCourseSkill.inc|只准备老师文档，不含个人答案、任务或凭据。将指令交给云端助手后，所选文档会由该服务处理。所有课程共用一个 Skill。|缩短|只准备所选老师文档，不含个人答案、任务或凭据。交给云端助手后，材料由该服务处理。|

## 结构性调整

|位置|处理|保留内容|
|---|---|---|
|日历空状态|删除点击加号／切换筛选教学|暂无任务、实际数量与筛选控件|
|提交选文件|删除“选择文件并填写提交说明…”整行并重连布局|目标仓库、文件、说明、检查按钮及真实校验|
|材料确认|将网页上传／本机助手多步教程归位|目标助手、逐文件范围、当前限制与确认按钮|
|配置完成|删除检查／审核／同步／提交四项教程|配置完成状态和课程结果|
|通知设置|多步系统设置教学归位|通知权限、测试状态、打开设置及失败原因|
|悬浮提示|删除操作步骤|名称、快捷键、全文及当前不可用原因|
|开始使用|重组为六章|录入与周期安排；日历与筛选；课程检查与审核；本机检查与在线复核；提交与记录；设置与常见问题|

## 必须保留

- 未确认的截止时间、时区与证据。
- 本机与在线检查的完成情况、未核验内容、原始报告。
- API 材料范围、费用、每日额度与第三方服务条件。
- Git 提交目标、强制安全检查、冲突及回退操作后果。
- 删除、恢复、覆盖备份、停止重复等确认的真实后果。
- 已排除文件及原因、模型或队列的实际状态。

## 验证边界

本轮不用截图捕获。原生属性、布局和行为回归通过后，仍须用户在独立模拟预览中确认实际材质和可读性。

## 第二轮逐页核查

|位置|原文／片段|处理结果|
|---|---|---|
|Sources/AMWorkspace.swift|state.dirty ? "有未保存修改":"核对后保存至任务"|state.dirty ? "有未保存修改":""|
|Sources/AMWorkspace.swift|Text("安排工作日期，截止时间保持不变。也可以通过“安排到…”操作，无需拖放。").font(.caption).foregroundStyle(.secondary)|删除，移入教程|
|Sources/AMWorkspace.swift|步骤已全部完成，可以标记整个作业完成。|所有子任务已完成|
|Sources/App.m|快速录入作业（⌘⇧N）；完整新建可用 ⌘N|快速录入作业（⌘⇧N）|
|Sources/App.m|1. 允许 AM Helper 通知、横幅和声音。\n2. 检查专注模式是否静音。\n3. 确认应用在通知设置中的身份为当前安装版本。\n4. 回到提醒设置重试；任务保存不依赖通知成功。|系统通知权限或专注模式可能阻止提醒。|
|Sources/App.m|%@\n\n每个任务可以设置最多 10 个提醒点，例如「5小时、1小时、到期」。点击测试后，约 5 秒会出现系统通知。\n\n请在系统通知设置中允许 AM's Homework Helper 的横幅和声音。专注模式可能使提醒静音；电脑关机时不显示提醒。关闭窗口后应用仍在菜单栏运行。|%@\n测试提醒约5秒送达，可能受专注模式影响。|
|Sources/SSCourseWindow.m|点击加入队列；相同请求会合并，可在窗口菜单查看或取消。|排队检查|
|Sources/SSCourseWindow.m|先关联或下载课程文件夹，再检查新作业。|尚未关联本地课程文件夹|
|Sources/SSCourseWindow.m|只读取老师内容，不合并或推送。|检查新作业|
|Sources/SSCourseWindow.m|合并老师更新，再安全更新个人 fork。|同步课程文件|
|Sources/SSCourseWindow.m|self.commitButton.toolTip=self.syncButton.toolTip;|self.commitButton.toolTip=self.connected && local ? @"提交作业":@"需要登录并关联本地课程文件夹。";|
|Sources/SSCourseWindow.m|按当前课程和搜索筛选逐项审核；Return 保存并下一项|审核作业（Return 保存并下一项）|
|Sources/SSCourseWindow.m|连接 GitHub，然后添加你的课程仓库|尚未添加课程|
|Sources/SSCourseWindow.m|这门课尚未关联本地文件夹\n点击“关联文件夹…”继续|这门课尚未关联本地文件夹|
|Sources/SSCourseWindow.m|没有匹配的作业，试试其他关键词|没有匹配的作业|
|Sources/SSCourseWindow.m|暂无待审核作业，检查课程后会在这里显示|暂无待审核作业|
|Sources/SSCourseWindow.m|暂无待审核作业，点击“检查新作业”刷新|暂无待审核作业|
|Sources/SSCourseWindow.m|在编辑器中打开文件，保留需要的内容并删除冲突标记。保存后勾选文件，点击“标记已解决”；全部解决后再完成合并。|仍有未解决的冲突文件。|
|Sources/SSCourseWindow.m|冲突文件已经标记解决。可以完成合并，然后检查并推送到自己的 fork。|所有冲突已解决，可以完成合并。|
|Sources/SSSubmission.inc|上传附件，再导入助手结果|材料包已准备好|
|Sources/SSSubmission.inc|把 AM-Helper-review.zip 上传到助手；若不支持 ZIP，请解压后上传其中的文件。助手返回 results.local.json 后，下载并在本报告点‘导入助手结果…’。网页聊天无法读取 Mac 本机路径。|材料包：AM-Helper-review.zip|
|Sources/SSSubmission.inc|仅把指令交给获准读取本机文件的助手。结果写回本机批次目录后自动接回；普通网页聊天请使用附件方式。|仅交给已获准访问所选本机材料的助手。|
|Sources/SSSubmission.inc|材料包已准备好；上传给助手后，下载 JSON 并点‘导入助手结果…’。|材料包已准备好|
|Sources/SSSubmission.inc|等待本机助手写回复核结果；不会自动发送材料。|等待本机助手复核结果|
|Sources/SSSubmission.inc|当前本机文件 · 本机检查和助手复核分别显示覆盖范围。|当前本机文件|
|Sources/SSSubmission.inc|拟提交版本 · 质量建议可确认，凭据与推送安全检查始终强制执行。|拟提交版本 · 安全检查必须通过|
|Sources/SSCourseSkill.inc|复制指令交给助手即可。结果会自动接回，无需选择文件导入；可在“更多 → 识别批次与进度”查看。|所选课程材料已准备好。|
|Sources/SSCourseSkill.inc|· 等待助手识别；结果会自动接回。|· 等待助手识别|
|Sources/AMRecurrenceEditor.inc|老师原作业保持截止时间。可从任务菜单另建周期安排。|老师作业不直接重复。|
|Sources/AMOnlineReviewUI.inc|自己的 API 密钥 · 留空保留现有密钥|API 密钥（留空保留）|
|Sources/AMOnlineReviewUI.inc|使用自己的免费项目；软件无法确认计费状态，不承诺绝对零费用。每天最多20次生成请求，失败与重试也计数。\n免费服务可能使用材料改进产品并有人审阅；遵守年龄、地区、用途条件，不发送敏感或保密材料。只发送确认的材料，不执行作业代码、不自动提交。|仅发送确认材料。使用自己的免费项目，软件无法核验计费状态；每天最多20次生成请求（含失败和重试）。\n免费服务可能使用材料改进产品并由人工审阅，请遵守年龄、地区及用途条件，勿发送敏感或保密材料。|

## 空状态及确认页复查

|位置|原文|处理结果|
|---|---|---|
|Sources/AMNativeUI.inc|暂无匹配任务，可调整筛选或点＋快速录入。|暂无匹配任务|
|Sources/AMProgressUI.inc|暂无进行中的操作。已完成记录可以在上方展开。|暂无进行中的操作|
|Sources/AMPreflightUI.inc|逐文件审阅，可排除无关材料。图片可放大；不会自动发送或提交。|仅使用已勾选材料，不会自动发送或提交。|
|Sources/AMPreflightUI.inc|将包含 %lu 个文件，其中 %lu 张图片。可在左侧选择文件审阅。|已选 %lu 个文件 · %lu 张图片|
|Sources/AMPreflightUI.inc|数据表：共 %lu 行；预览前 %lu 行。勾选时仍会包含完整数据，可排除无关文件。|数据表：共 %lu 行，预览前 %lu 行；发送时包含完整数据。|
|Sources/AMPlanningUI.inc|写下一个可以完成的小步骤。子任务使用作业的截止时间。|子任务沿用作业截止时间。|
|Sources/AMPlanningUI.inc|例如：完成第一部分|子任务名称|

- `Sources/AMWorkspace.swift`：拆成几个小步骤，逐项完成。 → 暂无子任务。

- `Sources/AMWorkspace.swift`：选择提交记录，查看文件、提交号与推送状态。 → 未选择提交记录。

- `Sources/AMWorkspace.swift`：Text("计划日期不会改变作业截止时间或提醒。").font(.caption).foregroundStyle(.secondary) → 删除并收紧布局。

- `Sources/AMWorkspace.swift`：WorkspaceHeading(title:"开始使用",subtitle:"",symbol:"sparkles") → 删除并收紧布局。

- 配置状态：首次检查结束。可重试未完成课程，或完成配置后查看结果。 → 首次检查已结束。。

- 配置状态：返回不会删除已保存的课程和任务。 → 删除。

- 配置状态：首次检查中，请等待；不会重复启动检查。 → 首次检查中…。

- 配置状态：选择课程总文件夹可批量匹配；权限失败可处理后重新检测。 → 课程权限核验完成。。

- 配置状态：匹配完成。核对目录后，点“确认并开始检查”即可。 → 课程目录匹配完成。。

- 配置状态：目录已选中，关联前将核验仓库身份。 → 目录已选中，待核验。。

## 本轮回归记录

- 共享分段控件使用常规尺寸及自然宽度；日历和页面导航在 macOS 27 使用 Tabs，表单值选择保留 ValueSelection。工具栏溢出菜单保留每一项。
- 页面头部锚定内容安全区域，按实际头部高度安排网格、列表、课程及教程内容。
- 本机已验证输入表单、课程审核、识别与草稿状态、材料确认、在线复核、快速录入、预览退出和更新退出；合成数据不调用真实模型。
- 源码、完整历史及正式构建资源的隐私检查通过；扫描包内资源，没有屏幕捕获。
- 实际玻璃材质、窗口激活／失活、减少透明度仍由用户在新独立预览确认；属性与隐藏窗口几何回归不能代替实际外观验收。
- 当前版本目标 1.13.3／构建35，高于已发布的 1.13.2／构建34。代码推送后等待远端完整检查，预览确认前不创建正式标签、不修改更新源。

## R019 用户反馈后的精简

“开始使用”也应让新用户直接开始操作。六项各保留一句说明及原有入口，移除长段教程、重复按钮，不增加折叠或二级教程。标题缩短，说明和操作并排，减少页面高度。发送范围、费用及操作后果继续保留在对应确认处。

六项说明由约 1149 字压缩至 82 字。正式目标仍为 1.13.3／构建35。

## 月历滚动条

按用户反馈去掉月历的滚动条，释放原来的轨道宽度。沿用触控板滚动、月份选择和今天定位；任务详情及其他长内容仍使用各自的滚动控件。版本保持 1.13.3／构建35。

- 课程检查结果按钮：“X 项待审核 · 查看结果”缩短为“X 项待审核”，保留点击后查看审核结果的操作。
