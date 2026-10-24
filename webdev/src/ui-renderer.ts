/**
 * MoveCertificate — 页面渲染层（新版设计）
 *
 * 只负责把数据画成 DOM，不执行任何 shell 命令。
 * 视觉语言：彩色图标块 + 分组卡片 + 胶囊状态 + 底部导航。
 */

import { t } from './i18n.js';
import { icon } from './icons.js';
import type { RunMode, CertEntry, ModuleStatus } from './constants.js';

// ==================== 工具 ====================

/** HTML 转义，防止证书名里的特殊字符破坏结构 */
export function esc(s: string): string {
    return String(s).replace(/[&<>"']/g, (c) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c] as string));
}

/** 版本号统一显示成 v1.7.0（module.prop 里可能已经带 v） */
export function formatVersion(v: string): string {
    const s = String(v || '').trim();
    if (!s) return '—';
    return s.startsWith('v') ? s : `v${s}`;
}

/** 图标块 */
function tile(iconName: string, cls: string): string {
    return `<div class="tile ${cls}">${icon(iconName, 21)}</div>`;
}

/** 一行：图标块 + 标题/副标题 + 右侧内容 */
function row(opts: {
    icon: string;
    tileCls: string;
    title: string;
    sub?: string;
    value?: string;
    pill?: { text: string; cls: string };
    chev?: boolean;
}): string {
    const right = [
        opts.pill ? `<span class="pill ${opts.pill.cls}">${esc(opts.pill.text)}</span>` : '',
        opts.value ? `<span class="value">${esc(opts.value)}</span>` : '',
        opts.chev ? `<div class="chev">${icon('chevron', 18)}</div>` : '',
    ].join('');
    return `<div class="row">${tile(opts.icon, opts.tileCls)}
        <div class="txt"><div class="t">${esc(opts.title)}</div>${opts.sub ? `<div class="s">${esc(opts.sub)}</div>` : ''}</div>
        ${right}</div>`;
}

/** 骨架屏 */
export function showSkeleton(elId: string, count = 4): void {
    const el = document.getElementById(elId);
    if (!el) return;
    el.innerHTML = Array.from({ length: count }, () => '<div class="skeleton"></div>').join('');
}

export function hideSkeleton(elId: string): void {
    const el = document.getElementById(elId);
    if (el) el.innerHTML = '';
}

// ==================== Hero 状态胶囊 ====================

export interface ChipItem { text: string; cls?: string; icon?: string; }

export function renderChips(elId: string, items: ChipItem[]): void {
    const el = document.getElementById(elId);
    if (!el) return;
    el.innerHTML = items.map((c) =>
        `<span class="chip ${c.cls || ''}">${c.icon ? icon(c.icon, 14) : ''}${esc(c.text)}</span>`
    ).join('');
}

// ==================== 状态卡片 ====================

export interface StatusView {
    status: ModuleStatus | null;
    mode: RunMode;
    version: string;
    certCount: number;
}

export function renderStatusCard(elId: string, view: StatusView): void {
    const el = document.getElementById(elId);
    if (!el) return;

    const st = view.status;
    const modeLabel = view.mode === 'compatible' ? t('compatibleMode') : t('builtinMode');

    if (!st || !st.ok) {
        el.innerHTML = row({
            icon: 'info',
            tileCls: 't-orange',
            title: t('statusUnavailable'),
            sub: '/data/adb/modules/MoveCertificate/sh/status.sh',
        });
        return;
    }

    const systemOk = st.probeSystem;
    const apexOk = st.probeApex;

    el.innerHTML = [
        row({
            icon: 'layers',
            tileCls: 't-blue',
            title: t('statusMode'),
            sub: st.mode === 'compatible' ? t('statusModeSubCompatible') : t('statusModeSubBuiltin'),
            pill: { text: modeLabel, cls: 'good' },
        }),
        row({
            icon: 'shield',
            tileCls: 't-green',
            title: t('statusStore'),
            sub: t('statusStoreSub'),
            value: `${st.store}`,
        }),
        row({
            icon: 'folder',
            tileCls: 't-slate',
            title: t('statusSystem'),
            sub: '/system/etc/security/cacerts',
            pill: { text: systemOk ? t('certActive') : t('certInactive'), cls: systemOk ? 'good' : 'warn' },
        }),
        row({
            icon: 'lock',
            tileCls: 't-violet',
            title: t('statusApex'),
            sub: '/apex/com.android.conscrypt/cacerts',
            pill: { text: apexOk ? t('certActive') : t('certInactive'), cls: apexOk ? 'good' : 'warn' },
        }),
        row({
            icon: 'bolt',
            tileCls: 't-orange',
            title: t('statusInject'),
            sub: t('statusInjectSub'),
            value: `${st.injected}/${st.zygotes}`,
        }),
        row({
            icon: 'cert',
            tileCls: 't-teal',
            title: t('statusProbe'),
            sub: st.probe || t('statusProbeEmpty'),
            value: formatVersion(st.version || view.version),
        }),
    ].join('');
}

// ==================== 证书列表 ====================

export type DeleteHandler = (fileName: string) => void;

export function renderCertList(elId: string, certs: CertEntry[], onDelete: DeleteHandler): void {
    const list = document.getElementById(elId);
    if (!list) return;
    list.innerHTML = '';

    if (!certs || certs.length === 0) {
        const li = document.createElement('li');
        li.className = 'list-empty';
        li.innerHTML = `${tile('cert', 't-slate')}<div>${esc(t('certEmpty'))}</div>`;
        list.appendChild(li);
        return;
    }

    for (const cert of certs) {
        const [hash, ...rest] = String(cert.name).split(':');
        const fileName = (hash || '').trim();
        const rawName = rest.join(':').trim();
        const certName = !rawName || rawName === 'Unknown' ? t('unknownCert') : rawName;
        const ok = cert.status === 'success';

        const li = document.createElement('li');
        li.className = 'cert-row';

        const iconBox = document.createElement('div');
        iconBox.className = 'tile ' + (ok ? 't-green' : 't-slate');
        iconBox.innerHTML = icon('shield', 20);
        li.appendChild(iconBox);

        const txt = document.createElement('div');
        txt.className = 'txt';
        const tt = document.createElement('div');
        tt.className = 't';
        tt.textContent = fileName;
        const ss = document.createElement('div');
        ss.className = 's';
        ss.textContent = certName;
        txt.appendChild(tt);
        txt.appendChild(ss);
        li.appendChild(txt);

        const pill = document.createElement('span');
        pill.className = 'pill ' + (ok ? 'good' : 'warn');
        pill.textContent = ok ? t('certActive') : t('certInactive');
        li.appendChild(pill);

        const del = document.createElement('button');
        del.type = 'button';
        del.className = 'cert-del';
        del.setAttribute('aria-label', t('delete'));
        del.innerHTML = icon('trash', 19);
        del.addEventListener('click', (e) => {
            e.stopPropagation();
            onDelete(fileName);
        });
        li.appendChild(del);

        list.appendChild(li);
    }
}

// ==================== 模式页 ====================

export type SwitchModeHandler = (mode: RunMode) => void;

export function renderModeSection(elId: string, mode: RunMode, onPick: SwitchModeHandler): void {
    const el = document.getElementById(elId);
    if (!el) return;

    el.innerHTML = `
        <div class="section-title"><span>${esc(t('modeCurrentTitle'))}</span></div>
        <div class="card">
            <div class="row">
                ${tile('layers', 't-blue')}
                <div class="txt">
                    <div class="t">${esc(mode === 'compatible' ? t('compatibleMode') : t('builtinMode'))}</div>
                    <div class="s">${esc(t('modeDesc'))}</div>
                </div>
                <span class="pill good">${esc(t('certActive'))}</span>
            </div>
            <div class="row pad-seg">
                <div class="seg" id="modeSeg">
                    <button type="button" data-mode="compatible" class="${mode === 'compatible' ? 'active' : ''}">${esc(t('compatibleMode'))}</button>
                    <button type="button" data-mode="builtin" class="${mode === 'builtin' ? 'active' : ''}">${esc(t('builtinMode'))}</button>
                </div>
            </div>
        </div>

        <div class="section-title"><span>${esc(t('modeExplainTitle'))}</span></div>
        <div class="card">
            <div class="row">
                ${tile('shield', 't-green')}
                <div class="txt">
                    <div class="t">${esc(t('compatibleMode'))}</div>
                    <div class="s">${esc(t('compatibleDesc'))}</div>
                </div>
            </div>
            <div class="row">
                ${tile('folder', 't-violet')}
                <div class="txt">
                    <div class="t">${esc(t('builtinMode'))}</div>
                    <div class="s">${esc(t('builtinDesc'))}</div>
                </div>
            </div>
        </div>
        <p class="mode-note">${esc(t('modeSwitchHint'))}</p>
    `;

    el.querySelectorAll<HTMLButtonElement>('#modeSeg button').forEach((btn) => {
        btn.addEventListener('click', () => {
            const next = btn.getAttribute('data-mode') as RunMode;
            if (next && next !== mode) onPick(next);
        });
    });
}

// ==================== 日志 ====================

export function renderLog(elId: string, lines: string[], countElId?: string): void {
    const el = document.getElementById(elId);
    if (el) el.textContent = (lines && lines.length ? lines : [t('noLog')]).join('\n');
    if (countElId) {
        const c = document.getElementById(countElId);
        if (c) c.textContent = lines && lines.length ? `${lines.length} lines` : '';
    }
}

// ==================== 语言弹层 ====================

export interface LangOption { code: string; name: string; native: string; flag: string; }

export function renderLangSheet(elId: string, options: LangOption[], current: string, onPick: (code: string) => void): void {
    const el = document.getElementById(elId);
    if (!el) return;
    el.innerHTML = options.map((o) => {
        const on = o.code === current;
        return `<button type="button" class="lang-row" data-code="${esc(o.code)}">
            <span class="flag">${o.flag}</span>
            <span class="lang-txt"><span class="lang-name">${esc(o.name)}</span><span class="lang-code">${esc(o.native)}</span></span>
            <span class="radio ${on ? 'on' : ''}">${on ? icon('check', 14) : ''}</span>
        </button>`;
    }).join('');

    el.querySelectorAll<HTMLButtonElement>('.lang-row').forEach((btn) => {
        btn.addEventListener('click', () => {
            const code = btn.getAttribute('data-code') || '';
            onPick(code);
        });
    });
}

/** 设置页里更新当前语言文字 */
export function setLangLabel(elId: string, label: string): void {
    const el = document.getElementById(elId);
    if (el) el.textContent = label;
}
