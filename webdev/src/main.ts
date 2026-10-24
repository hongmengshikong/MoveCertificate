/**
 * MoveCertificate WebUI — 应用入口（新版界面）
 *
 * 页面结构：顶部栏 + Hero + 分组卡片 + 底部导航 + 底部弹层
 * 数据来源：kernelsu 的 exec() 读取模块文件 / 运行只读状态脚本
 */

import { fullScreen, toast as ksuToast } from 'kernelsu';
import { t, getLang, setLang, clearLang, isAutoLang, LANG_LABELS, supportedLangs } from './i18n.js';
import type { LangCode } from './i18n.js';
import {
    getVersionInfo,
    getLoggerInfo,
    getInstallCertResults,
    deleteCert,
    getCurrentMode,
    setMode,
    getStatus,
} from './cert-service.js';
import {
    renderChips,
    renderStatusCard,
    renderCertList,
    renderModeSection,
    renderLog,
    renderLangSheet,
    setLangLabel,
    showSkeleton,
    hideSkeleton,
} from './ui-renderer.js';
import type { LangOption } from './ui-renderer.js';
import { icon, setIcon } from './icons.js';
import { initTheme, bindThemeSeg } from './theme.js';
import type { RunMode, ModuleStatus, CertEntry } from './constants.js';

// ==================== 状态 ====================

type TabName = 'certs' | 'mode' | 'log' | 'settings';

const state: {
    tab: TabName;
    mode: RunMode;
    version: string;
    name: string;
    status: ModuleStatus | null;
    certs: CertEntry[];
    logLines: string[];
    certsLoaded: boolean;
    modeLoaded: boolean;
    logLoaded: boolean;
} = {
    tab: 'certs',
    mode: 'compatible',
    version: '',
    name: '',
    status: null,
    certs: [],
    logLines: [],
    certsLoaded: false,
    modeLoaded: false,
    logLoaded: false,
};

const TAB_TITLES: Record<TabName, () => string> = {
    certs: () => t('certsTab'),
    mode: () => t('modeTab'),
    log: () => t('logTab'),
    settings: () => t('setTab'),
};

/** 语言选项（flags 用 emoji，避免额外资源） */
const LANGS: LangOption[] = [
    { code: 'auto', name: '', native: '', flag: '🌐' },
    { code: 'zh-CN', name: '中文', native: 'zh-CN', flag: '🇨🇳' },
    { code: 'en', name: 'English', native: 'en', flag: '🇬🇧' },
    { code: 'tr', name: 'Türkçe', native: 'tr', flag: '🇹🇷' },
];

// ==================== 小工具 ====================

function $(id: string): HTMLElement | null {
    return document.getElementById(id);
}

function setText(id: string, text: string): void {
    const el = $(id);
    if (el) el.textContent = text;
}

let toastTimer = 0;
function showToast(msg: string): void {
    const el = $('toast');
    if (!el) {
        ksuToast(msg);
        return;
    }
    el.textContent = msg;
    el.classList.add('show');
    window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(() => el.classList.remove('show'), 1900);
}

/** 把 data-i18n 的静态文字替换成当前语言 */
function applyI18n(): void {
    document.querySelectorAll<HTMLElement>('[data-i18n]').forEach((el) => {
        const key = el.getAttribute('data-i18n');
        if (key) el.textContent = t(key);
    });
}

// ==================== 确认弹窗 ====================

interface ConfirmOptions {
    title: string;
    message: string;
    iconName?: string;
    info?: boolean;
    danger?: boolean;
    okText?: string;
    onOk: () => void | Promise<void>;
}

let closeConfirm: (() => void) | null = null;

function openConfirm(opts: ConfirmOptions): void {
    const modal = $('confirmModal');
    const ico = $('confirmIcon');
    const title = $('confirmTitle');
    const msg = $('confirmMessage');
    const ok = $('confirmOk') as HTMLButtonElement | null;
    const cancel = $('confirmCancel') as HTMLButtonElement | null;
    if (!modal || !ok || !cancel) return;

    if (ico) {
        ico.className = 'modal-ico' + (opts.info ? ' info' : '');
        ico.innerHTML = icon(opts.iconName || (opts.info ? 'layers' : 'trash'), 26);
    }
    if (title) title.textContent = opts.title;
    if (msg) msg.textContent = opts.message;

    ok.textContent = opts.okText || t('confirm');
    ok.className = 'btn' + (opts.danger ? ' danger' : '');

    const close = (): void => {
        modal.classList.remove('open');
        ok.onclick = null;
    };
    closeConfirm = close;

    ok.onclick = async (): Promise<void> => {
        close();
        try {
            await opts.onOk();
        } catch (e) {
            console.error(e);
        }
    };
    cancel.onclick = close;
    modal.onclick = (e: MouseEvent): void => {
        if (e.target === modal) close();
    };

    modal.classList.add('open');
}

