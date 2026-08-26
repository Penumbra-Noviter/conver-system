/**
 * Conver System — 主入口（协调层）
 *
 * 职责：
 *   1. 视图切换（侧栏导航，含 switchView 内 100ms 搜索框聚焦时序）
 *   2. 业务协调（初始化数据加载序列 / 删除/清空联动调用点 / 注入接线）
 *   3. 事件绑定（导航 / 聊天输入发送）
 *
 * 模块结构：
 *   - ./state.js — 全局状态
 *   - ./chat.js  — 聊天域渲染与交互（renderMessages / handleSend / chatDom /
 *     聊天头部深模块 renderChatHeader / startRename — F4 收口）
 *   - ./list-views.js — 角色/对话列表视图深模块（C4 下沉：渲染 + 四类按钮
 *     事件委托 + 导入 + 开始对话 + 级联删除入口 + 列表标题同步 DOM 手术；
 *     持有自身 DOM 引用，仅经 initListViews({ switchView }) 依赖本协调层）
 *   - ./format.js — 渲染/格式化纯函数（highlightText / buildMessagesHtml）
 *   - ./search-view.js — 搜索视图深模块（防抖 + 五态文案 + 渲染 + 结果跳转；
 *     ARC-9 C1 迁出，经 initSearchView 注入跳转钩子接线）
 *   - ./cascade.js — 级联关闭收口深模块（删角色/删对话/清空全部/关最后 tab
 *     四入口共用；ARC-9 C1 迁出，依赖经 setCascadeHooks 注入接线）
 *   - ./simulators.js — 模拟器列表视图深模块（manifest 解析 + 卡片网格 +
 *     类型筛选 + 四态；U7-T3，进入视图经 refreshSimulators 刷新，打开回调
 *     经 initSimulatorsView 注入）
 *   - ./simulator-view.js — 模拟器运行视图深模块（iframe 状态机 + AI 提示条
 *     + 返回；U7-T4，onOpenGame 接到 openSimulator，切走 simulators 视图时
 *     closeSimulator 销毁 iframe — Grilling 共识：状态全在游戏自身
 *     localStorage，避免后台游戏继续跑）
 *   - ./key-injector.js — 模拟器配置同步深模块（U8-T2/SIM-API-1：load 自动
 *     同步 + 「重新同步」按钮手动兜底 + 端点口径转换 + 受管模型 option；凭证
 *     获取经 initKeyInjector 钩子接线 settings.credentials()，按钮条由
 *     simulator-view.js 渲染挂接；TD-71：none 态「前往设置页配置」链接经
 *     onNavigateSettings 钩子接 switchView('settings')）
 *   - ./save-manager.js — 存档管理面板深模块（列表/导出/导入/删除；U9-T2，
 *     工具条按钮接到 openSavePanel，游戏列表经 getGames 钩子注入，
 *     切走 simulators 视图时 closeSavePanel 复位）
 *   - ./components/settings-panel.js — 设置面板（Provider 下拉、主题、侧栏、保存、清空）
 *   - ./components/ — 模态框相关组件（modal 工厂 / confirm / model-selector / export / character-form）
 */

import { models, settings } from './api.js';
import { initSettingsPanel, loadSettings, initProviderDropdown } from './components/settings-panel.js';
import { initTabBar } from './components/tab-bar.js';
import { showError, autoResizeInput } from './utils.js';
import { state } from './state.js';
import { chatDom, handleSend, refreshSendButton, setChatHooks } from './chat.js';
import { getActiveTab, abortStream, restoreFromStorage } from './tabs.js';
import { activateConversation, showEmptyState, setActivationHooks } from './conversation-activation.js';
import { initSearchView } from './search-view.js';
import { closeConversationsAndResettle, setCascadeHooks } from './cascade.js';
import { initSimulatorsView, refreshSimulators, getGames } from './simulators.js';
import { initSimulatorRun, openSimulator, closeSimulator } from './simulator-view.js';
import { initKeyInjector } from './key-injector.js';
import { initSaveManager, openSavePanel, closeSavePanel } from './save-manager.js';
import { initSimulatorImport, openImportFlow, resetSimulatorImport } from './simulator-import.js';
import { initGameGenerator, openGenerateFlow, resetGameGenerator } from './components/game-generator.js';
import { loadCharacters, loadConversations, renderConversations, syncConversationListTitle, initListViews } from './list-views.js';
import { ensureCloseActionChoice, initCloseActionSetting } from './desktop-settings.js';

