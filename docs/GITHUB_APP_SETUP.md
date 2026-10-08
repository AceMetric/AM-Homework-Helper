# GitHub 登录、私有课程与迁移

## 四步开始使用

1. **连接账号**：打开应用或侧栏“连接 GitHub”，点“浏览器登录”。复制验证码并打开 GitHub，确认是自己的账户；网页授权对象显示 **GitHub CLI**，即内置的 GitHub 官方登录工具。完成后向导自动继续。
2. **选择课程**：搜索并一次勾选个人课程 fork。软件自动识别老师上游，逐门检测读取权限；失败课程不会阻止其他课程。
3. **准备文件**：选择课程总文件夹，软件只检查该目录及下两层，按 Git 仓库身份匹配。有多个匹配时选择一个；缺少目录的课程可批量下载，已有非空目录不覆盖。点击“关联选定目录”保存。
4. **首次检查**：检查就绪课程，逐门查看作业、考试等结果和失败原因。完成后可查看或跳过操作提示，进入课程或待审核。

向导支持返回、取消和下次继续。已保存课程保留；重新打开不会自动重复首次检查。侧栏“开始使用”提供使用提示及重新运行配置引导。

## 权限与学校登录

无需安装 GitHub App、填写令牌、生成 SSH 密钥或申请学校批准本项目应用。GitHub 官方将 CLI 列为特许 OAuth 应用；组织限制普通 OAuth 应用时，CLI 仍可访问用户已有权限的资源。学校 SSO、双重验证和个人课程权限仍需本人完成。

官方工具默认请求 `repo`、`read:org`、`gist`，权限比勾选的课程更宽。应用仅处理所选课程；令牌在本机钥匙串，不上传给维护者。首次可能出现 macOS 钥匙串访问提示，确认系统窗口即可，密码不应输入应用或发给他人。[工具、安全包装及维护说明](GITHUB_CLI.md)。

检查失败显示“未完成检查”及上次成功时间，零项待审核不代表没有作业。可在对应课程重试；完整错误收进“详情”。应用不发送管理员申请、不自动切回本项目 OAuth。

## 旧版本迁移

新版本默认用官方登录，需要完成一次新版浏览器连接。任务、课程及原目录保留；重新核验后可复用，即使 remote 使用 SSH，软件也使用身份核验后的 HTTPS，不修改原 remote 或全局 Git 设置。

官方 CLI、旧 OAuth、旧 GitHub App 的本应用凭据分别保存。高级登录设置可明确选择旧方式，不自动回退。

**新登录不会撤销旧 GitHub App 安装。** 请在 [安装设置](https://github.com/settings/installations) 移除不再使用的 SS Homework Manager。退出登录只删除当前本应用凭据；撤销 GitHub CLI 授权可能同时影响其他官方 CLI 工具，需在 GitHub 授权管理中自行处理。

## 维护者配置

默认方式不需要注册本项目 OAuth 应用或保存 Client Secret。构建下载并校验固定的官方 CLI，随应用签名和更新，不在用户电脑全局安装工具。

`Config/GitHubApp.plist` 保留旧 OAuth 的公开 `oauthClientID` 与旧 App 的公开 `clientID`、`installationURL`，只用于兼容。自行维护旧 OAuth 时应注册自己的公开身份、开启设备登录，并遵循组织策略；这不是默认首次配置步骤。

---

以下为旧版兼容配置，普通用户无需操作。

# 旧 GitHub App 配置与兼容登录

GitHub App 是软件在 GitHub 上的公开身份，不是你的账户密码。维护者只注册一次，同学通过浏览器选择允许访问的个人课程 fork。应用运行无需服务端、App 私钥或 Client Secret。GitHub 注册后台可能要求维护者首次生成 App 私钥后才允许安装；该密钥只由维护者保管，不能分发或加入本项目。

## 使用已配置的测试包

同学可直接点击侧栏账户入口的“安装授权…”和“登录 GitHub”，无需自行注册。当前公开配置沿用已注册的 **SS Homework Manager**；桌面应用更名为 AM's Homework Helper 后，Client ID、安装入口和已有授权继续沿用。

原作者若采用独立的 GitHub App，只需按下面的流程注册并替换两项公开配置。

## 维护者操作

1. 登录 GitHub，打开 [新建 GitHub App](https://github.com/settings/apps/new)。
2. 名称可使用 `AM Homework Helper` 或对应的公开项目名；被占用时添加维护者后缀。
3. Homepage URL 填项目公开仓库页面。Description 可填“macOS 课程作业与截止时间管理；只向当前用户自己的 fork 提交”。
4. 保留 **Expire user authorization tokens**；勾选 **Enable Device Flow**。
5. 取消 **Request user authorization (OAuth) during installation**。本应用随后通过设备码授权，Callback URL 和 Setup URL 留空。
6. Webhook 的 **Active** 取消勾选，无需服务器地址或 Webhook Secret。
7. Repository permissions 只设置 **Contents: Read and write**；**Metadata: Read-only** 自动保留。其他仓库、组织、账户权限均不申请。
8. “Where can this GitHub App be installed?” 选择 **Any account**，然后 Create GitHub App。
9. 注册页面复制公开 **Client ID**（不是数字 App ID）；公开安装 URL 形如 `https://github.com/apps/实际应用名称/installations/new`。
10. 把两项填入 `Config/GitHubApp.plist`：`clientID` 和 `installationURL`。可公开提交这两项。开发期间也可在侧栏“设置 → 高级：GitHub App…”填写。
11. **不要生成 Client Secret，也不要复制任何秘密到配置**。若注册成功页面要求先生成 Private Key 才能安装，由维护者本人点击 Generate a private key，将下载的 PEM 保存到仓库之外、限制读取权限。该密钥可签发安装令牌，不能上传、不能发给同学或发到开发聊天。本应用只使用设备授权，不读取这把密钥。
12. 安装时选择 **Only select repositories**，只勾选自己的课程 fork。完成后运行发布前验证并用设备登录联调。

## 同学操作

在预配置的应用点“安装授权…”，安装到自己的账户，选择课程 fork；回到应用点“登录”，在 GitHub 输入屏幕显示的设备码。再“添加 fork”。老师无需安装本 App；私有上游读取使用该同学 Mac 上已有的 Git 访问权限。

若看不到 fork，检查 App 的安装账户、所选仓库和设备登录账户是否一致。组织的 SSO / 仓库策略可能还需要学校授权。

## 官方依据

- [注册设置、权限与安装范围](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app)
- [设备授权流程](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app)
- [设备授权得到的令牌刷新不需要 Client Secret](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens)

## 当前公开配置

2026-10-04 已在 AceMetric 账户完成注册，名称 SS Homework Manager。

- 公开 Client ID：`Iv23liW7trz271V8cdSb`。
- [公开安装页面](https://github.com/apps/ss-homework-manager/installations/new)。
- Contents read/write、Metadata read-only；Device Flow 已启用，Webhook 关闭，其余权限关闭。
- App 已完成注册与安装准备。私钥由维护者在仓库之外保管；桌面应用不使用这把私钥，也不包含 Client Secret。

以上按 2026-10-04 官方说明及实际注册页面核对。这是旧 App 注册记录；网页登录及 App 安装不等于桌面应用已经登录。
