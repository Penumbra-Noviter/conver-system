"""
Conver System — 叙事游戏种子模板

一个完整的、自包含的 HTML 叙事选择游戏模板。LLM 通过替换两个模板标记
（<!-- GEN:config --> 和 <!-- GEN:scenes -->）来填充游戏数据，生成
可运行的 HTML 模拟器游戏。

模板标记契约：
    <!-- GEN:config --> → JSON 对象：{ "title": 游戏标题, "world": 世界观简介 }
    <!-- GEN:scenes --> → JSON 数组：[ scene, ... ]
        每个 scene: { "id": 场景ID, "narrative": 叙事文本, "choices": [choice, ...] }
        每个 choice: { "text": 选项文本, "next": 目标场景ID }

    空 choices 数组 → 终局场景（显示「重新开始」按钮）。

验证闸门（game_generator.validate_generated_html）使用本模块的 MARKER_PATTERN
正则检测模板标记是否全部替换完毕。
"""

from __future__ import annotations

__all__ = [
    "MARKER_PATTERN",
    "SEED_TEMPLATE",
]

import re

#: 模板标记正则（用于校验闸门检测替换完整性）
MARKER_PATTERN = re.compile(r"<!--\s*GEN:", re.IGNORECASE)

#: 种子模板 HTML（LLM 在此填充数据；完整自包含，零外部依赖）
SEED_TEMPLATE = r"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>世界生成游戏</title>
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{--bg:#1a1a2e;--panel:#16213e;--surface:#0f3460;--accent:#e94560;--text:#eee;--text-dim:#aaa;--border:#2a2a4a;--radius:8px;--font-sans:system-ui,'Segoe UI',sans-serif;--font-mono:'Cascadia Code','Fira Code',monospace}
body{font-family:var(--font-sans);background:var(--bg);color:var(--text);min-height:100vh;display:flex;flex-direction:column;align-items:center;padding:20px;line-height:1.7}
#game-wrap{max-width:720px;width:100%;flex:1;display:flex;flex-direction:column;gap:16px}
#game-title{font-size:1.6em;font-weight:700;color:var(--accent);text-align:center;padding:12px 0 4px;border-bottom:2px solid var(--border)}
#game-world{font-size:.9em;color:var(--text-dim);text-align:center;padding:0 8px 12px;border-bottom:1px solid var(--border);line-height:1.6}
#game-narrative{background:var(--panel);border:1px solid var(--border);border-radius:var(--radius);padding:20px;font-size:1.05em;line-height:1.85;min-height:120px;white-space:pre-wrap;word-wrap:break-word}
#game-choices{display:flex;flex-direction:column;gap:8px;padding:4px 0}
.choice-btn{background:var(--surface);color:var(--text);border:1px solid var(--border);border-radius:var(--radius);padding:12px 20px;font-size:1em;cursor:pointer;text-align:left;transition:background .15s,border-color .15s}
.choice-btn:hover{background:var(--accent);border-color:var(--accent);color:#fff}
.choice-btn:disabled{opacity:.4;cursor:not-allowed}
#game-footer{display:flex;gap:8px;flex-wrap:wrap;justify-content:center;padding:12px 0;border-top:1px solid var(--border);margin-top:auto}
#game-footer button{background:transparent;color:var(--text-dim);border:1px solid var(--border);border-radius:var(--radius);padding:6px 14px;font-size:.85em;cursor:pointer;transition:color .15s,border-color .15s}
#game-footer button:hover{color:var(--accent);border-color:var(--accent)}
#game-status{text-align:center;font-size:.85em;color:var(--text-dim);padding:4px 0}
#game-error{background:#2a0a0a;color:#ff6b6b;border:1px solid #5a1a1a;border-radius:var(--radius);padding:16px;font-size:.95em;display:none}
</style>
</head>
<body>
<div id="game-wrap">
<div id="game-title"></div>
<div id="game-world"></div>
<div id="game-narrative"></div>
<div id="game-choices"></div>
<div id="game-error"></div>
<div id="game-status"></div>
<div id="game-footer">
<button id="btn-save" title="保存进度">&#128190; 保存</button>
<button id="btn-load" title="读取进度">&#128194; 读取</button>
<button id="btn-restart">&#8635; 重新开始</button>
</div>
</div>

<!-- cfg- 输入框（key-injector 探测用，运行时隐藏） -->
<input type="hidden" id="cfg-endpoint">
<input type="hidden" id="cfg-apikey">
<input type="hidden" id="cfg-model">

<script>
(function(){
'use strict';

// ═══════════════════════════════════════════════════════════
// 游戏数据 — LLM 在此填充
// ═══════════════════════════════════════════════════════════

var GAME_CONFIG = <!-- GEN:config -->;
var GAME_SCENES = <!-- GEN:scenes -->;

// ═══════════════════════════════════════════════════════════
// 游戏引擎
// ═══════════════════════════════════════════════════════════

var SAVE_KEY = 'gen_' + (GAME_CONFIG.title || 'sg').replace(/[^a-z0-9]/gi,'_').toLowerCase() + '_save';
var state = { currentScene: null, history: [] };
var transitioning = false;

function getScene(id) {
    for (var i = 0; i < GAME_SCENES.length; i++) {
        if (GAME_SCENES[i].id === id) return GAME_SCENES[i];
    }
    return null;
}

function renderScene(sceneId) {
    if (transitioning) return;
    transitioning = true;
    var scene = getScene(sceneId);
    if (!scene) {
        showError('场景 "' + sceneId + '" 不存在，请重试或重新开始。');
        transitioning = false;
        return;
    }
    state.currentScene = sceneId;
    state.history.push(sceneId);
    document.getElementById('game-narrative').textContent = scene.narrative;
    var choicesEl = document.getElementById('game-choices');
    choicesEl.innerHTML = '';
    if (scene.choices && scene.choices.length > 0) {
        for (var i = 0; i < scene.choices.length; i++) {
            (function(choice) {
                var btn = document.createElement('button');
                btn.className = 'choice-btn';
                btn.textContent = choice.text;
                btn.addEventListener('click', function() {
                    renderScene(choice.next);
                });
                choicesEl.appendChild(btn);
            })(scene.choices[i]);
        }
    } else {
        var endBtn = document.createElement('button');
        endBtn.className = 'choice-btn';
        endBtn.textContent = '\u2014 \u7ec8 \u2014';
        endBtn.disabled = true;
        choicesEl.appendChild(endBtn);
        document.getElementById('game-status').textContent = '— 终 —';
    }
    saveGame();
    transitioning = false;
}

function showError(msg) {
    var el = document.getElementById('game-error');
    el.textContent = msg;
    el.style.display = 'block';
}

function hideError() {
    document.getElementById('game-error').style.display = 'none';
}

function saveGame() {
    try {
        var data = JSON.stringify({ scene: state.currentScene, history: state.history });
        localStorage.setItem(SAVE_KEY, data);
        var statusEl = document.getElementById('game-status');
        statusEl.textContent = '已保存';
        setTimeout(function() {
            if (statusEl.textContent === '已保存') {
                var scene = getScene(state.currentScene);
                if (!scene || !scene.choices || scene.choices.length === 0) {
                    statusEl.textContent = '— 终 —';
                } else {
                    statusEl.textContent = '';
                }
            }
        }, 1500);
    } catch(e) {
        // localStorage 不可用时不阻塞游戏
    }
}

function loadGame() {
    try {
        var raw = localStorage.getItem(SAVE_KEY);
        if (!raw) return false;
        var data = JSON.parse(raw);
        if (data && data.scene) {
            state.currentScene = data.scene;
            state.history = data.history || [];
            return true;
        }
    } catch(e) {}
    return false;
}

function startGame() {
    hideError();
    state.history = [];
    // 配置校验
    document.getElementById('game-title').textContent = GAME_CONFIG.title || '未命名世界';
    document.getElementById('game-world').textContent = GAME_CONFIG.world || '';
    document.getElementById('game-status').textContent = '';
    var firstScene = GAME_SCENES.length > 0 ? GAME_SCENES[0].id : null;
    if (firstScene) {
        renderScene(firstScene);
    } else {
        showError('游戏场景数据为空，无法开始。');
    }
}

function restartGame() {
    try { localStorage.removeItem(SAVE_KEY); } catch(e) {}
    state = { currentScene: null, history: [] };
    startGame();
}

// ═══════════════════════════════════════════════════════════
// 启动
// ═══════════════════════════════════════════════════════════

document.getElementById('btn-save').addEventListener('click', saveGame);
document.getElementById('btn-load').addEventListener('click', function() {
    if (loadGame()) {
        renderScene(state.currentScene);
    } else {
        document.getElementById('game-status').textContent = '无存档记录';
        setTimeout(function() { document.getElementById('game-status').textContent = ''; }, 1500);
    }
});
document.getElementById('btn-restart').addEventListener('click', restartGame);

if (loadGame()) {
    renderScene(state.currentScene);
} else {
    startGame();
}

})();
</script>
</body>
</html>"""

# 运行时验证：确保模板标记是合法的（不会被 Python 字符串插值破坏）
assert "<!-- GEN:config -->" in SEED_TEMPLATE, "种子模板缺少 GEN:config 标记"
assert "<!-- GEN:scenes -->" in SEED_TEMPLATE, "种子模板缺少 GEN:scenes 标记"
assert MARKER_PATTERN.search(SEED_TEMPLATE), "MARKER_PATTERN 未匹配种子模板标记"