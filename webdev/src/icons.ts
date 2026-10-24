/**
 * MoveCertificate — 内联 SVG 图标
 * 统一 24×24 线性图标（stroke=currentColor），避免依赖任何图标库。
 */

/** 图标路径表：key → SVG 内部片段 */
const PATHS: Record<string, string> = {
    shield: '<path d="M12 3l7 3v5.5c0 4.4-2.9 7.9-7 9.5-4.1-1.6-7-5.1-7-9.5V6l7-3z"/><path d="M9 12l2 2 4-4"/>',
    layers: '<path d="M12 3l9 5-9 5-9-5 9-5z"/><path d="M3 12.5l9 5 9-5"/><path d="M3 17l9 5 9-5"/>',
    folder: '<path d="M3 7.5A2.5 2.5 0 0 1 5.5 5h3.2l2 2.4h7.8A2.5 2.5 0 0 1 21 9.9v7.6a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17.5v-10z"/>',
    terminal: '<path d="M4 17l5.5-5L4 7"/><path d="M12 19h8"/>',
    sliders: '<path d="M4 21v-6M4 11V3M12 21v-9M12 8V3M20 21v-4M20 13V3"/><circle cx="4" cy="13" r="2"/><circle cx="12" cy="10" r="2"/><circle cx="20" cy="15" r="2"/>',
    gear: '<circle cx="12" cy="12" r="3.2"/><path d="M19.4 14.5a1.7 1.7 0 0 0 .34 1.87l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.7 1.7 0 0 0-1.87-.34 1.7 1.7 0 0 0-1.03 1.55V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.11-1.55 1.7 1.7 0 0 0-1.87.34l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.7 1.7 0 0 0 .34-1.87 1.7 1.7 0 0 0-1.55-1.03H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.55-1.11 1.7 1.7 0 0 0-.34-1.87l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.7 1.7 0 0 0 1.87.34H9a1.7 1.7 0 0 0 1.03-1.55V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1.03 1.55 1.7 1.7 0 0 0 1.87-.34l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.7 1.7 0 0 0-.34 1.87V9a1.7 1.7 0 0 0 1.55 1.03H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1.47z"/>',
    refresh: '<path d="M20.5 12a8.5 8.5 0 1 1-2.49-6.01"/><path d="M20.5 3.5v5h-5"/>',
    moon: '<path d="M20.5 13.2A8.5 8.5 0 1 1 10.8 3.5a6.6 6.6 0 0 0 9.7 9.7z"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
    globe: '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17"/><path d="M12 3.5c2.2 2.3 3.4 5.3 3.4 8.5S14.2 18.2 12 20.5C9.8 18.2 8.6 15.2 8.6 12S9.8 5.8 12 3.5z"/>',
    check: '<path d="M20 6.5L9.2 17.3 4 12.1"/>',
    chevron: '<path d="M9.5 6l6 6-6 6"/>',
    trash: '<path d="M3.5 6.5h17"/><path d="M9 6.5V4.2h6v2.3"/><path d="M6.2 6.5l.9 13h9.8l.9-13"/>',
    users: '<circle cx="9" cy="8.5" r="3.5"/><path d="M2.8 20c.6-3.4 3.2-5.4 6.2-5.4s5.6 2 6.2 5.4"/><path d="M16.5 5.6a3.4 3.4 0 0 1 0 6.6"/><path d="M18 14.9c2 .6 3.4 2.3 3.8 5.1"/>',
    link: '<path d="M10.5 13.5a4 4 0 0 0 5.66 0l2.4-2.4a4 4 0 0 0-5.66-5.66L11.3 7"/><path d="M13.5 10.5a4 4 0 0 0-5.66 0l-2.4 2.4a4 4 0 0 0 5.66 5.66l1.6-1.6"/>',
    info: '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5.5"/><circle cx="12" cy="8" r=".9" fill="currentColor" stroke="none"/>',
    bolt: '<path d="M13 2.5L4.5 13.5H11l-1 8 8.5-11H12l1-8z"/>',
    cert: '<path d="M6 3.5h9.5L20 8v12.5H6z"/><path d="M15 3.5V8h4.5"/><path d="M9.5 13h6M9.5 16.5h4"/>',
    lock: '<rect x="4.5" y="10" width="15" height="10.5" rx="3"/><path d="M8 10V7.5a4 4 0 0 1 8 0V10"/>',
};

/** 生成一个内联 SVG 字符串 */
export function icon(name: keyof typeof PATHS | string, size = 22): string {
    const body = PATHS[name] || PATHS.info;
    return `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;
}

/** 直接塞进元素的 innerHTML */
export function setIcon(el: Element | null, name: string, size = 22): void {
    if (el) el.innerHTML = icon(name, size);
}
