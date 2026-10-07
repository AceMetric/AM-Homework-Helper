# 软件更新与本机发布

## 用户使用

AM's Homework Helper 1.1.2 起使用正式在线更新源。原 DDL-Manager 或本应用 1.1 / 1.1.1 测试版需要从 [GitHub Releases](https://github.com/AceMetric/AM-Homework-Helper/releases/latest) 手动安装一次最新正式版：仓库更名后旧 Pages 地址不会重定向，新版已内置新地址。把应用放在“应用程序”中，再从应用菜单选择“检查更新…”。“设置 → 软件更新”可以关闭默认每 24 小时一次的检查。

发现新版后展示更新说明，由用户确认下载和安装；不会默认自动下载。更新整个应用，需要重新打开。支持稍后提醒、跳过版本和手动重试。用户已经同意下载并进入安装准备阶段后，Sparkle 的“稍后”可能安排在退出应用时完成安装。

退出或更新会等待正在进行的课程操作结束，不中途终止 Git。未保存的任务或审核内容须选择保存、放弃或取消退出；提交窗口的“检查并提交后更新”会真正提交所选文件并推送个人 fork，失败时暂缓退出。保存校验失败会保留输入。

任务、课程、本机设置和钥匙串授权继续沿用。无法连接更新服务时仍可管理本机任务。下载或签名验证失败不会安装未验证内容；可稍后从菜单重试。只读位置或 macOS 临时隔离位置中的应用应移至“应用程序”。

当前构建仍是临时签名、未经 Apple 公证。更新签名用于验证更新来源，不等同于 Apple 公证。安装包由 GitHub Releases 提供，签名更新清单与说明由 GitHub Pages 提供，均无需 GitHub 登录。更新源缺失时明确提示清单不可用，不会声称已是最新版。断网、超时和服务器故障分别说明原因，支持重试；连接中的检查可取消。1.1.2 及后续版本无需手动配置地址。

手动检查先通过独立、无账户凭据的 HTTPS 请求确认更新服务可访问，随后仍由 Sparkle 下载并验证清单与安装包签名。可访问不代表可信，检查失败不会绕过验证或安装更新。

## 构建与签名

依赖锁定在 `Config/Sparkle.json`：Sparkle 2.10.0 官方二进制及 SHA-256。首次构建联网下载，缓存放在忽略的 `build/dependencies/`；校验不匹配则停止。Command Line Tools 可继续使用，无需完整 Xcode。构建保留框架链接与辅助程序签名，校验完整应用。

`Info.plist` 统一定义显示版本、递增构建号、公开仓库地址 `DDLRepositoryURL`、HTTPS 清单地址和公开 Ed25519 密钥。发布工具从仓库地址生成 Release 下载与 Pages 说明链接，拒绝含凭据的地址或不一致的更新源。1.1 使用构建号 2，1.1.1 使用构建号 3，首个公开版本 1.1.2 使用构建号 4；后续正式构建必须严格递增。当前仅完整 ZIP，不生成增量包。

独立更新私钥由 Sparkle 的 `generate_keys` 存入维护者登录钥匙串，账户名为 `io.github.acemetric.sshomeworkmanager.updates`。应用和仓库只保存公钥；不使用 GitHub App 私钥、GitHub 令牌或 SSH 私钥。签名工具需要系统钥匙串授权，密码只在系统弹窗输入。

维护者须自行保留仓库之外的加密离线备份；不要把导出的私钥放在工作区、云端公开目录、日志或 CI 中。本工具不自动导出私钥。私钥丢失时，当前未使用 Developer ID 的版本通常需要手动安装带新公钥的应用，不能依赖普通自动更新恢复。改编者发布自己的软件时必须使用自己的更新源与密钥，不能沿用本分支公钥而期待能签名更新。

## 准备发布产物

```sh
zsh release.sh
python3 Tools/prepare-update.py --notes /path/to/public-release-notes.md
```

