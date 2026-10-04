# 一次性注册 GitHub App

GitHub App 是软件在 GitHub 上的公开身份，不是你的账户密码。维护者只注册一次，同学通过浏览器选择允许访问的个人课程 fork。应用运行无需服务端、App 私钥或 Client Secret。GitHub 注册后台可能要求维护者首次生成 App 私钥后才允许安装；该密钥只由维护者保管，不能分发或加入本项目。

## 维护者操作

1. 登录 GitHub，打开 [新建 GitHub App](https://github.com/settings/apps/new)。
2. 名称建议 `SS Homework Manager`，名称被占用时加公开项目名后缀。
3. Homepage URL 填项目公开仓库页面。Description 可填“macOS 课程作业与截止时间管理；只向当前用户自己的 fork 提交”。
4. 保留 **Expire user authorization tokens**；勾选 **Enable Device Flow**。
5. 取消 **Request user authorization (OAuth) during installation**。本应用随后通过设备码授权，Callback URL 和 Setup URL 留空。
6. Webhook 的 **Active** 取消勾选，无需服务器地址或 Webhook Secret。
7. Repository permissions 只设置 **Contents: Read and write**；**Metadata: Read-only** 自动保留。其他仓库、组织、账户权限均不申请。
8. “Where can this GitHub App be installed?” 选择 **Any account**，然后 Create GitHub App。
9. 注册页面复制公开 **Client ID**（不是数字 App ID）；公开安装 URL 形如 `https://github.com/apps/实际应用名称/installations/new`。
10. 把两项填入 `Config/GitHubApp.plist`：`clientID` 和 `installationURL`。可公开提交这两项。开发期间也可在课程窗口“Client ID…”填写。
11. **不要生成 Client Secret，也不要复制任何秘密到配置**。若注册成功页面要求先生成 Private Key 才能安装，由维护者本人点击 Generate a private key，将下载的 PEM 保存到仓库之外、限制读取权限。该密钥可签发安装令牌，不能上传、不能发给同学或发到开发聊天。本应用只使用设备授权，不读取这把密钥。
12. 安装时选择 **Only select repositories**，只勾选自己的课程 fork。完成后运行发布前验证并用设备登录联调。

## 同学操作

在预配置的应用点“安装授权…”，安装到自己的账户，选择课程 fork；回到应用点“登录”，在 GitHub 输入屏幕显示的设备码。再“添加 fork”。老师无需安装本 App；私有上游读取使用该同学 Mac 上已有的 Git 访问权限。

若看不到 fork，检查 App 的安装账户、所选仓库和设备登录账户是否一致。组织的 SSO / 仓库策略可能还需要学校授权。

## 官方依据

- [注册设置、权限与安装范围](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app)
- [设备授权流程](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app)
- [设备授权得到的令牌刷新不需要 Client Secret](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens)

## 本项目登记信息

2026-10-04 已在 AceMetric 账户完成注册，名称 SS Homework Manager。

- 公开 Client ID：`Iv23liW7trz271V8cdSb`。
- [公开安装页面](https://github.com/apps/ss-homework-manager/installations/new)。
- Contents read/write、Metadata read-only；Device Flow 已启用，Webhook 关闭，其余权限关闭。
- 维护者已亲自完成首次私钥准备并确认保存在仓库之外，已将 App 安装到本人明确授权的三个个人课程 fork。开发工具未生成、读取或保存 App 私钥，也未创建 Client Secret。

以上按 2026-10-04 官方说明及实际注册页面核对。用户设备授权与课程仓库联调仍待完成；网页登录及 App 安装不等于桌面应用已经登录。
