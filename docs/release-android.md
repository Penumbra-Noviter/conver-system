# Conver System 移动端 — Android 发布手册（Release Runbook）

> **用途**：Android 发布的唯一操作手册——版本号怎么加、包怎么出、签名怎么核对、
> 侧载怎么装、keystore 怎么管。发布负责人照此执行即可完成一次可上架、可侧载的发布。
> 与本手册配读：[docs/privacy-android.md](privacy-android.md)（数据安全表单填报依据，
> 本手册不复制其内容，只引用）。
>
> **适用范围**：当前仅 Android（M7 交付范围）。iOS 全部延后——Windows 开发机无
> macOS/Xcode 构建路径（设计文档 §7.1 既定），iOS 禁止在本机生成任何产物，TICKETS
> 中 M7 已标注「Android 范围收窄，iOS 延后」。

---

## 1. 版本策略（唯一事实来源）

版本号 `MAJOR.MINOR.PATCH+BUILD`（Flutter pubspec `version`）与 Android
`versionCode` / `versionName` 的对应关系沿用 Flutter 语义（gradle 从 pubspec
透传，`build.gradle.kts` 不单独维护版本号）：

| Flutter `version` | Android | 说明 |
|---|---|---|
| `1.0.0+1` | versionName=`1.0.0` / versionCode=`1` | **首发基线**（M7 定版，不得回退） |
| `+BUILD` 段 | versionCode | 单调递增整数；Android 以此判定新旧、阻止降级安装 |
| `MAJOR.MINOR.PATCH` 段 | versionName | 展示给用户；同上架页面「版本」列 |

**递增规则（每次发布只允许从当前基线向前，不得顺手改小）**：

| 变更类型 | 示例 | 动作 |
|---|---|---|
| 任何一次发布 | 每次发版 | `BUILD` **+1**（versionCode 单调递增，强制） |
| bugfix 发布 | 修复崩溃 / 文案错误 | `PATCH` +1 |
| 新功能 | 新增页面 / 能力 | `MINOR` +1 |
| 破坏性变更 | 数据格式不兼容 / 界面重构 | `MAJOR` +1 |

**规则语义**：
- `BUILD +1` 是硬性要求（versionCode 必须先 +1）；`MAJOR.MINOR.PATCH` 段按变更
  类型可选提升。
- 例：基线 `1.0.0+1` → 首次 bugfix 发布 `1.0.1+2`；首个新功能 `1.1.0+3`。
- 修改位置：根目录 `pubspec.yaml` 的 `version:` 行，然后 `flutter pub get`。
- 验证：发布后抽查包内 versionCode / versionName（见 §3 核对步骤）。

---

## 2. 发布命令链（双产物）

每次发布产出 **一式两份、同签名** 的产物：

- `app-release.aab` —— **上报 Google Play**（Play 从此 AAB 生成各设备优化包）；
- `app-release.apk` —— **侧载分发**（真机手动安装；与 AAB 同证书 → 侧载包等于
  上架包，无签名差异风险）。

```bash
# 环境（Windows + Git Bash）：Flutter 3.47.2 不在 PATH 时
export PATH="/d/Desktop/tools/Cache/Flutter/flutter/bin:$PATH"

# 0）版本前置确认（改号前先看当前基线）
grep '^version:' pubspec.yaml          # 应如 version: 1.0.0+1

# 1）AAB（上架）
flutter build appbundle --release
# 产物：build/app/outputs/bundle/release/app-release.aab

# 2）APK（侧载，universal 单包）
flutter build apk --release
# 产物：build/app/outputs/apk/release/app-release.apk

# 3）签名核对（每条发布必做，判据详见 §3）
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
"$ANDROID_HOME/build-tools/36.0.0/apksigner.bat" verify --print-certs \
    build/app/outputs/apk/release/app-release.apk
```

> **产物路径说明**：本仓库 `android/build.gradle.kts` 将 build 目录重定向到仓库根
> `build/`（T02 既有配置），因此 APK/AAB 落在上述 `build/app/outputs/...` 路径
> （非 Flutter 默认 `build/app/outputs/flutter-apk`）。build 产物不入库
> （.gitignore `build/`）。

---

## 3. 侧载与签名核对步骤

### 3.1 签名核对（机器判据）

**判据**：`keytool -printcert -jarfile <AAB>` 与 `apksigner verify --print-certs <APK>`
输出的证书 SHA-256 指纹必须一致，且等于 keystore 指纹（下方命令四者同源）。