// ==================== 数据加载 ====================

async function loadVersion(): Promise<void> {
    try {
        const lines = await getVersionInfo();
        for (const line of lines) {
            const i = line.indexOf('=');
            if (i < 0) continue;
            const key = line.slice(0, i).trim();
            const val = line.slice(i + 1).trim();
            if (key === 'version') state.version = val;
            if (key === 'name') state.name = val;
        }
        setText('versionValue', state.version || '—');
    } catch (e) {
        console.error('读取版本信息失败:', e);
        setText('versionValue', t('getVersionInfoFailed'));
    }
}

function renderHero(): void {
    const st = state.status;
    const modeLabel = state.mode === 'compatible' ? t('compatibleMode') : t('builtinMode');
    const chips = [{ text: modeLabel, cls: 'accent', icon: 'layers' }];

    if (st && st.ok) {
        chips.push({ text: t('chipCerts', String(st.store)), cls: 'good', icon: 'shield' });
        const ok = st.probeSystem || st.probeApex;
        chips.push({ text: ok ? t('certActive') : t('certInactive'), cls: ok ? 'good' : 'warn', icon: ok ? 'check' : 'info' });
    }
    renderChips('heroChips', chips);
}

async function loadCerts(force = false): Promise<void> {
    if (!force && state.certsLoaded) return;

    showSkeleton('statusCard', 6);
    showSkeleton('certificateList', 3);

    let status: ModuleStatus | null = null;
    let certs: CertEntry[] = [];
    let mode: RunMode = state.mode;

    try {
        [status, certs] = await Promise.all([
            getStatus(),
            getInstallCertResults().catch(() => [] as CertEntry[]),
        ]);
        mode = await getCurrentMode().catch(() => state.mode);
    } catch (e) {
        console.error('加载证书页失败:', e);
        showToast(t('getCertListFailed'));
    }

    state.status = status;
    state.certs = certs;
    state.mode = mode;
    state.certsLoaded = true;

    if (!state.version) await loadVersion();

    hideSkeleton('statusCard');
    hideSkeleton('certificateList');

    renderStatusCard('statusCard', {
        status,
        mode,
        version: state.version,
        certCount: certs.length,
    });
    renderCertList('certificateList', certs, onDelete);
    renderHero();
    setText('certCount', certs.length ? String(certs.length) : '');
}

async function loadMode(force = false): Promise<void> {
    if (!force && state.modeLoaded) return;
    try {
        state.mode = await getCurrentMode();
    } catch (e) {
        console.error('读取模式失败:', e);
    }
    state.modeLoaded = true;
    renderModeSection('modeConfig', state.mode, onModePick);
}

async function loadLog(force = false): Promise<void> {
    if (!force && state.logLoaded) return;
    showSkeleton('logContent', 5);
    try {
        const lines = await getLoggerInfo();
        state.logLines = lines;
        state.logLoaded = true;
        renderLog('logContent', lines, 'logCount');
    } catch (e) {
        console.error('读取日志失败:', e);
        hideSkeleton('logContent');
        renderLog('logContent', [t('getLogFailed')]);
        showToast(t('getLogFailed'));
    }
}

function refreshCurrentTab(): void {
    switch (state.tab) {
        case 'certs':
            state.certsLoaded = false;
            loadCerts(true);
            break;
        case 'mode':
            loadMode(true);
            break;
        case 'log':
            loadLog(true);
            break;
        default:
            loadVersion();
            break;
    }
}

// ==================== 交互回调 ====================

function onDelete(fileName: string): void {
    openConfirm({
        title: t('modalTitle'),
        message: t('confirmDeleteCert', fileName),
        iconName: 'trash',
        danger: true,
        onOk: async (): Promise<void> => {
            try {
                await deleteCert(fileName);
                showToast(t('deletedReboot', fileName));
                await loadCerts(true);
            } catch (e) {
                console.error('删除失败:', e);
                showToast(t('deleteFailed'));
            }
        },
    });
}

function onModePick(next: RunMode): void {
    const label = next === 'compatible' ? t('compatibleMode') : t('builtinMode');
    openConfirm({
        title: t('modeCurrentTitle'),
        message: t('confirmSwitchModeMsg', label),
        iconName: 'layers',
        info: true,
        danger: false,
        onOk: async (): Promise<void> => {
            try {
                await setMode(next);
                state.mode = next;
                state.modeLoaded = true;
                renderModeSection('modeConfig', state.mode, onModePick);
                showToast(t('modeSwitched', label));
            } catch (e) {
                console.error('切换模式失败:', e);
                showToast(t('modeSwitchFailed'));
            }
        },
    });
}

