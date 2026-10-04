# DDL-Manager

原生 macOS 截止时间管理器，支持日历、任务编辑、本机提醒和任务备份。本分支在 [原作者的 DDL-Manager](https://github.com/123456p-df/DDL-Manager) 基础上增加 GitHub 课程作业管理功能，供原作者审阅和合并。

适用于 **macOS 13+、Apple 芯片**。

## 功能

- 管理“老师截止时间”和“我的 DDL”，使用日历、主题、菜单栏及系统提醒。
- 从老师仓库当前默认分支的 Markdown、纯文本等文档发现作业；启动时、每 6 小时及手动检查。
- 显示原文、文件位置和附近任务说明，审核后才加入任务；老师更新原文时提供更新建议。
- 识别“本周日 21:00”“星期天”“下周一”等相对日期，要求确认完整日期后导入。
- 关联本地课程仓库，合并老师上游、处理冲突、逐项选择文件提交。
- **作业只推送到经核验属于当前登录用户的个人 fork，绝不推送到老师仓库，也不强推。**

## 安装与使用

此开发分支尚未发布 GitHub Release。维护者可通过发布脚本生成测试包；包名为 `DDL-Manager-1.0-macOS-arm64-candidate.zip`。当前构建使用临时签名，**未经 Apple 公证**。

解压后将 `DDL-Manager.app` 放入“应用程序”。首次打开若被系统阻止，可在“系统设置 → 隐私与安全性”按系统提示选择“仍要打开”。更新前退出正在运行的旧测试版。

### 日历与提醒

新建任务，填写老师截止时间和自己的 DDL，设置提醒点后保存。系统通知需要授予权限，可用“提醒测试”检查。关闭主窗口后应用继续在菜单栏运行；退出应用、关机或休眠期间无法定时扫描。

原版用户可先导出任务备份，再在本版“文件 → 导入任务备份…”导入。备份可能包含任务备注和来源，分享前请检查个人信息。

### GitHub 课程作业

1. 打开“GitHub 课程与作业”（主界面按钮或 ⌘G）。
2. 点击“安装授权…”，将 GitHub App 安装到自己的账户，只选择个人课程 fork；回到应用点击“登录”，按提示完成设备码授权。
3. 点击“添加 fork”，再“关联已有克隆”并选择电脑上的课程仓库文件夹；还未下载时可点击“克隆”。私有老师仓库需要本机已配置的 Git 读取权限。
4. 点击“检查作业”，选择发现项，查看原文，再“审核并导入 / 更新”。“本周日”等相对日期要结合老师布置作业的时间确认，不能按扫描当天猜测。
5. 拉取前处理本地修改。提交时逐项勾选文件、填写说明；发生冲突时按“继续冲突合并”引导处理。

已预置 [GitHub App 安装入口](https://github.com/apps/ss-homework-manager/installations/new)。这个 App 沿用注册时的名称 **SS Homework Manager**，与桌面应用的显示名称不同；使用预配置的测试包无需自行注册。若上游采用自己的 GitHub App，维护者可按 [配置说明](docs/GITHUB_APP_SETUP.md)替换两项公开信息。

## 数据与安全

GitHub 访问令牌和刷新令牌只保存在本机钥匙串，不进入仓库、日志或任务备份。应用不附带私钥或 Client Secret，不更改全局 Git 配置。

本次恢复显示名称时保留旧测试版的内部标识与数据位置，已有任务、课程关联及登录信息可继续使用：

- Bundle ID：`io.github.acemetric.sshomeworkmanager`。
- 数据目录：`~/Library/Application Support/SS Homework Manager/`。

该目录与原版 DDL Manager 独立；原版任务仍通过备份导入。详细推送校验、凭据处理和提交限制见 [安全说明](docs/SECURITY.md)。

## 识别范围与验证状态

当前使用本地规则扫描文本文档，支持 Markdown、纯文本、RST、AsciiDoc、Org 和 TeX；不解析 PDF / Office 附件。附件作业可从正文中的说明发现，但不会自动读取附件内容。单文件最多 1 MB，单次文档总量最多 30 MB。

构建、模拟 GitHub API、临时 Git 仓库及 AppKit 回归已验证。真实账户设备登录、私有课堂仓库操作和通知送达仍需在实际使用环境中核对。完整记录见 [验证状态](docs/VERIFICATION.md)。

## 开发与贡献

需要 macOS Command Line Tools 和系统 Python 3：

```sh
zsh build.sh
zsh test.sh
zsh verify-homework.sh
```

构建产物为 `build/DDL-Manager.app`。模块说明、完整验证命令、打包流程和上游 PR 注意事项见 [开发与贡献](docs/CONTRIBUTING.md)。

来源与署名见 [原作者与授权记录](docs/ATTRIBUTION.md)；原版用户指南保存在 [原版说明](docs/UPSTREAM_README.md)。