- **APK**：Flutter 默认 v2/v3 签名 → 用 `apksigner`（权威判据；`keytool -printcert
  -jarfile` 对 v2/v3 签名的 APK 报「不是已签名的 jar 文件」属预期）。
- **AAB**：走 v1 JAR 签名 → 用 `keytool -printcert -jarfile`（apksigner 只认 APK
  结构，对 AAB 报 `ApkFormatException: Missing AndroidManifest.xml` 属预期）。
- 期望指纹（M7 生成、T02 实证）：SHA-256 `7B:7C:00:A6:F9:BA:0B:34:68:A5:B2:34:
  B8:09:7E:2F:70:99:CE:F3:CC:DF:8D:AF:23:80:61:29:86:A8:69:09`
  （DN：`CN=Conver System Mobile, OU=Mobile, O=Conver System, L=Shanghai, ST=Shanghai, C=CN`；
  序列号 `aea5e9fe98b3541d`）。

```bash
# keystore 指纹
keytool -list -v -keystore ../keys/conver_system_upload.jks -storepass "$KEY_PASS"
# ① = ② = ③ = keystore 指纹即为同证书
```

### 3.2 侧载安装（release APK）

```bash
adb devices                                   # 确认 AVD/真机在线（本机 AVD：medium_phone）
adb install -r build/app/outputs/apk/release/app-release.apk
adb shell am start -n com.conversystem.conver_system_mobile/.MainActivity
```

- **Play Protect 提示属预期**：release APK 未经 Play 签名来源认证，侧载时可能弹出
  「Play Protect 未识别此应用开发者」/「非 Play 来源」提示——个人侧载验证选择
  「仍然安装」即可（或 `adb install -r -t`）。**不构成验收失败**。
- 安装后核对包版本：`adb shell dumpsys package com.conversystem.conver_system_mobile
  | grep -i version`（versionCode / versionName 应与 §3.3 一致）。
- 冒烟通过标准：launcher 显示「汇」字形自适应图标；冷启动进入主界面（五 tab 壳 +
  一屏内容渲染）；导航壳可切换。

### 3.3 对着包核对版本号与权限（上架前终检）

```bash
# 版本号（versionName / versionCode）
aapt dump badging build/app/outputs/apk/release/app-release.apk | grep -E "versionName|versionCode"

# 权限终检（零新权限纪律：集合必须 == {INTERNET} + 明文回环豁免）
aapt dump permissions build/app/outputs/apk/release/app-release.apk
# 或读 manifest 权限行集合（二选一，两者互为佐证）：
grep -o 'uses-permission[^>]\+' android/app/src/main/AndroidManifest.xml
```

> aapt 在 Android SDK build-tools（`$ANDROID_HOME/build-tools/36.0.0/aapt`）下。
> 期望：仅 `android.permission.INTERNET`；明文回环豁免见 `res/xml/network_security_config.xml`
> （base-config `cleartextTrafficPermitted="false"`，仅 `127.0.0.1`/`localhost` 放行）。

---

## 4. 产物路径与归档

| 产物 | 命令 | 路径 | 用途 |
|---|---|---|---|
| AAB | `flutter build appbundle --release` | `build/app/outputs/bundle/release/app-release.aab` | 上报 Google Play |
| APK | `flutter build apk --release` | `build/app/outputs/apk/release/app-release.apk` | 侧载分发 |

- build 产物一律不入库（.gitignore `build/`）。归档时另存一份到仓库外备份目录并
  记录 SHA-256（`sha256sum <产物>`），便于日后核对「发布时的文件 == 手上的文件」。
- 版本标号以 §1 策略为唯一准绳；每次发布的 AAB+APK 必须**同一次构建链产出、
  同证书**，禁止跨越多个 commit 的产物混发。

---

## 5. keystore 生命周期（密钥管理）

> keystore 是**仓库外单点资产**，位于 `F:\Craft\conver system\keys\conver_system_upload.jks`
> （与 mobile 仓库平级、不入 git）。口令在 gitignored 的 `android/key.properties`
> （四键：storeFile / storePassword / keyAlias / keyPassword）。**两者任一丢失即无法
> 对已发布包做升级签名**（Android 升级安装不认新证书）。

### 5.1 当前密钥事实（2026-09-09 生成，T02 实证）

- 类型：PKCS12 密钥库，1 条目，别名 `conver_system_upload`
- 密钥：RSA 2048 / SHA256withRSA；有效期 2026-09-09 → **2051-09-03**（≥25 年，端点 ≥2051）
- SHA-256 指纹、DN、序列号见 §3.1

