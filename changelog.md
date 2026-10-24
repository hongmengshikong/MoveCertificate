## v1.5.7（从 v1.5.6 发布节点分叉：逻辑不变 + 新 WebUI）

- 基线：`v1.5.6` tag（`eede893`）。`post-fs-data.sh` / `service.sh` / `customize.sh`
  与 v1.5.6 发布包**逐字节一致**，未改动任何挂载 / 证书处理逻辑。
- 未新增任何脚本，模块里没有 `sh/` 目录。
- WebUI 换成 v1.7 的新界面，并**按 1.5.6 的能力裁剪**（不是照搬）：
  - 删除「模式」页 / 底部「模式」标签：1.5.6 没有 `mode.conf`，没有可切换的模式；
  - 删除「模块状态」卡片：1.5.6 没有 `sh/status.sh`，没有状态数据来源；
  - 保留：证书列表（生效状态、删除）、运行日志、设置（语言 / 外观 / 版本）；
  - 顶部副标题改为「系统证书迁移」，不再声称 Flutter 修复。
- 附带 `cert_names.json`（证书名称字典，仅 UI 用）。
- 移除 `updateJson`，避免被上游更新覆盖；版本 `v1.5.7` / versionCode 24（bugfix，版本号不变）。

---

- feat(sh): :fire: #45 Compatible with AdGuard
- 1. Compatible with AdGuard, Skip "AdGuard Intermediate CA"
---
- chore(UI): :tada: Adapt to dark mode
---
- Merge pull request #41 from SafaSafari/iyue
- fix android 14 system ca
---
- fix(webui): 🐛 #34 修复识别证书失败
- fix(webui): 🐛 #34 Failed to repair recognition certificate
---
- build(webroot): :fire: 识别证书优化
- build(webroot): :fire: Recognition Certificate Optimization