// ══════════════════════════════════════════════════
// DOM 引用（协调层只保留视图与导航按钮 — 列表/角色 DOM 由 list-views.js 持有）
// ══════════════════════════════════════════════════

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

// 模块级状态（UI 实现细节，不属于全局应用状态）

const dom = {
    // 视图
    views: $$('.view'),
    navBtns: $$('.nav-btn'),
    // 移动端
    mobileNavBtns: $$('.mobile-nav-btn'),
};

// ══════════════════════════════════════════════════
// 视图切换
// ══════════════════════════════════════════════════

async function switchView(viewName) {
    // TD-53：捕获须在赋值 state.currentView 之前 — 否则 prevView 恒等于
    // viewName，运行中再点导航的 closeSimulator 永不触发
    const prevView = state.currentView;
    state.currentView = viewName;

    dom.views.forEach((v) => v.classList.remove('active'));
    dom.navBtns.forEach((b) => b.classList.remove('active'));
    dom.mobileNavBtns.forEach((b) => b.classList.remove('active'));

    const view = $(`#view-${viewName}`);
    const btn = $(`.nav-btn[data-view="${viewName}"]`);
    const mobileBtn = $(`.mobile-nav-btn[data-view="${viewName}"]`);
    if (view) view.classList.add('active');
    if (btn) btn.classList.add('active');
    if (mobileBtn) mobileBtn.classList.add('active');

    // 进入视图时刷新数据（角色/对话列表渲染与事件委托在 list-views.js — 本处只触发）
    if (viewName === 'characters') loadCharacters();
    if (viewName === 'chat') loadConversations();
    if (viewName === 'settings') {
        await loadSettings();
        initProviderDropdown();
    }
    if (viewName === 'search') {
        // 聚焦时序（ARC-9 C1）：100ms 延迟聚焦留在编排区 — 搜索视图事件绑定
        // 与防抖逻辑在 search-view.js，本处只负责视图切换后的焦点引导
        setTimeout(() => document.querySelector('#search-input')?.focus(), 100);
    }
    // 用户手册视图：初始化侧边栏滚动高亮
    if (viewName === 'guide') {
        initGuideSidebarScroll();
    }
    // 模拟器视图：进入即刷新列表（懒加载 — 未进入不发请求；fetch 在
    // simulators.js 内部走 setFetch seam，协调层只负责触发）。TD-53：运行
    // 中再点导航 = 返回列表（closeSimulator 卸载 iframe、列表面板恢复 —
    // 与「返回」同语义；idle 时 closeSimulator no-op），随后仍走既有
    // 刷新语义；非运行态重复进入保持幂等刷新不变。
    if (viewName === 'simulators') {
        if (prevView === viewName) closeSimulator();
        refreshSimulators();
    }
    // 切走模拟器视图 → 销毁运行中的 iframe + 存档面板复位 + 导入状态复位
    // （Grilling 共识：状态全在游戏自身 localStorage，无丢失风险；避免后台
    // 游戏继续跑；closeSimulator / closeSavePanel / resetSimulatorImport
    // 未打开时 no-op — 沿用运行视图销毁纪律；导入复位 = 导入中标志复位 +
    // 按钮恢复可用 + 拖拽高亮移除）
    if (viewName !== 'simulators') {
        closeSimulator();
        closeSavePanel();
        resetSimulatorImport();
        resetGameGenerator();
    }
}

dom.navBtns.forEach((btn) => {
    btn.addEventListener('click', () => switchView(btn.dataset.view));
});

// 移动端导航事件
dom.mobileNavBtns.forEach((btn) => {
    btn.addEventListener('click', () => switchView(btn.dataset.view));
});

