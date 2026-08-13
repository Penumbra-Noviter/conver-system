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
            ],
            reporter: ['text', 'html'],
            thresholds: {
                lines: 90,
                perFile: true,
            },
        },
    },
});
