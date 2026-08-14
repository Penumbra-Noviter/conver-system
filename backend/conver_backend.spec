# -*- mode: python ; coding: utf-8 -*-
"""Conver System 后端 PyInstaller onedir 打包配方（SPK-R1 spike 验证产物）。

用法（仓库根执行，Python 3.11+，依赖见 backend/requirements.txt）：
    pyinstaller backend/conver_backend.spec \
        --distpath dist --workpath build

产物：dist/conver_backend/conver_backend.exe（onedir，含 _internal/）

关键点（spk-r1 实测结论）：
  1. 入口必须是可执行脚本 → backend/run_backend.py（uvicorn.run(app) 直传对象，
     规避 frozen 下 import-string 解析差异）；backend.app.main 无 __main__ 块。
  2. pathex=[仓库根]：pytest.ini 的 pythonpath=. 同理，backend 为 PEP 420
     namespace package，必须让模块图在仓库根解析 backend.app.*。
  3. 无需手工 hiddenimports：uvicorn/pydantic/websockets/anyio/certifi/jinja2
     由 pyinstaller-hooks-contrib 覆盖，sqlalchemy 由 PyInstaller 核心 hook
     覆盖；fastapi/starlette/httpx/anthropic/openai 为纯 Python 静态导入。
  4. 前端静态目录随包分发（期末审核阻断2 修复）：main.py 的 _frontend_dir()
     在 frozen 下指向 _MEIPASS/frontend，datas 挂载 index.html/css/js
     子集后 exists() 守卫命中，StaticFiles 自动挂载 → 打包态 GET / 返回 UI。
     只打运行所需子集（见 _FRONTEND_RUNTIME），排除 node_modules(55M) 与 tests。
  5. 环境变量契约：Tauri 在 spawn 前设置 DATABASE_URL（sqlite 绝对路径），
     端口经 CLI --port 传入；.env 文件不打包（pydantic-settings 缺失时忽略）。
"""
from pathlib import Path

ROOT = Path(SPECPATH).parent  # SPECPATH = spec 所在目录（backend/），ROOT = 仓库根

# 前端运行子集：index.html + css/js + simulators（js/simulators 含子目录，PyInstaller 递归收集）。
# 目标目录均相对 _MEIPASS，与 main.py _frontend_dir() 的 /frontend 对齐。
# 禁止改为整目录打包 frontend/（node_modules 55M 会被拖入）。
# 注：frontend/assets 当前为空目录（git 不跟踪），不挂载；未来有内容时在此追加
#     (str(ROOT / "frontend" / "assets"), "frontend/assets")。
# simulators/ 随 U7 模块（2026-08-14）加入打包面：22 款游戏 HTML + manifest.json
#     （桌面版运行视图经 /simulators/… 静态加载；漏打包则应用内游戏列表为空）。
_FRONTEND_RUNTIME = (
    (str(ROOT / "frontend" / "index.html"), "frontend"),
    (str(ROOT / "frontend" / "css"), "frontend/css"),
    (str(ROOT / "frontend" / "js"), "frontend/js"),
    (str(ROOT / "frontend" / "simulators"), "frontend/simulators"),
)

a = Analysis(
    [str(ROOT / "backend" / "run_backend.py")],
    pathex=[str(ROOT)],
    binaries=[],
    datas=list(_FRONTEND_RUNTIME),
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="conver_backend",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,  # Tauri 以 CREATE_NO_WINDOW 启动可隐藏；桌面版可改 False
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="conver_backend",
)
