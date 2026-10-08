# GitHub 登录、私有课程与迁移

## 同学首次使用

1. 点击侧栏“连接 GitHub”，复制设备码并打开 GitHub；确认登录的是自己的账号。
2. 授权 AM's Homework Helper 的私有仓库访问，再回到应用。令牌只存本机，无需 SSH、手填 token 或安装 GitHub App。
3. 一次勾选个人课程 fork。应用自动确认老师上游并逐课核验内容读取权限。
4. 选择课程总文件夹，按 Git 身份匹配已有目录。多个匹配需选择；未找到时可选择一次下载位置，批量下载。
5. 点击“关联选定目录”，成功后“开始检查”。单课失败不影响其他课程，可稍后重试。

## 权限和学校限制

OAuth 使用 `repo`，GitHub 授权范围比应用内所选课程更宽，不能宣称只授予这几门课。应用禁止向老师推送，不上传令牌或课程数据给维护者。学校组织可能限制第三方 OAuth 或要求 SSO；按错误提示申请批准、完成学校登录再重新检测，软件不能绕过组织政策。

检查失败会保留上次结果，并标明“未完成检查”；零条审核结果不代表老师没有作业。课程“更多”提供恢复访问和已隐藏凭据的操作详情。

## 旧版本迁移

升级后默认使用 OAuth，需要重新浏览器登录一次。任务、课程和原目录保留；即使 origin/upstream 是 SSH 地址，OAuth 模式也使用核验后的 HTTPS 地址，不修改原 remote 或全局 Git 设置。已有关联目录会重新核验后复用。

**新登录不会撤销旧 GitHub App 安装。** 完成配置后可在 [GitHub 安装设置](https://github.com/settings/installations) 卸载旧 SS Homework Manager。只删除本机旧令牌也不等于撤销安装。高级登录设置保留旧方式，切换不自动回退或删除另一种凭据。

## 维护者一次性配置

注册独立 OAuth App，Homepage 与必填 Redirect URI 填本项目公开首页，开启 Enable Device Flow；默认保留令牌到期。实际使用设备流程，不使用网页重定向认证。不要启用通配重定向，不生成或保存 Client Secret。公开配置 `Config/GitHubApp.plist` 增加 `oauthClientID`；现有 `clientID`、`installationURL` 仅用于旧兼容方式。

公开 OAuth Client ID：`Ov23libEk0uJm0Dg9t2c`。设备登录与设备令牌刷新均无需客户端密钥。复制项目的维护者应注册自己的 OAuth App，不能冒用本项目身份。默认构建必须包含公开 OAuth ID。

- [官方设备登录及刷新流程](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps)
- [OAuth 授权范围](https://docs.github.com/en/apps/oauth-apps/using-oauth-apps/authorizing-oauth-apps)
- [学校组织审批](https://docs.github.com/en/account-and-profile/how-tos/organization-membership/requesting-organization-approval-for-oauth-apps)

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
