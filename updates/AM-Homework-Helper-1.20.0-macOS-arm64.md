<!-- sparkle-sign-warning:
IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires updating signatures in appcasts that reference this file! This will involve re-running generate_appcast or sign_update.
-->
# AM Helper 1.20.0

- 修复提交核验刷新后列表快照不一致导致的崩溃，过期列表回调安全退出。
- 作业工作台采用紧凑导航和文件、预览、操作三栏，窄窗口逐级切换。
- 右侧直接选择变更、填写说明并提交，复用既有安全检查和推送核验。
- 统一原生 Liquid Glass 操作控件，返回导航固定左侧，预览切换与侧栏标签紧凑排列；保持标签和正文布局稳定。
- 主窗口与录入弹窗适应可用空间，小窗口内部滚动，底部保存操作保持可见。
- 提交草稿按作业与仓库身份隔离保留，后台刷新不覆盖用户输入。
- 新增官方 ChatGPT 登录，识别默认 Luna、内容检查默认 Terra；模型不可用时由用户确认替代。
- 每小时默认最多 60 次请求、并发 2 次，可调整；与官方套餐额度分别管理，不自动切换付费服务。
- 由模型提炼真正的作业交付项与条件，并核对老师原文引用；区分文件检查、内容检查和材料覆盖缺口。
