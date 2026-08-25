from __future__ import annotations

# 纯聚合入口：API 包不导出符号，路由器在各路由模块内定义后由应用入口 main.py 显式 include
__all__: list[str] = []
