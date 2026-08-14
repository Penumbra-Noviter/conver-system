/**
 * 模拟器 manifest 数据完整性锁（U7-T2 + U9-T1 扩展）。
 *
 * 直接读真实 manifest.json 与模拟器静态目录互验：
 * 顶层契约（version=2 / 无 throwaway 字段 / 恰 22 条）、条目 schema
 * （id 唯一 kebab / file 唯一且文件真实存在 / name / description / type）、
 * 双向一一对应（目录内 *.html 全部被 manifest 引用，无孤儿文件）、
 * ai 游戏 config 三元组 {endpoint, apikey, model} 在对应 HTML 中真实存在、
 * local 游戏不带 config、v2 条目必带 saveKeys 且键可溯源至 HTML 源码、
 * cfg 键（含 API Key）不收录进任何 saveKeys。
 *
 * saveKeys 契约（U9-T1，与 U9-T2 共享）：
 *   - 元素为字符串；不含正则元字符的字符串 = 精确键名；含正则元字符的
 *     字符串 = 正则模式（匹配时锚定完整键名 ^…$）。
 *   - 数据不变量：模式字符串不得自含 ^ / $（锚定由匹配方统一加）；
 *     任何元素不得命中已知 cfg 键。
 *   - 溯源断言：元素整体字面须在对应 HTML 源码中出现；常量拼接键
 *     （如 'wg_' + CFG.id + '_save' / NS+'_slot_'+i，字面无完整键名）
 *     按 '_' 拆段逐段溯源（U9-T1 键提取方法学：常量拼接解析）。
 *
 * 数据面覆盖口径：每条 manifest 的每个契约字段均被断言（≥90% 数据面）。
 */
import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { parseManifest } from '../js/simulators.js';

const SIM_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'simulators');

const manifest = JSON.parse(readFileSync(path.join(SIM_DIR, 'manifest.json'), 'utf8'));

/** 条目允许出现的字段（v2 schema 锁；saveKeyPrefix 已退役 — TD-48） */
const ALLOWED_ENTRY_KEYS = ['id', 'file', 'name', 'type', 'description', 'saveKeys', 'config'];

/** 正则元字符集：saveKeys 元素含任一字符即按正则模式处理（与实现共享的数据契约） */
const SAVE_KEY_META_RE = /[.*+?^${}()|[\]\\]/;

const KEBAB_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

/** 读取某条目对应游戏 HTML 全文（config id / saveKeys 溯源断言用） */
function readGameHtml(entry) {
    return readFileSync(path.join(SIM_DIR, entry.file), 'utf8');
}

/** 在 HTML 中查找形如 id="xxx" 的属性出现次数 */
function countIdOccurrences(html, id) {
    const escaped = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const matches = html.match(new RegExp(`id="${escaped}"`, 'g'));
    return matches ? matches.length : 0;
}

/** saveKeys 元素是否为正则模式（含正则元字符） */
function isPattern(element) {
    return SAVE_KEY_META_RE.test(element);
}

/** saveKeys 元素（精确键或锚定模式）是否命中给定键名（导入白名单判定语义 — 与 U9-T2 同构） */
function saveKeyHits(element, key) {
    if (!isPattern(element)) return element === key;
    return new RegExp(`^${element}$`).test(key);
}

/**
 * 溯源断言：元素整体字面（模式元素取其字面前缀 — 首个正则元字符之前的部分）
 * 须在 HTML 中出现；常量拼接键（字面无完整键名）按 '_' 拆段，各段须均在
 * HTML 中出现（U9-T1 提取方法学）。
 */
function assertKeyTraceable(html, entry, key) {
    const probe = isPattern(key) ? key.slice(0, key.search(SAVE_KEY_META_RE)) : key;
    expect(probe.length, `${entry.id} ${key} 溯源探针非空`).toBeGreaterThan(0);
    if (html.includes(probe)) return;
    const segments = probe.split('_').filter(Boolean);
    expect(segments.length, `${entry.id} ${key} 拆段可溯源（段数 >1）`).toBeGreaterThan(1);
    for (const seg of segments) {
        expect(html.includes(seg), `${entry.id} ${key} 段 ${seg} 在 ${entry.file} 中可溯源`).toBe(true);
    }
}

