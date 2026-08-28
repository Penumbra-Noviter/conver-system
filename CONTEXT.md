# 移动端领域词汇表 (CONTEXT)

> 领域术语登记，供新入参与者与架构评审对齐概念。术语即事实：修改命名 / 职责前先更新本表。
> 仅收录 load-bearing 术语（协议/契约级，不自嗨）；来源：设计文档 [docs/mobile-design.md](docs/mobile-design.md)（标 § 出处）与桌面库 CONSENSUS。

| 术语 | 定义 | 归属（模块 / 接口） |
|------|------|---------------------|
| **独立运行 (standalone)** | 移动端不依赖桌面 FastAPI 后端，App 内直连公网 LLM API；桌面中间层（为 Python SDK 导入而生）整体省略 | 架构决策（mobile-design §0） |
| **完整桥接（不阉割）** | 模拟器 MVP 全量做：本地托管 + Key 自动注入 + 存档管理 + AI 驱动游戏全通，不分期 | 里程碑承诺（§4.5） |
| **本地 HTTP 服务器托管** | `dart:io` HttpServer 监听 `127.0.0.1:<固定端口>` serve 文档目录；游戏走正常 http origin → localStorage 语义与桌面一致（另：明文流量限定回环） | `services/simulator_bridge.dart`（§4.5 Q1） |
| **Key 注入契约** | 保留桌面注入全部语义（游戏零改动）：endpoint/model 由主应用注入；Key 仅存 SecureStorage、白名单三元组注入，`claude key 恒不进游戏` | `simulator_bridge.dart`（§4.5 Q2/Q5） |
| **注入幂等守卫** | 桌面熔断机制简化为注入期的幂等守卫（注入单向 Dart→JS），守注入不重复、不越界 | §4.5 Q2 |
| **单 origin + 前缀隔离** | 存档 localStorage 键带统一前缀白名单（复用桌面 saveKeys 语义），同一 origin 下游戏互不越权 | 存档桥（§4.5 Q3） |
| **恶意导入策略** | 命中恶意模式 → 拒绝 + 显示命中关键词清单 + 强制二次确认（知情才放行；化解文档类 HTML 关键词误杀） | 导入链（§4.5 Q14） |
| **CORS 直连（方案③）** | 游戏 WebView 内浏览器 fetch 直连第三方 OpenAI 兼容 API（国产厂商实测放行）为默认路径；无 `/proxy` 反代 | §4.4 |
| **fetch 垫片（方案①）** | JS fetch 拦截垫片，仅为 Claude/OpenAI 官方端点保留兜底位（未启用，视反馈） | §4.5 |
| **验证分层** | 业务逻辑/widget 用 `flutter test`（宿主无头，无需模拟器）兜底；平台薄层（WebView 桥/SecureStorage/端口绑定）上真机/模拟器验证；iOS 需 macOS+CI | §7.1 |
| **伴生同步（后期可选）** | Tailscale/导出导入实现"连桌面同步数据"的后期可选功能，非 MVP 所需 | §0 / §8 |

> 注：与桌面库共享的领域概念（角色卡 V2、SSE 流式、存档互迁格式等）权威定义在桌面库 `desktop/CONTEXT.md`，本表只登记移动端特有/新增的 load-bearing 术语。