// ══════════════════════════════════════════════════
// 会话激活流程（ARC-6 移入 conversation-activation.js 深模块 —
//   激活编排 / 草稿滚动保存恢复 / 懒加载 / F-2 守卫 / 空态 均由该模块持有，
//   app.js 经 setActivationHooks 注入 DOM 渲染回调，本文件保留事件与协调；
//   聊天域渲染/发送/头部深模块见 chat.js — 头部 F4 已收口，app.js 只留注入接线）
// ══════════════════════════════════════════════════

// ══════════════════════════════════════════════════
// 输入框事件（发送/停止逻辑见 chat.js handleSend）
// ══════════════════════════════════════════════════

chatDom.btnSend.addEventListener('click', () => {
    const tab = getActiveTab();
    if (!tab) return;
    if (tab.isStreaming) {
        // 流式生成中 → 点击为「停止生成」（停止活动 tab 的流式句柄；经 tabs.js 协议统一）
        abortStream(tab.conversationId);
    } else {
        handleSend();
    }
});

chatDom.chatInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        handleSend();
    }
});

chatDom.chatInput.addEventListener('input', () => {
    autoResizeInput(chatDom.chatInput);
});

// ══════════════════════════════════════════════════
// 模型列表
// ══════════════════════════════════════════════════

async function loadModels() {
    try {
        state.models = await models.list();
    } catch (err) {
        console.error('加载模型列表失败:', err);
    }
}

// ══════════════════════════════════════════════════
// 初始化（数据加载序列 — 角色/对话加载在 list-views.js）
// ══════════════════════════════════════════════════

async function init() {
    // 桌面壳设置：首次运行选择弹窗尽早执行（不依赖数据加载），
    // 确保 init 内任何异常都不会阻塞首次引导
    ensureCloseActionChoice();

    await loadCharacters();
    await loadConversations();
    await loadModels();
    await loadSettings();

    // T1 凭证协议检测（init 数据加载序列后）：结果缓存到 state.credentialsProtocol，
    // 供首启引导卡判定（none → 空态渲染引导卡）。检测失败 → 静默降级为 null
    // （保守不引导、不弹错、init 不中断）。
    try {
        const creds = await settings.credentials();
        state.credentialsProtocol = creds?.protocol ?? null;
    } catch (err) {
        console.error('加载凭证协议失败:', err);
        state.credentialsProtocol = null;
    }

    // P6.5-4 恢复时序契约：conversations 加载完成后才 restore；
    // isValidId 以已加载列表判定（过滤已删会话）；恢复的 tab 一律非流式，
    // 消息在激活时懒加载（走统一激活流程）
    restoreFromStorage({
        isValidId: (id) => state.conversations.some((c) => c.id === id),
    });
    const restored = getActiveTab();
    if (restored) {
        await activateConversation(restored.conversationId, { saveCurrent: false });
    } else {
        // 无记录 / 全部失效 → 现有空态（无空 tab 残留、不报错）
        showEmptyState();
    }

    // 初始化 Provider 下拉 + 模型下拉选项（含自定义模型回填）
    initProviderDropdown();

    // 初始化设置面板事件绑定（主题、侧栏、保存、清空等）
    initSettingsPanel({
        onConversationsCleared: () => {
            // 「清空所有对话」联动：统一收口（abort 全部在途流式 + closeTabs 全关 +
            // 空态 + 发送按钮）；settings-panel 已置空 state.conversations → 仅重渲染列表
            closeConversationsAndResettle({ ids: 'all', reloadList: false });
        },
    });

    // 桌面壳设置（D11）：设置页「关闭窗口」分组回填（首次引导已在 init 最前执行）
    initCloseActionSetting();
}

// ══════════════════════════════════════════════════
// 模块级注入区（G7 注入钩子模式 — 全部注入同处同相；renderConversations /
//   loadConversations / syncConversationListTitle 为 list-views.js 深模块导出，
//   showError 为 utils.js 导出 — 不再依赖本文件函数声明）
// ══════════════════════════════════════════════════

// 激活编排模块注入（ARC-6 — DOM 渲染回调 renderConversations/视图切换/错误提示；
// 头部渲染 F4 已收口 chat.js — conversation-activation 直 import，不再经 hooks）
setActivationHooks({
    renderConversations,
    switchView: (viewName) => switchView(viewName),
    showError,
});