/** 已知 cfg 键全集（含 API Key 的配置键 — 从 22 游戏源码提取，存档管理不得收录） */
const CFG_KEYS = [
    'ls_cfg', 'xiantu_config', 'coc_config', 'il_cfg', 'god_config',
    'urban_awakening_config', 'spiderweb_cfg', 'xingtu_cfg', 'hpbook_cfg',
    'sakura_cfg', 'endless_sea_cfg', 'twilight_config', 'emperor_cfg',
    'lwfs_cfg_v1', 'hsh_cfg_v1', 'wg_xiaomabaoli_cfg', 'wg_gaozhongsheng_cfg',
    'madoka_cfg_v1',
];

describe('manifest 顶层契约（正式 v2）', () => {
    it('version 为 2 且无原型 throwaway 注释字段', () => {
        expect(manifest.version).toBe(2);
        expect(manifest.note).toBeUndefined();
    });

    it('恰含 22 条模拟器条目', () => {
        expect(manifest.simulators).toHaveLength(22);
    });

    it('每条目只含 v2 契约字段，无多余字段', () => {
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

    it('saveKeyPrefix 已退役：v2 条目不得出现该字段（v1 数据兼容解析仅存于代码）', () => {
        for (const entry of manifest.simulators) {
            expect('saveKeyPrefix' in entry, `saveKeyPrefix 退役: ${entry.id}`).toBe(false);
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

describe('saveKeys 数据完整性（U9-T1）', () => {
    it('22 条全部含 saveKeys，且为不含空串元素的字符串数组', () => {
        for (const entry of manifest.simulators) {
            expect(Array.isArray(entry.saveKeys), `saveKeys 数组: ${entry.id}`).toBe(true);
            expect(entry.saveKeys.length, `saveKeys 非空: ${entry.id}`).toBeGreaterThan(0);
            for (const key of entry.saveKeys) {
                expect(typeof key, `saveKeys 元素类型: ${entry.id}`).toBe('string');
                expect(key.trim(), `saveKeys 元素非空: ${entry.id}`).not.toBe('');
            }
        }
    });

    it('模式元素（含正则元字符）锚定完整键名编译合法，且不自含 ^ $ 锚点', () => {
        for (const entry of manifest.simulators) {
            for (const key of entry.saveKeys) {
                if (!isPattern(key)) continue;
                expect(key, `模式不得自含 ^: ${entry.id}`).not.toContain('^');
                expect(key, `模式不得自含 $: ${entry.id}`).not.toContain('$');
                expect(() => new RegExp(`^${key}$`), `模式可编译: ${entry.id} ${key}`).not.toThrow();
            }
        }
    });

    it('精确键与模式元素均在对应 HTML 源码中可溯源（字面包含，常量拼接按 _ 拆段兜底）', () => {
        for (const entry of manifest.simulators) {
            const html = readGameHtml(entry);
            for (const key of entry.saveKeys) {
                assertKeyTraceable(html, entry, key);
            }
        }
    });

    it('cfg 键（含 API Key 的配置键）不收录：无精确键或模式命中任一已知 cfg 键', () => {
        for (const entry of manifest.simulators) {
            for (const key of entry.saveKeys) {
                for (const cfgKey of CFG_KEYS) {
                    expect(saveKeyHits(key, cfgKey), `${entry.id} saveKeys ${key} 不得命中 cfg 键 ${cfgKey}`).toBe(false);
                }
            }
        }
    });

    it('真实 manifest.json 经 parseManifest 解析：ok:true 且 22 条全部带非空 saveKeys 数组（数据面与解析面一致）', () => {
        const raw = readFileSync(path.join(SIM_DIR, 'manifest.json'), 'utf8');
        const result = parseManifest(raw);
        expect(result.ok).toBe(true);
        expect(result.games).toHaveLength(22);
        for (const game of result.games) {
            expect(Array.isArray(game.saveKeys), `${game.id} 归一化后 saveKeys 数组`).toBe(true);
            expect(game.saveKeys.length, `${game.id} 归一化后 saveKeys 非空`).toBeGreaterThan(0);
            expect('saveKeyPrefix' in game, `${game.id} 归一化无退役字段`).toBe(false);
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
