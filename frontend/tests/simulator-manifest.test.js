/**
 * 模拟器 manifest 数据完整性锁（U7-T2）。
 *
 * 直接读真实 manifest.json 与模拟器静态目录互验：
 * 顶层契约（version / 无 throwaway 字段 / 恰 22 条）、条目 schema
 * （id 唯一 kebab / file 唯一且文件真实存在 / name / description / type）、
 * 双向一一对应（目录内 *.html 全部被 manifest 引用，无孤儿文件）、
 * ai 游戏 config 三元组 {endpoint, apikey, model} 在对应 HTML 中真实存在、
 * local 游戏不带 config、saveKeyPrefix 可选字段合法性。
 *
 * 数据面覆盖口径：每条 manifest 的每个契约字段均被断言（≥90% 数据面）。
 */
import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const SIM_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'simulators');

const manifest = JSON.parse(readFileSync(path.join(SIM_DIR, 'manifest.json'), 'utf8'));

/** 条目允许出现的字段（v1 schema 锁） */
const ALLOWED_ENTRY_KEYS = ['id', 'file', 'name', 'type', 'description', 'saveKeyPrefix', 'config'];

const KEBAB_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

/** 读取某条目对应游戏 HTML 全文（config id 存在性断言用） */
function readGameHtml(entry) {
    return readFileSync(path.join(SIM_DIR, entry.file), 'utf8');
}

/** 在 HTML 中查找形如 id="xxx" 的属性出现次数 */
function countIdOccurrences(html, id) {
    const escaped = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const matches = html.match(new RegExp(`id="${escaped}"`, 'g'));
    return matches ? matches.length : 0;
}

describe('manifest 顶层契约（正式 v1）', () => {
    it('version 为 1 且无原型 throwaway 注释字段', () => {
        expect(manifest.version).toBe(1);
        expect(manifest.note).toBeUndefined();
    });

    it('恰含 22 条模拟器条目', () => {
        expect(manifest.simulators).toHaveLength(22);
    });

    it('每条目只含 v1 契约字段，无多余字段', () => {
        for (const entry of manifest.simulators) {
            expect(Object.keys(entry).sort()).toEqual([...ALLOWED_ENTRY_KEYS].sort());
        }
    });
});

describe('条目 schema', () => {
    it('id 为英文 kebab-case 且全局唯一', () => {
        const ids = manifest.simulators.map((e) => e.id);
        expect(ids.length).toBe(new Set(ids).size);
        for (const id of ids) {
            expect(id, `id 应为 kebab-case: ${id}`).toMatch(KEBAB_RE);
        }
    });

    it('file 非空且唯一', () => {
        const files = manifest.simulators.map((e) => e.file);
        expect(files.length).toBe(new Set(files).size);
        for (const file of files) {
            expect(file, `file 不能为空: ${file}`).toBeTruthy();
        }
    });

    it('type 仅取 ai | local', () => {
        for (const entry of manifest.simulators) {
            expect(['ai', 'local']).toContain(entry.type);
        }
    });

    it('name 与 description 非空', () => {
        for (const entry of manifest.simulators) {
            expect(entry.name.trim(), `name 非空: ${entry.id}`).not.toBe('');
            expect(entry.description.trim(), `description 非空: ${entry.id}`).not.toBe('');
        }
    });

    it('saveKeyPrefix 为可选字段，存在时须为非空字符串', () => {
        for (const entry of manifest.simulators) {
            if ('saveKeyPrefix' in entry) {
                expect(typeof entry.saveKeyPrefix, `saveKeyPrefix 类型: ${entry.id}`).toBe('string');
                expect(entry.saveKeyPrefix.trim(), `saveKeyPrefix 非空: ${entry.id}`).not.toBe('');
            }
        }
    });

    it('ai 游戏必带 config 三元组；local 游戏必不带 config', () => {
        for (const entry of manifest.simulators) {
            if (entry.type === 'ai') {
                expect(entry.config, `ai 游戏 config 存在: ${entry.id}`).toBeDefined();
                expect(Object.keys(entry.config).sort()).toEqual(['apikey', 'endpoint', 'model']);
                for (const value of Object.values(entry.config)) {
                    expect(value.trim(), `config 值非空: ${entry.id}`).not.toBe('');
                }
            } else {
                expect(entry.config, `local 游戏不带 config: ${entry.id}`).toBeUndefined();
            }
        }
    });
});

describe('manifest 与文件系统互验', () => {
    it('每条 file 在模拟器静态目录中真实存在', () => {
        for (const entry of manifest.simulators) {
            expect(existsSync(path.join(SIM_DIR, entry.file)), `文件存在: ${entry.file}`).toBe(true);
        }
    });

    it('目录内全部 *.html 均被 manifest 引用（无孤儿文件、无缺漏条目）', () => {
        const dirHtmlFiles = readdirSync(SIM_DIR).filter((f) => f.endsWith('.html')).sort();
        const manifestFiles = manifest.simulators.map((e) => e.file).sort();
        expect(dirHtmlFiles).toEqual(manifestFiles);
    });

    it('ai 游戏 config 三元组 id 在对应 HTML 中真实存在', () => {
        for (const entry of manifest.simulators) {
            if (entry.type !== 'ai') continue;
            const html = readGameHtml(entry);
            for (const [role, id] of Object.entries(entry.config)) {
                expect(countIdOccurrences(html, id), `${entry.id} config.${role}=${id} 在 ${entry.file} 中真实存在`).toBeGreaterThan(0);
            }
        }
    });
});