后续版本加 `--previous-feed /path/to/previous-signed-appcast.xml`，脚本先验证旧清单签名与构建号，再保留旧条目。维护者每次后续发布必须传入最新线上清单，不要用首次发布模式绕过版本检查。

`release.sh` 构建、回归、检查签名并扫描源码、历史和产物。更新 ZIP 仅包含 `.app`；安装说明单独生成。`--candidate` 是本机测试包，不参与正式清单。

`prepare-update.py` 读取钥匙串签名，不导出私钥；要求公钥与应用一致，生成并验证 ZIP、清单及 Markdown 更新说明的签名，然后扫描所有待发布文件。产物位于忽略的 `build/releases/update/`。如修改清单或更新说明，必须重新签名。

## 发布顺序

构建和签名脚本只准备本机文件。维护者在检查通过后实际上传 Release 并部署 Pages；不把更新私钥交给 GitHub Actions，也不创建 PR。

1. 检查 `Info.plist` 版本与构建号，完成上述回归、签名与隐私检查。
2. 向个人仓库 `AceMetric/AM-Homework-Helper` 的版本标签 `v<版本>` 发布固定的 ZIP、校验文件、独立安装说明及必要公开文档。已发布的版本附件不原地替换。
3. 确认 Release 附件可通过 HTTPS 下载，且下载内容与本机校验值一致。
4. Pages 使用独立 `gh-pages` 分支的根目录并强制 HTTPS。分支仅含公开首页、`.nojekyll`、`updates/appcast.xml` 与签名 Markdown 更新说明；保持签名字节，不经过 Jekyll 转换。只发布显式选择的文件，不部署整个工作区或 `build/`。
5. 用上一版应用检查公开源，确认新版本、更新说明和升级成功。失败时撤下对应清单条目，重新签名发布；已发布 ZIP 保持不变，用更高构建号发布修复。

固定清单地址：`https://acemetric.github.io/AM-Homework-Helper/updates/appcast.xml`。更新包使用对应 Release 标签的 HTTPS 地址。用户无需登录 GitHub 下载软件更新；更新请求不携带课程访问令牌、课程路径或任务内容。

## 验证

```sh
zsh verify-update.sh
zsh verify-update-integration.sh
```

第一项覆盖退出协调、保存校验、课程操作门控、安装位置与配置。第二项需要图形会话及本机更新签名钥匙串授权，用独立 bundle ID、模拟数据目录和测试钥匙串条目驱动真实 Sparkle 下载、验证、安装与重启；不使用真实课程或登录凭据。测试应用及窗口明确标识“升级测试”，每个场景结束后自动清理测试进程。测试覆盖正常升级、签名及清单篡改、损坏包、版本与系统限制、断网、请求超时和下载中断。测试允许 HTTP 仅限测试应用的本机回环源，发布应用仍使用 HTTPS。每次结果保存在 `build/qa/update-integration/suite-*/results.json`；CI 不需要维护者私钥，仅运行不需要签名私钥的回归。

参考：[Sparkle 接入](https://sparkle-project.org/documentation/programmatic-setup/)、[更新签名](https://sparkle-project.org/documentation/)、[发布清单](https://sparkle-project.org/documentation/publishing/)。

## 正式源验证

正式发布后，从公开 Release 下载并验证 ZIP，解压到忽略的临时目录，再运行：

```sh
python3 Tools/test-public-update.py --app "/path/to/extracted/AM's Homework Helper.app"
```

此测试让真实 Sparkle 读取正式 HTTPS 清单：当前构建号应无更新；仅本机临时副本降低一个构建号，再下载正式包并安装，核对完整应用配置、可执行文件及签名。独立测试驱动器负责重启协调；更新后的正式应用只以不会保存的预览模式打开，然后关闭，不加载真实任务、课程或钥匙串。测试结束恢复更新偏好，报告仅留在忽略的 `build/qa/public-update/`。任务和模拟钥匙串保留由上述隔离完整应用的回环升级测试验证。