// ==================== 语言弹层 ====================

function langOptions(): LangOption[] {
    return LANGS.map((l) => {
        if (l.code === 'auto') {
            return { code: 'auto', name: t('langAuto'), native: t('langAutoSub'), flag: l.flag };
        }
        return l;
    });
}

function openLangSheet(): void {
    const sheet = $('langSheet');
    if (!sheet) return;
    const current = isAutoLang() ? 'auto' : getLang();
    renderLangSheet('langSheetList', langOptions(), current, (code) => {
        pickLang(code);
    });
    sheet.classList.add('open');
}

function closeLangSheet(): void {
    const sheet = $('langSheet');
    if (sheet) sheet.classList.remove('open');
}

function pickLang(code: string): void {
    if (code === 'auto') {
        clearLang();
    } else {
        setLang(code as LangCode);
    }
    closeLangSheet();
    applyI18n();
    setLangLabel('langValue', isAutoLang() ? t('langAuto') : LANG_LABELS[getLang()]);
    setText('topTitle', TAB_TITLES[state.tab]());

    // 重新渲染动态内容（状态/模式/日志都是运行时生成的文字）
    renderModeSection('modeConfig', state.mode, onModePick);
    renderLog('logContent', state.logLines, 'logCount');
    state.certsLoaded = false;
    loadCerts(true);
}

// ==================== 标签页 ====================

function switchTab(name: TabName): void {
    state.tab = name;

    document.querySelectorAll<HTMLElement>('.tab-page').forEach((p) => p.classList.remove('active'));
    const page = $('tab-' + name);
    if (page) page.classList.add('active');

    document.querySelectorAll<HTMLElement>('#nav .nav-item').forEach((b) => {
        b.classList.toggle('active', b.getAttribute('data-tab') === name);
    });

    setText('topTitle', TAB_TITLES[name]());
    window.scrollTo({ top: 0 });

    if (name === 'certs') loadCerts();
    else if (name === 'mode') loadMode();
    else if (name === 'log') loadLog();
}

// ==================== 初始化 ====================

function setupIcons(): void {
    setIcon($('refreshTopBtn'), 'refresh', 21);
    setIcon($('navIcoCerts'), 'shield', 22);
    setIcon($('navIcoMode'), 'sliders', 22);
    setIcon($('navIcoLog'), 'terminal', 22);
    setIcon($('navIcoSet'), 'gear', 22);
    setIcon($('refreshCertsIco'), 'refresh', 18);
    setIcon($('refreshLogIco'), 'refresh', 18);
    setIcon($('langTile'), 'globe', 21);
    setIcon($('themeTile'), 'moon', 21);
    setIcon($('versionTile'), 'info', 21);
    setIcon($('repoTile'), 'link', 21);
    setIcon($('upstreamTile'), 'layers', 21);

    document.querySelectorAll<HTMLElement>('.chev').forEach((el) => setIcon(el, 'chevron', 18));

    // 贡献者
    const contrib = $('contributors');
    if (contrib) {
        const names = ['ys1231', 'SafaSafari', 'fr0stb1rd', 'RevealedSoulEven', 'shikong'];
        contrib.innerHTML = names
            .map((n) => `<span class="contrib"><span class="dot"></span>${n}</span>`)
            .join('');
    }
}

function bindEvents(): void {
    document.querySelectorAll<HTMLElement>('#nav .nav-item').forEach((btn) => {
        btn.addEventListener('click', () => {
            const tab = btn.getAttribute('data-tab') as TabName;
            if (tab) switchTab(tab);
        });
    });

    $('refreshTopBtn')?.addEventListener('click', refreshCurrentTab);
    $('refreshCertsBtn')?.addEventListener('click', () => {
        state.certsLoaded = false;
        loadCerts(true);
    });
    $('refreshLogBtn')?.addEventListener('click', () => loadLog(true));
    $('langRow')?.addEventListener('click', openLangSheet);
    $('langSheetClose')?.addEventListener('click', closeLangSheet);

    $('langSheet')?.addEventListener('click', (e: MouseEvent) => {
        if (e.target === $('langSheet')) closeLangSheet();
    });

    window.addEventListener('scroll', () => {
        const bar = $('topbar');
        if (bar) bar.classList.toggle('stuck', window.scrollY > 6);
    }, { passive: true });
}

window.onload = async (): Promise<void> => {
    fullScreen(false);
    initTheme();
    bindThemeSeg();
    applyI18n();
    setupIcons();
    bindEvents();

    setLangLabel('langValue', isAutoLang() ? t('langAuto') : LANG_LABELS[getLang()]);
    setText('topTitle', TAB_TITLES[state.tab]());

    await loadVersion();
    await loadCerts();
};
