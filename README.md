# SS 作业管理器

基于同学开发的 [DDL Manager](https://github.com/123456p-df/DDL-Manager) 改编的原生 macOS 作业管理器。适用于 **macOS 13+、Apple 芯片**。

## 功能

- 保留日历、任务编辑、老师截止时间 / 我的 DDL、菜单栏和本机系统提醒。
- 从老师仓库当前默认分支的 Markdown、纯文本等文档寻找作业和截止时间；启动、每 6 小时及手动检查。
- 发现结果显示原文与来源，审核后才导入；含糊日期和缺失时间必须补全；后续更新不自动覆盖本机任务。
- 每个课程可启用或停用自动检查，关联已有克隆或克隆个人 fork。
- 图形化合并上游、冲突处理、逐项选择文件提交、推送失败后重试。
- **所有推送只能到当前登录账户拥有的个人 fork。绝不向老师上游推送，绝不强推。**

## 首次使用

1. 开发者完成一次 [GitHub App 注册](docs/GITHUB_APP_SETUP.md)。同学只需安装该 App 到自己选择的课程 fork，并通过浏览器设备码登录。
2. 打开“GitHub 课程与作业”（主界面按钮或 ⌘G），点击“安装授权…”和“登录”。
3. 添加自己的课程 fork，关联本地仓库或克隆；私有老师上游需要本机已有 SSH / Git 钥匙串访问权限。
4. “检查作业”后选择发现项，核对老师截止时间并保存。提醒和日历以“我的 DDL”为准。
5. 拉取前处理本地修改；提交时勾选文件、填写说明。遇到冲突使用“继续冲突合并”中的引导。

**GitHub App 已注册并预置公开配置：** [安装 SS Homework Manager](https://github.com/apps/ss-homework-manager/installations/new)。维护者已完成首次注册准备与个人课程 fork 安装；密钥仅由维护者保管，应用不使用或分发。桌面设备登录和课程仓库联调仍待完成。同学使用预配置的应用无需自行注册。

## 下载与安装

发布准备脚本生成 `build/releases/SS-Homework-Manager-1.0-macOS-arm64.zip`，供维护者上传 GitHub Releases。开发候选包带 `-candidate` 后缀，应用信息尚未配置时不能称为可直接登录的发布版。

解压后拖入“应用程序”。第一版为 ad-hoc 签名、**未 Apple 公证**。首次打开若被系统阻止，请在“系统设置 → 隐私与安全性”查看“仍要打开”，按系统提示确认；部分系统也可 Control 点按后选择“打开”。只有确认来源为本项目时才执行此步骤。

## 数据与旧版迁移

- 独立 bundle ID：`io.github.acemetric.sshomeworkmanager`。
- 数据目录：`~/Library/Application Support/SS Homework Manager/`；GitHub 令牌仅在本机钥匙串。
- 在旧 DDL Manager 导出任务备份，再在新应用“文件 → 导入任务备份…”导入。
- 任务备份不含 GitHub 登录凭据或本地课程关联，但会含任务内容、备注与来源；分享前检查个人信息。
- 关闭窗口后保留菜单栏提醒；退出应用或关机期间无法定时扫描，系统通知受系统权限与专注模式影响。

## 构建与验证

需要 macOS Command Line Tools、系统 Python 3；无需 Xcode 或第三方服务密钥。

```sh
zsh build.sh
zsh test.sh
zsh verify-import.sh
zsh verify-homework.sh
zsh verify-forms.sh
zsh verify-course-ui.sh
python3 Tools/security-audit.py --history --artifacts build/SS\ 作业管理器.app --ocr build/tests/privacy-ocr
zsh release.sh --candidate
```

构建产物为 `build/SS 作业管理器.app`。完整发布前配置 `Config/GitHubApp.plist` 中的两项公开信息，再运行 `zsh release.sh`。持续集成执行核心、导入、GitHub/Git 安全测试和历史泄漏检查。

## 文档

- [开发计划](DEVELOPMENT_PLAN.md)
- [GitHub App 注册](docs/GITHUB_APP_SETUP.md)
- [安全设计、限制和修复指引](docs/SECURITY.md)
- [验证与发布状态](docs/VERIFICATION.md)
- [原作者与授权记录](docs/ATTRIBUTION.md)
- [原版说明](docs/UPSTREAM_README.md)

识别采用本地规则，可能漏掉非标准日期；第一版不解析 PDF / Office 文档。文档单文件最多 1 MB，总扫描最多 30 MB。提交检查单对象最多 5 MB、总计 50 MB、最多 4000 个对象，压缩包与常见凭据文件直接阻止。未经真实 GitHub App 联调和发布条件检查，不能把候选包作为正式发布版本。
