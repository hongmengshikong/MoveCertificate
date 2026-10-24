/**
 * MoveCertificate — 主题管理
 * 三种主题：跟随系统（auto）/ 浅色 / 深色，保存在 localStorage。
 * 视觉由 CSS 变量驱动，这里只负责切换 <html data-theme>。
 */

const THEME_STORAGE_KEY = 'movecert_theme';

export type Theme = 'dark' | 'light' | 'auto';

/** 读取主题（无效值回退到跟随系统） */
export function getTheme(): Theme {
    const saved = localStorage.getItem(THEME_STORAGE_KEY);
    if (saved === 'dark' || saved === 'light' || saved === 'auto') return saved;
    return 'auto';
}

/** 应用主题 */
export function applyTheme(theme: Theme): void {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem(THEME_STORAGE_KEY, theme);
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', theme === 'light' ? '#f2f3f5' : '#000000');
    syncThemeSeg();
}

/** 同步设置页分段控件的选中态 */
export function syncThemeSeg(): void {
    const current = getTheme();
    document.querySelectorAll<HTMLElement>('#themeSeg button').forEach((btn) => {
        btn.classList.toggle('active', btn.getAttribute('data-theme') === current);
    });
}

/** 初始化：应用已保存主题 */
export function initTheme(): void {
    document.documentElement.setAttribute('data-theme', getTheme());
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', getTheme() === 'light' ? '#f2f3f5' : '#000000');
    syncThemeSeg();
}

/** 绑定设置页主题按钮 */
export function bindThemeSeg(): void {
    document.querySelectorAll<HTMLElement>('#themeSeg button').forEach((btn) => {
        btn.addEventListener('click', () => {
            const theme = btn.getAttribute('data-theme') as Theme;
            if (theme) applyTheme(theme);
        });
    });
}
