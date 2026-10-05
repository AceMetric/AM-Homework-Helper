# 软件更新与本机发布

## 用户使用

DDL-Manager 1.1 起支持应用内更新。旧版本需先手动安装一次 1.1；把应用放在“应用程序”中，再从应用菜单选择“检查更新…”。“设置 → 软件更新”可以关闭默认每 24 小时一次的检查。

发现新版后展示更新说明，由用户确认下载和安装；不会默认自动下载。更新整个应用，需要重新打开。支持稍后提醒、跳过版本和手动重试。用户已经同意下载并进入安装准备阶段后，Sparkle 的“稍后”可能安排在退出应用时完成安装。

退出或更新会等待正在进行的课程操作结束，不中途终止 Git。未保存的任务或审核内容须选择保存、放弃或取消退出；提交窗口的“检查并提交后更新”会真正提交所选文件并推送个人 fork，失败时暂缓退出。保存校验失败会保留输入。

任务、课程、本机设置和钥匙串授权继续沿用。无法连接更新服务时仍可管理本机任务。下载或签名验证失败不会安装未验证内容；可稍后从菜单重试。只读位置或 macOS 临时隔离位置中的应用应移至“应用程序”。

当前构建仍是临时签名、未经 Apple 公证。更新签名用于验证更新来源，不等同于 Apple 公证。正式 GitHub Releases 与 Pages 更新源尚未发布，首次公开发布前检查更新可能失败。

## 构建与签名

依赖锁定在 `Config/Sparkle.json`：Sparkle 2.10.0 官方二进制及 SHA-256。首次构建联网下载，缓存放在忽略的 `build/dependencies/`；校验不匹配则停止。Command Line Tools 可继续使用，无需完整 Xcode。构建保留框架链接与辅助程序签名，校验完整应用。

`Info.plist` 统一定义显示版本、递增构建号、HTTPS 清单地址和公开 Ed25519 密钥。1.1 使用构建号 2，后续正式构建必须严格递增。当前仅完整 ZIP，不生成增量包。

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

脚本只准备本机文件，不创建 Release、不启用 Pages、不上传文件、不创建 PR。

1. 检查 `Info.plist` 版本与构建号，完成上述回归、签名与隐私检查。
2. 向个人仓库 `AceMetric/DDL-Manager` 的版本标签 `v<版本>` 发布固定的 ZIP、校验文件、独立安装说明及必要公开文档。已发布的版本附件不原地替换。
3. 确认 Release 附件可通过 HTTPS 下载，且下载内容与本机校验值一致。
4. 将签名 `appcast.xml` 和对应版本的签名 Markdown 更新说明原样放到 GitHub Pages 的 `updates/` 目录。只发布显式选择的这些文件，不部署整个工作区或 `build/`。
5. 用上一版应用检查公开源，确认新版本、更新说明和升级成功。失败时撤下对应清单条目，重新签名发布；已发布 ZIP 保持不变，用更高构建号发布修复。

固定清单地址：`https://acemetric.github.io/DDL-Manager/updates/appcast.xml`。更新包使用对应 Release 标签的 HTTPS 地址。用户无需登录 GitHub 下载软件更新；更新请求不携带课程访问令牌、课程路径或任务内容。

## 验证

```sh
zsh verify-update.sh
zsh verify-update-integration.sh
```

第一项覆盖退出协调、保存校验、课程操作门控、安装位置与配置。第二项需要图形会话及本机更新签名钥匙串授权，用独立 bundle ID、模拟数据目录和测试钥匙串条目驱动真实 Sparkle 下载、验证、安装与重启；不使用真实课程或登录凭据。测试应用及窗口明确标识“升级测试”，每个场景结束后自动清理测试进程。测试覆盖正常升级、签名及清单篡改、损坏包、版本与系统限制、断网、请求超时和下载中断。测试允许 HTTP 仅限测试应用的本机回环源，发布应用仍使用 HTTPS。每次结果保存在 `build/qa/update-integration/suite-*/results.json`；CI 不需要维护者私钥，仅运行不需要签名私钥的回归。

参考：[Sparkle 接入](https://sparkle-project.org/documentation/programmatic-setup/)、[更新签名](https://sparkle-project.org/documentation/)、[发布清单](https://sparkle-project.org/documentation/publishing/)。
