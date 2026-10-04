# SS 作业管理器开发计划

本文件记录 2026-09-29 确定的第一版范围与验收要求。

## 产品与数据

- 以现有 AppKit DDL Manager 为基础，发布独立的“SS 作业管理器”，bundle ID 为 `io.github.acemetric.sshomeworkmanager`。保留日历、任务编辑、通知；旧版用户通过旧应用导出 plist，再在新应用导入。
- 本机任务、课程关联与识别缓存放在新应用的 Application Support 目录。GitHub 访问令牌与刷新令牌只放在 macOS 钥匙串，不进入偏好、备份、日志、安装包或仓库。
- GitHub App 仅授权用户选定的自己 fork，申请 Metadata read 和 Contents read/write。桌面应用使用设备授权；客户端 ID 可公开配置，不能附带 client secret 或 App private key。

## 作业发现

- 每门课程关联一个已有本地克隆目录，或在应用中克隆用户自己的 fork。验证 fork 的上游身份和本机对私有上游的读取权限。
- 启动时、运行中每 6 小时和手动刷新时，只获取并扫描老师上游默认分支的可读文本文档；不扫描其他学生的 fork。按 blob 版本缓存；列出跳过的大文件、无权限和读取失败。
- 每项发现保留标题、截止时间、来源仓库与文件位置、原文片段。用户审核或修改后才导入 DDL；没有明确时间的日期必须人工补全。原文后续变化只生成更新建议，不覆盖本机编辑。
- GitHub 断线时保留已有 DDL，显示上次成功检查时间。

## Git 操作与安全

- 拉取：验证目录、分支与远端身份，获取自己 fork 和老师上游，安全补齐本地分支并合并上游，成功后只推送到经过验证的自己 fork。脏工作区和分歧时停止；冲突时列出文件，用户解决后继续。绝不强推。
- 提交：用户勾选文件并填写说明；仅暂存和提交所选文件。推送前检查完整待推送提交范围及敏感内容；用 GitHub 隐私邮箱写新提交，不改全局 Git 配置。
- 每次推送重新核验 fork 身份，使用明确的 fork URL 与分支，不依赖默认 push 配置。Git 子进程不用 shell 拼接，禁用仓库钩子，令牌不写入 URL、参数、文件或日志。

## 验收与发布

- 用模拟 API 和临时仓库覆盖私有上游失败、重复与变更的作业、含糊日期、脏工作区、冲突、被拒推送、文件选择、敏感内容和上游绝不被推送；回归现有日历、备份和通知。
- 发布前扫描当前文件、完整历史、旧 ZIP、截图及新产物。发现真实凭据应先撤销或轮换并处理历史。保留原作者署名及公开改编发行的授权记录。
- 第一版面向 macOS 13+ Apple 芯片，提供 GitHub Releases 未公证 ZIP 和首次打开说明。Apple Developer ID 签名与公证留作后续版本。

## 已确定的产品选择

只扫描老师主分支；只读取可读文本文档；识别结果先审核；每门课关联本地仓库；同步后更新自己的 fork；提交前逐项选择文件。私有上游使用用户本机已有 Git 凭据，绝不上传该凭据到仓库。

## 实施记录（2026-10-04）

已实现独立本机存储与钥匙串、GitHub App 设备登录及刷新、所选个人 fork 列表、课程与本地克隆关联、当前老师默认分支发现、审核导入、安全同步、选文件提交、冲突引导与推送重试。加入模拟 API / 临时仓库 / AppKit 回归、完整历史与产物检查以及本机发布打包脚本。

老师默认分支会在每次扫描及同步时重新确认。第一版只支持规则识别的文本文档；数据限额和压缩包阻止规则详见 docs/SECURITY.md。

### 2026-10-04：课程文档漏检修复

- 补充“本周 / 这周 / 下周”“星期 / 礼拜”“周末”和相对天数的识别，支持 Markdown 加粗及截止时间另起一行。
- “规则”“任务”等通用标题不作为作业名称，优先使用作业标题或文档文件名；审核原文包含后面的任务与附件说明。
- 相对日期只保存老师原话，不以扫描时间推算；用户必须确认完整截止时间。识别缓存版本更新，旧版空结果会重新解析。
- 增加截图所示作业的解析、临时 Git 上游扫描和 AppKit 展示回归；扫描和推送的仓库权限边界保持原设计。

外部前提：GitHub App 已注册，公开 Client ID / 安装 URL 已预置。维护者已自行完成首次私钥准备并安装到明确授权的个人课程 fork；开发工具未读取任何私钥或生成 Client Secret。桌面账户授权联调及正式 GitHub Release 仍待完成。本机候选包明确标注未公证，不能把模拟测试当作真实私有课程联调证据。

## 依据

- [GitHub App 设备授权](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app)
- [GitHub 仓库许可](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)
- [Apple 签名与公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
