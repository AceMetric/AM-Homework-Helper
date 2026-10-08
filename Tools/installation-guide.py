#!/usr/bin/env python3
import sys
import plistlib
from pathlib import Path
from distribution import update_locations

version = sys.argv[1]
info = plistlib.loads((Path(__file__).resolve().parents[1] / 'Info.plist').read_bytes())
name, archive_name = info['CFBundleName'], info['DDLArchiveName']
repository, _, _ = update_locations(info)
Path(f'build/releases/{archive_name}-{version}-installation-guide.txt').write_text(f'''{name} {version} · macOS 13+ · Apple 芯片

此包使用临时签名，未经 Apple 公证。退出旧版，解压后将 {name}.app 拖入“应用程序”。首次打开若被阻止，在系统设置 → 隐私与安全性中按系统提示选择“仍要打开”。

从 DDL-Manager 或 AM's Homework Helper 1.1 / 1.1.1 测试版升级时，须手动安装本版一次。退出旧版后替换旧应用，勿同时运行两个版本；任务、课程绑定和登录信息会继续沿用。旧测试版的更新地址不再使用。

本版通过公开 HTTPS 更新源提供“检查更新…”和“设置 → 软件更新”；默认每天检查，由你确认下载和安装，无需登录 GitHub。升级时等待课程操作结束，并处理未保存内容。断网、超时和服务故障分别说明原因，可稍后重试，不影响本机任务使用。

首次打开跟随四步引导：浏览器登录 → 多选个人课程 fork → 批量关联或下载 → 首次检查。内置 GitHub CLI 官方工具，无需安装命令行工具、GitHub App、生成 SSH 密钥或申请学校批准本项目应用。旧版本需完成一次新版连接，任务和课程目录保留。GitHub CLI 请求 repo、read:org、gist，权限比所选课程宽，令牌只存本机钥匙串；个人登录、双重验证、学校 SSO 和已有课程权限仍需本人完成。侧栏“开始使用”可重看四种日常操作或重新运行引导。旧 GitHub App 安装不自动撤销，请在 GitHub 设置中单独卸载不再使用的安装；“待审核作业”集中核对老师原文与截止时间。相对日期需确认完整截止时间。所有推送只到已核验属于当前用户的个人 fork。

旧测试版的数据与钥匙串授权继续沿用；原版 DDL Manager 请先导出备份，再导入。更新签名私钥不包含在应用中；登录令牌只存在本机钥匙串。

提醒需要系统通知权限；退出、关机或休眠时无法定时扫描。完整公开说明见 {repository} 。
''')