// 聊天域注入钩子（setChatHooks — 发送/停止后刷新对话列表（refreshConversations）
// + 重命名成功后列表标题同步 DOM 手术（syncConversationListTitle）；避免反向
// import；标题同步只更新匹配会话项 .title 文本，不重渲染列表 — 与收口前行为一致）
setChatHooks({
    refreshConversations: loadConversations,
    syncConversationListTitle,
    navigateToSettings: () => switchView('settings'),
});

// 级联收口依赖注入（ARC-9 C1 — 删角色级联 / 删对话 / 清空全部 / tab-bar 关最后
// tab 四入口共用统一收口；依赖经注入而非互相 import，G7）
setCascadeHooks({
    renderConversations,
    loadConversations,
    activateConversation,
    showEmptyState,
    refreshSendButton,
});

// 列表视图深模块初始化（C4 — 角色/对话列表渲染与事件委托收口在 list-views.js；
// 唯一协调层钩子 switchView：btnNewChat 切角色视图、startChatWithCharacter
// 创建对话后切 chat 视图）
initListViews({
    switchView: (viewName) => switchView(viewName),
});

// 搜索视图初始化（ARC-9 C1 — 防抖 + 五态文案 + 渲染 + 结果跳转收口在 search-view.js；
// 跳转钩子经注入走统一激活流程；100ms 聚焦时序在 switchView 内）
initSearchView({
    navigateToConversation: (conversationId) => activateConversation(conversationId),
});

// 模拟器列表视图初始化（U7-T3 — 挂载列表 UI 到 #simulator-list-panel；
// onOpenGame 接入 openSimulator：点击卡片 → 运行视图，U7-T4；
// onOpenSaveManager 接入 openSavePanel：工具条「存档管理」按钮 → 存档面板，U9-T2；
// onImportGame 接入 openImportFlow：工具条「导入游戏」按钮 → 导入流程，工单 04；
// onGenerateGame 接入 openGenerateFlow：工具条「AI 生成」按钮 → 游戏生成器）
initSimulatorsView({
    container: $('#simulator-list-panel'),
    onOpenGame: openSimulator,
    onOpenSaveManager: openSavePanel,
    onImportGame: openImportFlow,
    onGenerateGame: openGenerateFlow,
});

// 模拟器导入初始化（工单 04 — 隐藏文件选择器 + 列表面板拖拽绑定收口在
// simulator-import.js；onImported 接入 refreshSimulators：导入成功 → 列表
// 刷新出现新卡片（带「已导入」badge）；切走 simulators 视图时 switchView
// 调用 resetSimulatorImport 复位）
initSimulatorImport({
    container: $('#simulator-list-panel'),
    onImported: () => refreshSimulators(),
});

// 模拟器运行视图初始化（U7-T4 — 绑定列表/运行两面板；iframe 状态机 +
// AI 提示条 + 返回收口在 simulator-view.js）
initSimulatorRun({
    listPanel: $('#simulator-list-panel'),
    runPanel: $('#simulator-run-panel'),
});

// 模拟器 Key 注入初始化（U8-T2 — 凭证获取经注入钩子（G7）；点击/注入/
// 反馈状态机收口在 key-injector.js，按钮条由 simulator-view.js 渲染挂接；
// 凭证请求复用 api.js setFetch seam；TD-71：none 禁用态「前往设置页配置」
// 链接点击 → 切设置视图（与侧栏导航同语义））
initKeyInjector({
    getCredentials: () => settings.credentials(),
    onNavigateSettings: () => switchView('settings'),
});

// 游戏生成器初始化（AI 生成按钮 → 模态框 → POST /api/simulators/generate；
// onGenerated 接入 refreshSimulators：生成成功 → 列表刷新出现新卡片）
initGameGenerator({
    onGenerated: () => refreshSimulators(),
});
// 存档管理面板初始化（U9-T2 — 绑定三面板 + getGames 钩子（数据源为
// simulators.js 缓存，不重复 fetch manifest）；返回按钮 → closeSavePanel；
// 切走 simulators 视图时 switchView 调用 closeSavePanel 复位）
initSaveManager({
    savePanel: $('#simulator-save-panel'),
    listPanel: $('#simulator-list-panel'),
    runPanel: $('#simulator-run-panel'),
    getGames,
});

