/**
 * MoveCertificate — 页面渲染层（新版设计）
 *
 * 只负责把数据画成 DOM，不执行任何 shell 命令。
 * 视觉语言：彩色图标块 + 分组卡片 + 胶囊状态 + 底部导航。
 */

import { t } from './i18n.js';
import { icon } from './icons.js';
import type { CertEntry } from './constants.js';

// ==================== 工具 ====================

/** HTML 转义，防止证书名里的特殊字符破坏结构 */
export function esc(s: string): string {
    return String(s).replace(/[&<>"']/g, (c) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c] as string));
}

/** 图标块 */
function tile(iconName: string, cls: string): string {
    return `<div class="tile ${cls}">${icon(iconName, 21)}</div>`;
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

// ==================== 证书列表 ====================

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
