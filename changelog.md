## v1.5.7-webui（从 v1.5.6 发布节点分叉：逻辑不变 + 新 WebUI）

- 基线：`v1.5.6` tag（`eede893`）。`post-fs-data.sh` / `service.sh` / `customize.sh`
  与 v1.5.6 发布包**逐字节一致**，未改动任何挂载 / 证书处理逻辑。
- 未新增任何脚本，模块里没有 `sh/` 目录。
- 仅替换 WebUI：使用 v1.7 的新界面（证书列表、日志、设置、深色 / 浅色 / 跟随系统、语言弹层）；
  新 UI 的「模块状态」页没有后端脚本，会显示「状态不可用」，其它页面正常。
- 附带 `cert_names.json`（证书名称字典，仅 UI 用）。
- 移除 `updateJson`，避免被上游更新覆盖；版本 `v1.5.7-webui` / versionCode 24。

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