# 开发与贡献

本分支为原项目增加 GitHub 课程作业能力，并沿用 **DDL-Manager** 名称。本分支当前独立开发，暂不提交 PR。个人开发计划留在本机，不属于仓库文档。

## 代码结构

| 模块 | 职责 |
| --- | --- |
| `Sources/App.m` | 主窗口页面状态、日历、统一任务编辑、通知和备份 |
| `Sources/DDLUI.m`、`SSSubmission.inc` | 系统外观、共享控件、统一表单按键及文件选择 / 预览弹窗 |
| `Sources/DDLCore.m`、`DDLImport.m` | 日期与提醒计算、公告解析及截图 OCR |
| `Sources/SSCourseWindow.m` | 嵌入课程页、统一审核列表、引导、操作状态和 Git 流程 |
| `Sources/SSAssignments.m` | 文档识别、日期待确认标记、标题与原文片段 |
| `Sources/SSGitHub.m` | 设备授权、令牌刷新、仓库及账户身份核验 |
| `Sources/SSGit.m` | 上游文档读取、安全合并、所选文件提交与明确目标推送 |
| `Sources/SSUpdateController.m`、`SSExitCoordinator.m` | 原生更新窗口、偏好、退出等待与保存保护 |
| `Sources/SSLocalData.m`、`SSSecurity.m` | 本机数据与钥匙串、敏感内容检查 |
| `Tools/security-audit.py` | 源码、历史、图片、归档和发布产物的隐私检查 |

`SS` 前缀与旧测试版内部数据标识暂时保留，用于兼容已有任务和登录信息。应用显示名称、可执行文件及新安装包名称均已恢复为 DDL-Manager。上游正式发行时，维护者应结合原版数据格式决定是否迁移内部标识；单纯改名不触发数据迁移。

## 构建与验证

需要 Apple 芯片 Mac、macOS 13+、Command Line Tools 和系统 Python 3，无需完整 Xcode。所有输出位于忽略的 `build/` 目录。

```sh
zsh build.sh
zsh test.sh
zsh verify-import.sh
zsh verify-homework.sh
zsh verify-forms.sh
zsh verify-course-ui.sh
zsh verify-update.sh
python3 Tests/SecurityAuditTests.py
python3 Tools/security-audit.py --history --artifacts build/DDL-Manager.app --ocr build/tests/privacy-ocr
```

图形与 Vision 测试需要可用的 macOS 图形会话，并须实际输出 PASS 标记；系统提前退出或无法运行 OCR 不能算通过。GitHub / Git 测试使用模拟响应和临时仓库，不操作真实课程仓库或用户钥匙串。

## 界面约定

采用 AppKit 与 macOS 原生菜单、文件选择和 sheet；共享 UI 模块提供中性分层背景、蓝色强调、系统字体和焦点样式。主窗口默认 1280×840、最小 960×640，侧栏始终保留；宽度小于 1180 时日历当天任务移到下方。布局使用 8 点间距，主要按钮至少 32 点高。

不再读取旧主题偏好，不强制浅色，也不修改系统外观设置。系统外观变化刷新缓存绘制与输入样式，同时保留未保存内容。页面保存当前会话中的筛选、选择和滚动状态；六小时检查由课程控制器独立管理，不随页面重建。

界面测试使用合成任务、课程与回复；截图仅生成在忽略的 `build/qa/`。`QA/` 是原版历史验收材料，不能作为当前界面说明。开发计划和私人账户截图均不加入提交。

## 本机打包

```sh
zsh release.sh --candidate
```

脚本依次构建、测试、校验签名、扫描历史与产物，然后生成 `build/releases/DDL-Manager-1.1-macOS-arm64-candidate.zip` 和校验文件。ZIP 仅包含应用，安装说明单独生成；不包含任务数据库、登录信息或开发计划。

`zsh release.sh` 生成不带 candidate 后缀的本机包，要求配置公开 GitHub App 信息。它仍不会上传 GitHub Release，也不完成 Developer ID 签名或 Apple 公证。当前 1.1 的构建号为 2，后续更新必须递增。签名清单及真实升级验证见 [软件更新与本机发布](UPDATES.md)。

## 提交给上游

- PR 的接收仓库为 `123456p-df/DDL-Manager`，来源为贡献者自己的 fork。
- 在说明中列出功能、验证范围和仍待实机联调的项目，并注明数据目录与内部标识的兼容选择。
- 保留原作者署名和已有历史，不提交个人聊天截图、密钥、本机数据库或构建包。
- 作业推送到个人课程 fork 的安全限制应作为合并后的功能约束保留。
- 上游采用自己的 GitHub App 时，仅替换 `Config/GitHubApp.plist` 中公开的 Client ID 和安装入口。

PR 不需要向原作者仓库直接 push。提交代码后由原作者审阅并决定是否合并。
