import { defineConfig } from 'vitest/config';

export default defineConfig({
    test: {
        environment: 'jsdom',
        include: ['tests/**/*.test.js'],
        // ARC-9 C5 覆盖率接线（G2 口径：按本批涉改文件范围计，行覆盖 ≥90%；
        // coverage.include 限定清单，阈值按文件粒度断言 — 涉改存量文件低于 90%
        // 必须显式记录原因 + 行号清单，不可静默放宽）
        coverage: {
            provider: 'v8',
            include: [
                'js/app.js',
                'js/chat.js',
                'js/markdown.js',
                'js/stream-session.js',
                'js/search-view.js',
                'js/cascade.js',
                'js/components/settings-panel.js',
                'js/components/model-selector.js',
                'js/components/character-submit.js',
                'js/simulators.js',
                'js/simulator-view.js',
                'js/key-injector.js',
                'js/save-manager.js',
                'js/save-key-meta.js', // TD-67/68 存档键契约单一来源（契约之家，per-file ≥90% 口径）
                'js/fetch-seam.js', // TD-51/55/60 fetch 注入点单一来源（per-file ≥90% 口径）
                'js/simulator-contracts.js', // C8 模拟器域契约单一来源（契约深模块，per-file ≥90% 口径）
                'js/simulator-adapt.js', // T-01 适配分析共享模块（映射记录解析/三面提取/覆盖比对，per-file ≥90% 口径）
                // scripts/check-simulator-css.mjs 不在此列：v8 provider 无法
                // 采集项目根外文件（实测空报告）——其全部代码行由
                // simulator-adapt.test.js 直调（runCheck/main/renderItem）+ 
                // spawn 集成测试执行覆盖（T-01 汇报口径）
                'js/list-views.js', // C4 角色/对话列表视图深模块（自 app.js 下沉，per-file ≥90% 口径）
                'js/utils.js', // C4 共享工具域（showError/showSuccess 薄封装归位，per-file ≥90% 口径）
            ],
            reporter: ['text', 'html'],
            thresholds: {
                lines: 90,
                perFile: true,
            },
        },
    },
});