### 5.2 备份（生成后必须立即做）

1. keystore 文件：复制到**至少两处**独立介质（如外部硬盘 + 加密云盘），文件名含
   日期（如 `conver_system_upload_20260909.jks`）。备份后校验副本 SHA-256 与原件一致。
2. 口令：**不得只存在 key.properties**。另存到与 keystore 隔离的密码管理器/纸面
   备份（关键字段：storePassword / keyPassword）。
3. key.properties 本身：gitignored、不入库；重装环境后按 §5.4 重建。

### 5.3 换发（Re-key）触发条件

- **keystore 文件丢失/损坏**，或 **口令泄露/遗忘**（换发口令亦可）；
- 任何疑似泄露迹象（文件曾暴露在外网环境 / 口令出现在非受控位置）——**立即换发**。

### 5.4 换发流程

上架（Play）路径与侧载路径处理不同：

| 场景 | 处置 |
|---|---|
| **尚未上架首发**（当前状态） | 用新 keystore 重建签名，重新产出所有产物即可；无已发布用户受影响 |
| **已上架且用户已安装** | 换证书将**无法覆盖升级**（Android 拒绝签名不一致的升级）。处置：a) 若仅口令遗忘而文件仍在 → 可从 `keytool -list -rfc` 尝试导出证书续用；b) 否则只能以「卸载重装」或「新包名」发布并接受数据迁移成本——因此 **备份是纪律，不是选项** |

换发具体步骤（新 keystore）：

```bash
# 1）生成新密钥（仓库外）
#    有效期目标 ≥25 年；受 keytool 安全上界约束（生效日 + 最长 25 年、不得越过
#    2100-01-01），用 -validity（天数）与 -startdate 组合倒推，以
#    `keytool -list -v` 输出「失效时间 ≥ 生成日 +25 年」为验收
keytool -genkeypair -v -keystore "F:/Craft/conver system/keys/conver_system_upload_v2.jks" \
    -alias conver_system_upload -keyalg RSA -keysize 2048 \
    -validity 9125 \
    -dname "CN=Conver System Mobile, OU=Mobile, O=Conver System, L=Shanghai, ST=Shanghai, C=CN"
# 2）更新 android/key.properties 四键（storeFile → 新路径，口令 → 新口令）
# 3）按 §5.2 备份新 keystore + 口令；销毁旧的（若仅换口令则保留原文件）
# 4）更新 §3.1 指纹表（换发后指纹必然变化，文档同步更新）
```

> 提示：`-validity` 受 keytool 默认安全上界约束（生效日 + 最长 25 年，不能越过
> 2100-01-01）——用 `-startdate`/`-validity` 组合倒推，以 `keytool -list -v` 输出
> 「有效期端点 ≥ 25 年」为验收。

---

## 6. 数据安全表单对照节

Android 上架需在 Play Console 填报**数据安全表单**。本应用逐项结论统一见
[docs/privacy-android.md](privacy-android.md)（三节：① 本机存储 / ② 功能必需传输 /
③ 零第三方 SDK 追踪），**本手册不复述数据流细节**，只给对照口径：

| 表单条目 | 填报值 | 依据 |
|---|---|---|
| 权限 | 仅 INTERNET（+ 明文回环豁免） | `android/app/src/main/AndroidManifest.xml`（§3.3 终检命令） |
| 数据收集 | 本机存储不出设备；功能联网仅用户主动请求 → 用户配置的 LLM 端点（HTTPS）；无自有服务器 | `docs/privacy-android.md` §①/§② |
| 第三方 SDK 追踪/统计/崩溃上报 | 0（依赖树全量审计实证，129 包 0 命中） | `docs/privacy-android.md` §③ + `python scripts/privacy_audit.py` |
| 数据安全表单「不收集」声明 | 填「不收集」项依据同上（口径：收集 = 上传至第三方服务器） | `docs/privacy-android.md` 口径界定 |

**填报前必须复跑**：

```bash
python scripts/privacy_audit.py                                        # 退出码 0 = 零第三方追踪（依赖有变动时）
python scripts/test_privacy_audit.py --cov=scripts.privacy_audit --cov-fail-under=90
```

**零新权限纪律**：发布前终检权限集合（§3.3）。权限集合不得包含 INTERNET 以外的
任何权限；明文流量仅限回环豁免（模拟器本地 HTTP 托管用）。