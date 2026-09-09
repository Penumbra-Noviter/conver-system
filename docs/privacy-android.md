# Conver System 移动端 — Android 隐私清单（Privacy Policy Deck）

> **用途**：Android 数据安全表单（Play Console）填报备查。逐节给出数据流结论（数据在何
> 设备 / 是否出网 / 出网目的与触发者），第三节的「零第三方 SDK 追踪」由机器审计实证
> （`scripts/privacy_audit.py` + pytest），不靠记忆。
> **口径界定**：「收集」= **数据上传至第三方服务器**。本机存储不是收集；用户主动触发的
> 功能联网请求（目的地为 App 自有业务端点）不是「向第三方上传」。

---

## 权限声明（与 AndroidManifest 机器核对一致）

| 项 | 值 | 位置 |
|---|---|---|
| 权限集合 | **仅 `android.permission.INTERNET`** | `android/app/src/main/AndroidManifest.xml` L4 |
| 明文回环豁免 | `base-config cleartextTrafficPermitted="false"`；仅 `127.0.0.1` / `localhost`（`includeSubdomains=false`）放行明文 | `android/app/src/main/res/xml/network_security_config.xml` |

核对命令（读取 manifest 的 `uses-permission` 行集合）：

```bash
grep -o 'uses-permission[^>]\+' android/app/src/main/AndroidManifest.xml
# 输出：uses-permission android:name="android.permission.INTERNET"/  （唯一一行）
```

- 无相机 / 定位 / 存储 / 通讯录等任何运行时权限，无 `android.permission.READ/WRITE_EXTERNAL_STORAGE`。
- 明文面收缩到回环：除 `127.0.0.1` / `localhost` 外的任何域名（含同网段 LAN IP 与公网）
  **明文 http 一律被拦**（模拟器本地 HTTP 托管用，见 §②）。
- 升级到 M7 发布包**不索要任何新权限**（零新权限纪律，spec §"零新权限纪律"）。

**结论**：App 持有唯一一个权限 INTERNET，仅用于下述两类联网（§②）；其余一切能力
（文件选择、分享面板、WebView、系统安全存储）均由系统 intent/框架提供，不构成权限。

---

## ① 本机存储：数据不出设备

数据流（数据在何设备 / 是否出网 / 出网目的与触发者）：

| 数据 | 存储位置（设备内） | 是否出网 | 说明 |
|---|---|---|---|
| 角色卡 / 对话 / 消息 / 设置 | `drift` 本地 SQLite（App 应用私有目录） | 否 | 全部数据驻留设备，无任何定时/后台/静默同步 |
| API Key（Claude / OpenAI 两槽位） | `flutter_secure_storage`（Android Keystore 系统安全存储） | 否 | 写入经 API Key 注入面直连用户配置端点，见 §② |
| 模拟器 22 款种子 HTML + 存档 | App 应用文档目录（`path_provider`），`assets/simulators/` 随包 | 否 | 存档只写设备内；目录墙约束文件访问 |

**结论**：本机存储全部落在设备内，不设任何远程备份 / 云同步 / 遥测通道，因此本机存储
**不构成「收集」**（口径：收集 = 上传至第三方服务器）。

---

## ② 功能必需传输：仅用户主动请求联网

出网请求目的地类型与触发条件：

| 目的地类型 | 协议 | 触发者（用户主动） | 传输内容 |
|---|---|---|---|
| 用户配置的 LLM Provider 端点（Claude / OpenAI 及兼容 `base_url`，如 `api.anthropic.com` / `api.openai.com`） | HTTPS（明文一律被拦，见权限声明） | 用户发送聊天消息 / 用户触发文档解析 / 用户在设置页测试连接 | 本次请求的消息与用户自己填写的 Key（Key 只发往用户配置的端点） |
| 模拟器本地 HTTP 托管 `127.0.0.1:8642`（`dart:io` HttpServer + WebView） | 明文 http（仅回环豁免） | 用户打开模拟器运行页 | WebView 加载本机托管页面，不出设备 |

**结论**：全 App 的出网动作共一类——用户**主动请求**时，向**用户自己配置的 LLM 提供商**
在 HTTPS 上发一次业务请求；请求目的地、触发时机、携带内容全部由用户操作决定。App
自身没有自有服务器，不以任何时机向非用户指定端点发包。明文 http 只存在于设备回环接口，
不形成设备出网。因此本节**不构成「收集」**（无向第三方服务器的上传）。

