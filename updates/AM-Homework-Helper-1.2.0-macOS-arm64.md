<!-- sparkle-sign-warning:
IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires updating signatures in appcasts that reference this file! This will involve re-running generate_appcast or sign_update.
-->
# AM's Homework Helper 1.2.0

适用于 macOS 13+、Apple 芯片；构建号 5。使用临时签名，未经 Apple 公证。

## 作业识别

- 免费规则提取作业名称、内容概括和提交要求，显示完整活动原文及仓库内文档附件。
- 修复“作业目标”等小标题截断、模型引用提交说明导致重复候选的问题。
- 完整明确日期的新作业可自动加入，支持撤销本次加入；相对日期、缺失时间、历史材料及模型新发现仍待审核。
- 可选已安装的 Ollama 本地模型或用户配置的云 API，初始关闭。云端只处理勾选课程，密钥保存在钥匙串并绑定服务地址，每日最多20次请求，失败计入。
- 提供可选手动 Skill 导出 / 导入，重新核验来源版本及原文，结果统一进入审核。

## 界面与使用

- 审核和设置改用嵌入主窗口的 SwiftUI，日历与核心执行层继续使用 AppKit。
- 列表旁直接编辑、多选确认、保存并下一项，保留个人DDL、自定义标题和未保存输入。
- 侧栏使用单行 AM Helper，隐藏重复长标题；浅深外观自动跟随系统。
- 任务支持批量完成与撤销，排序随页面保存；多行备注正常换行，⌘Return保存。
- 备份导入增加数量、重复和冲突预览，保存前保留恢复副本；批量保存失败不出现部分导入。

## 兼容与验证

任务、课程、提醒、内部标识、更新公钥和钥匙串服务继续沿用。原有个人fork身份核验、所选文件检查及禁止推送老师仓库的限制保留。

三门课程14份老师文档的规则与本地模型核对得到7份作业和1组考试，来源及规则日期一致。836项原生断言、更新工具和隐私检查通过；真实更新覆盖安装重启、签名错误、网络失败等10种回环场景。macOS13兼容性通过构建检查，实际运行验收在当前Mac上进行；未进行付费云服务联调。

1.1.2用户可在应用菜单选择“检查更新…”。更早测试版请从GitHub Releases手动安装一次最新版。完整使用说明见项目README及 docs/RECOGNITION.md。
