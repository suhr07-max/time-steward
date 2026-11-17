# 时间安排管家 · Time Steward

原生 macOS 本地时间规划工具，使用 SwiftUI 构建。无需账号，核心功能离线可用。

## 功能

- 自定义任务、起止时间、分类、休息和备注。
- 每天或指定星期重复，多个项目方向按适用日期轮换。
- 当前与下一项安排、系统提醒、菜单栏后台运行。
- 一键记录完成、部分完成、未完成，支持执行备注。
- 日、周、月统计、分类筛选和月历。
- 计划模板、本地备份导出与恢复；历史记录保留。

## 环境与构建

需要 macOS 13+ 和 Apple 命令行开发工具。无第三方依赖。当前仅在 Apple Silicon Mac 上验证；Intel 支持尚未验证。

```sh
git clone https://github.com/suhr07-max/time-steward.git
cd time-steward
swift build
.build/debug/CoreChecks
bash package-app.sh
```

打包脚本在 `dist/` 生成 `.app`、DMG 和 PKG。需要使用打包后的应用测试系统通知，不建议直接运行裸可执行文件。首次使用可从空白添加安排，或选择可自由修改的示例模板。

## 提醒与数据

在应用设置中开启通知，并在 macOS 系统设置中允许通知。关闭窗口后应用仍在菜单栏运行；彻底退出后不保证提醒。提醒队列自动补充未来 30 天内最近 60 条请求。专注模式和系统休眠可能影响展示。

数据使用 Codable JSON 原子写入，保存在 `~/Library/Application Support/TimeSteward/records.json`，不上传至服务器。修改未来计划不会覆盖历史结果。恢复备份前保留当前数据。公开仓库只含通用示例，不含实际用户计划和执行记录。

## 当前状态

0.1.0 本地测试版。核心检查覆盖轮换、历史保护、统计口径、数据迁移、时间校验和示例时长。界面、编译和打包已进行本机检查。长期后台提醒、登录启动、安装向导与备份恢复的完整交互仍需进一步测试。

打包产物采用 ad-hoc 应用签名，未使用 Apple 开发者证书签名或公证，正式分发需自行完成这些步骤。

## 项目结构

- `Sources/StewardCore`：任务、重复规则、轮换、历史与统计。
- `Sources/TimeSteward`：原生界面、存储、模板、备份与通知。
- `Tests/StewardCoreTests`：独立核心检查程序（不依赖 XCTest）。
- `Scripts/icon.swift`：图标生成。
- `package-app.sh`：本机构建与打包。

## License

[MIT](LICENSE)