---

## ③ 零第三方 SDK 追踪：依赖审计实证

**结论**：依赖树（直接 + 传递全量）命中追踪 / 统计 / 崩溃上报 SDK 排除名单条数为 **0**。
机器断言，见下方审计命令复跑。

### 实证命令（可复跑）

```bash
# 1）CLI 全量审计（读 pubspec.lock 直接+传递，输出命中名单；退出码 0 = 通过）
python scripts/privacy_audit.py

# 2）pytest 契约 + 行覆盖门（被测模块 = scripts/privacy_audit.py，失败基线 90%）
python -m pytest scripts/test_privacy_audit.py --cov=scripts.privacy_audit --cov-fail-under=90

# 3）等价交叉验证：flutter 依赖树全文扫描上述名单
flutter pub deps | grep -iE "firebase|appsflyer|amplitude|mixpanel|sentry|crashlytics|adjust|braze|branch|clevertap|kochava"
```

> 注：命令 2 用模块名形式 `--cov=scripts.privacy_audit`（coverage 7.15 将带 `.py` 的
> 非目录 source 归类为模块名而无法采集，文件形式输出 0 数据；二者测的是同一文件
> `scripts/privacy_audit.py`）。

### 排除名单（scripts/privacy_audit.py，包名子串命中）

```
appsflyer | firebase | amplitude | mixpanel | sentry |
crashlytics | adjust | braze | branch | clevertap | kochava
```

名单以「vendor 锚点子串」覆盖该 vendor 旗下全部包（如 `appsflyer_sdk`、
`sentry_flutter`、`firebase_crashlytics`）。名单变更须与本清单同步。

### 审计口径（机器可复读）

- 输入：`pubspec.yaml`（直接依赖声明）+ `pubspec.lock`（pub 解析后的直接+传递全量事实来源）。
- 输出：命中名单；pubspec.yaml 声明但 lock 未解析的直接依赖（**lock 过期**）同样报警——
  因此「新增依赖后先 `flutter pub get` 再审计」是零收集结论成立的前提。
- 模块级入口：`from scripts.privacy_audit import audit_project, TRACKING_PATTERNS`
  （或 `PYTHONPATH=scripts` 后 `from privacy_audit import ...`），T04 发布门禁可直接复用。

### 依赖证据（2026-09-09，`flutter pub deps`，Flutter SDK 3.47.2 / Dart 3.13.2）

直接依赖 18 项，全部为功能库或发布工具链（无 `firebase` / `sentry` / `mixpanel` / 等）：

```
crypto 3.0.7 | cupertino_icons 1.0.9 | dio 5.11.0 | drift 2.34.3 |
drift_flutter 0.3.1 | drift_dev 2.34.5（dev） | file_picker 12.1.2 |
flutter_markdown_plus 1.0.12 | flutter_secure_storage 11.0.0 |
path_provider 2.1.6 | provider 6.1.5+1 | share_plus 13.3.0 |
webview_flutter 4.14.1 | build_runner 2.16.0（dev） | flutter_lints 6.0.0（dev） |
flutter_launcher_icons 0.14.4（dev，发布图标生成） | flutter / flutter_test（SDK）
```

`pubspec.lock` 全量 133 个包名对排除名单命中 **0**（`python scripts/privacy_audit.py` 实证，
`flutter pub deps` 全文扫描亦 0 命中）。
`drift`、`dio`、`flutter_secure_storage`、`webview_flutter`、`share_plus`、
`path_provider` 等既有功能库经 pytest 负向断言**不命中**名单。

### 变更纪律

未来任何新增依赖（**含传递依赖**）必须先过 `python scripts/privacy_audit.py`：
`flutter pub get` 刷新锁文件 → 审计 → 命中 0 方可合入。本清单的「零收集」从提交之日起
是一个可辩护的测试结论，而不是记忆。

---

## 结论速览

| 维度 | 结论 |
|---|---|
| 权限 | 仅 INTERNET + 明文回环豁免（manifest 机器核对） |
| 本机存储 | drift SQLite + 系统安全存储，数据不出设备 |
| 功能性传输 | 仅用户主动请求 → 用户配置的 LLM 端点（HTTPS），无自有服务器 |
| 第三方 SDK | 追踪 / 统计 / 崩溃上报 SDK：**0**（133 包全量审计实证） |
| 数据上传第三方服务器 | **0**（口径：收集 = 上传至第三方服务器） |