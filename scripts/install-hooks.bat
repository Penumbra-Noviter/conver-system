@echo off
REM F-01: install pre-commit hook to .git/hooks/pre-commit.
REM Source lives in scripts/pre-commit.sh (version-controlled). .git/hooks/ is NOT
REM committed, so re-run this script after cloning / re-initializing the repo.
REM The hook runs under Git for Windows' sh.
REM NOTE: keep this file ASCII-only so it parses correctly under any Windows codepage.

setlocal
cd /d "%~dp0\.."

if not exist .git\hooks (
    echo [F-01] ERROR: .git\hooks not found ^(not a git repo root?^)
    exit /b 1
)

copy /y scripts\pre-commit.sh .git\hooks\pre-commit >nul
if errorlevel 1 (
    echo [F-01] ERROR: failed to copy scripts\pre-commit.sh
    exit /b 1
)

echo [F-01] pre-commit hook installed: .git\hooks\pre-commit
echo         It runs "python scripts/doc_sync.py --check" on every commit and
echo         blocks the commit when CODE_WIKI markers have drifted.
echo         Uninstall: del .git\hooks\pre-commit
endlocal
