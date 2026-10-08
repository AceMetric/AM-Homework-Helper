# 内置 GitHub 官方登录工具

应用内置未经修改的 GitHub CLI 2.101.0（macOS arm64），无需用户安装命令行工具。下载版本、官方地址和 SHA-256 固定在 `Config/GitHubCLI.json`；构建时核验归档，每次从已验证归档提取工具。保留官方 Developer ID 签名，应用启动登录前再次核验可执行文件完整哈希；工具不自行升级、不安装扩展。许可证随应用提供。

## 登录过程

应用以固定参数运行 `gh auth login --hostname github.com --web --skip-ssh-key`，标准输入不可交互；验证码显示在原生向导，由用户复制并打开 GitHub。不会打开终端、运行 `auth setup-git`、设置 git protocol、上传 SSH 密钥或更改用户的 Git 配置。

授权对象是 **GitHub CLI**，默认权限 `repo`、`read:org`、`gist` 比选择的课程范围更宽。GitHub 将 CLI 列为特许 OAuth 应用，允许其在限制普通 OAuth 应用的组织中访问用户已有权限的资源。软件不提供本项目应用的学校批准申请；GitHub 登录、双重验证、学校 SSO 和课程访问权限仍由用户本人完成。

## 只允许钥匙串存储

CLI 在钥匙串失败时可能明文写配置，因此应用不能直接使用默认登录行为。包装器使用专用配置目录和最小环境，子进程受 macOS 写入限制：普通文件与临时目录不可写，仅允许 `/dev/null` 与当前用户的加密钥匙串目录。系统不支持保护规则、钥匙串拒绝访问或本应用保存失败时停止登录，不允许明文回退。

官方 CLI 的 macOS keyring 使用 `/usr/bin/security -i` 的标准输入传递密码。应用不把令牌放进参数、URL、日志或导出文件，关闭 CLI 遥测、调试和更新通知。配置目录只保存不含令牌的公共偏好和本机登录锁。

通过与官方 keyring 相同的系统钥匙串工具读取凭据，输出仅留内存，不转发到日志。登录前在内存中记录原 CLI 钥匙串项；登录后只接受本次可核验的新凭据，核对账户及实际授权范围，再存入本应用的 `github.cli` 凭据项。配置写入被保护规则阻止导致非零退出时，只有本次钥匙串、账户和权限核验全部成功才视为登录成功。成功文案不作为凭据证据。

恢复原 CLI 登录时只处理本次识别出的共享项，恢复前比较数据与修改时间；其他进程再次修改的项保持原样。来源不明确、并发登录无法核验时停止连接。登录期间建议完成或关闭其他 GitHub 工具的登录流程。

退出登录只删除本应用的当前凭据，不自动撤销所有工具共用的 GitHub CLI 远端授权。要撤销时前往 [GitHub 授权管理](https://github.com/settings/applications)，留意其他 CLI 工具也可能受影响。

## 维护和验证

- `zsh verify-github-cli.sh`：凭据解码、环境限制、恢复与并发修改保护、账户／权限核验、取消与保存失败。
- `python3 Tools/test-cli-sandbox.py`：在真实 macOS 使用一次性模拟钥匙串项，验证文件回退受阻、钥匙串存储可用，完成后清理。
- `Tests/CLIKeychainIntegration.m`：一次性系统钥匙串验证真实快照、恢复及其他进程修改保护，结束后删除测试项。
- `Tests/OfficialLoginIntegration.m`：本机隔离浏览器登录及私有课程只读联调；使用独立测试钥匙串和数据目录，实际课程配置仅在忽略目录准备。
- 不修改官方工具或复制其身份常量来实现自制认证。旧本项目 OAuth / GitHub App 配置仅用于显式选择的兼容模式。

来源：[GitHub 特许应用](https://docs.github.com/en/apps/oauth-apps/using-oauth-apps/privileged-oauth-apps)、[官方登录与存储说明](https://cli.github.com/manual/gh_auth_login)、[固定发行版本](https://github.com/cli/cli/releases/tag/v2.101.0)。