// 注入 tab 条激活处理器（P6.5-3）：组件内关闭按钮直接 closeTab（含 abort 流式），
// 激活/联动一律经此回调走 P6.5-2 收敛的统一激活流程
initTabBar({
    container: $('#chat-tabs'),
    onActivate: async (convId, { saveCurrent = true } = {}) => {
        if (convId == null) {
            // 关闭最后一个 tab → 统一收口（tab-bar 已关 tab；settle 走空态 +
            // 发送按钮 + 列表高亮/空态重渲染）
            await closeConversationsAndResettle({ ids: [], reloadList: false });
            return;
        }
        await activateConversation(convId, { saveCurrent });
    },
});

init();

// ══════════════════════════════════════════════════
// 协议表面收口（纯编排，无导出符号）
// ══════════════════════════════════════════════════

export const __all__ = [];

// ══════════════════════════════════════════════════
// 用户手册侧边栏滚动高亮
// ══════════════════════════════════════════════════

/** 手册侧边栏中所有锚点链接 */
let guideSidebarLinks = null;
/** 手册内所有带 id 的 section 元素 */
let guideSections = null;
/** 当前高亮的链接元素 */
let guideActiveLink = null;

/**
 * 初始化手册侧边栏滚动高亮：监听 guide-container 滚动，
 * 根据当前可见区域高亮对应侧边栏条目。
 *
 * 坐标基准为「视口差值」：章节与滚动容器各自 getBoundingClientRect().top
 * 的差值随滚动自适应，无需在坐标系间换算（旧实现混用文档坐标 offsetTop
 * 与容器内部 scrollTop，两套坐标系互不随滚动换算导致高亮错位）。
 * 高亮阈值统一为容器高度的 20%；滚动到底（含 2px 容差）时强制高亮最后
 * 一章 —— 否则短小的末章节在「顶部 20%」规则下永远不可达。
 *
 * 每次切入手册视图时调用，防重复注册。
 * @returns {void}
 */
function initGuideSidebarScroll() {
    const container = document.querySelector('.guide-container');
    const sidebar = document.querySelector('.guide-sidebar');
    if (!container || !sidebar) return;

    // 首次初始化时收集引用
    if (!guideSidebarLinks) {
        guideSidebarLinks = sidebar.querySelectorAll('a[href^="#guide-"]');
    }
    if (!guideSections) {
        guideSections = container.querySelectorAll('.guide-section[id^="guide-"]');
    }

    // 移除旧 listener（防重复注册）
    const oldHandler = container._guideScrollHandler;
    if (oldHandler) {
        container.removeEventListener('scroll', oldHandler);
    }

    const handler = () => {
        // 视口差值坐标：章节顶部相对容器顶部的偏移（随滚动自动正确）
        const containerTop = container.getBoundingClientRect().top;
        const threshold = container.clientHeight * 0.2;

        let currentId = null;
        for (const section of guideSections) {
            if (section.getBoundingClientRect().top - containerTop <= threshold) {
                currentId = section.id;
            } else {
                break;
            }
        }

        // 末章可达性：滚到底（含 2px 容差）→ 强制高亮最后一章
        const lastSection = guideSections[guideSections.length - 1];
        if (lastSection &&
            container.scrollTop + container.clientHeight >= container.scrollHeight - 2) {
            currentId = lastSection.id;
        }

        if (currentId) {
            const newActive = sidebar.querySelector(`a[href="#${currentId}"]`);
            if (newActive && newActive !== guideActiveLink) {
                if (guideActiveLink) guideActiveLink.classList.remove('active');
                newActive.classList.add('active');
                guideActiveLink = newActive;
            }
        }
    };

    container._guideScrollHandler = handler;
    container.addEventListener('scroll', handler, { passive: true });
    // 初始触发一次
    setTimeout(handler, 50);
}
