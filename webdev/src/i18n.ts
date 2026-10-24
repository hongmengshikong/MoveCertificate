/**
 * MoveCertificate — 国际化（i18n）模块
 * 
 * 支持三种语言（对应项目 README 的语言）：
 *   zh-CN — 中文（简体）
 *   en    — English
 *   tr    — Türkçe
 * 
 * 用法：
 *   import { t, setLang, getLang, supportedLangs } from './i18n.js';
 *   t('certsTab')  →  根据当前语言返回对应文字
 *   setLang('en')  →  切换语言
 */

// ==================== 类型定义 ====================

/** 支持的语言代码 */
export type LangCode = 'zh-CN' | 'en' | 'tr';

/** 翻译字典中每个 key 对应的三种语言值 */
type TranslationEntry = Record<LangCode, string>;

/** 支持的语言列表项 */
export interface LangItem {
    code: LangCode;
    name: string;
    nativeName: string;
}

// ==================== 翻译表 ====================
// 每个 key 对应三个语言的翻译值
// 如果你要加新文字，在这里添加一个 key，然后给三种语言分别填上翻译即可

const translations: Record<string, TranslationEntry> = {
    // 页面标题
    appTitle: {
        'zh-CN': 'MoveCertificate',
        en: 'MoveCertificate',
        tr: 'MoveCertificate',
    },

    // ==================== 底部标签 ====================
    certsTab: {
        'zh-CN': '证书管理',
        en: 'Certificates',
        tr: 'Sertifikalar',
    },
    logTab: {
        'zh-CN': '运行日志',
        en: 'Runtime Log',
        tr: 'Çalışma Günlüğü',
    },
    setTab: {
        'zh-CN': '设置',
        en: 'Settings',
        tr: 'Ayarlar',
    },

    // ==================== 证书管理页 ====================
    moduleInfo: {
        'zh-CN': '模块信息',
        en: 'Module Info',
        tr: 'Modül Bilgisi',
    },
    certList: {
        'zh-CN': '证书列表',
        en: 'Certificate List',
        tr: 'Sertifika Listesi',
    },
    loading: {
        'zh-CN': '正在加载…',
        en: 'Loading…',
        tr: 'Yükleniyor…',
    },
    refreshCerts: {
        'zh-CN': '🔄 刷新证书列表',
        en: '🔄 Refresh Certificates',
        tr: '🔄 Sertifikaları Yenile',
    },
    delete: {
        'zh-CN': '删除',
        en: 'Delete',
        tr: 'Sil',
    },


    // ==================== 运行日志页 ====================
    runtimeLog: {
        'zh-CN': '运行日志',
        en: 'Runtime Log',
        tr: 'Çalışma Günlüğü',
    },
    logPlaceholder: {
        'zh-CN': '点击下方刷新按钮加载日志…',
        en: 'Click refresh button below to load log…',
        tr: 'Günlüğü yüklemek için aşağıdaki yenile düğmesine tıklayın…',
    },
    refreshLog: {
        'zh-CN': '🔄 刷新日志',
        en: '🔄 Refresh Log',
        tr: '🔄 Günlüğü Yenile',
    },
    noLog: {
        'zh-CN': '暂无日志',
        en: 'No logs available',
        tr: 'Günlük mevcut değil',
    },

    // ==================== 模态框（删除确认） ====================
    modalTitle: {
        'zh-CN': '此操作不可逆',
        en: 'This action is irreversible',
        tr: 'Bu işlem geri alınamaz',
    },
    confirmDeleteMsg: {
        'zh-CN': '确认要删除这个证书吗？',
        en: 'Are you sure you want to delete this certificate?',
        tr: 'Bu sertifikayı silmek istediğinizden emin misiniz?',
    },
    confirmDeleteCert: {
        'zh-CN': '确认要删除 {0} 证书吗？',
        en: 'Delete certificate {0}?',
        tr: '{0} sertifikası silinsin mi?',
    },
    cancel: {
        'zh-CN': '取消',
        en: 'Cancel',
        tr: 'İptal',
    },
    confirm: {
        'zh-CN': '确认',
        en: 'Confirm',
        tr: 'Onayla',
    },

    // ==================== Toast 消息 ====================
    loadingApp: {
        'zh-CN': 'Loading MoveCertificate!',
        en: 'Loading MoveCertificate!',
        tr: 'MoveCertificate Yükleniyor!',
    },
    deletedReboot: {
        'zh-CN': '{0} 已删除，重启生效！',
        en: '{0} deleted, reboot to take effect!',
        tr: '{0} silindi, etkili olması için yeniden başlatın!',
    },
    deleteFailed: {
        'zh-CN': '删除失败，请重试',
        en: 'Delete failed, please try again',
        tr: 'Silme başarısız, lütfen tekrar deneyin',
    },
    loadFailedRoot: {
        'zh-CN': '加载失败，请检查 root 权限',
        en: 'Load failed, check root permission',
        tr: 'Yükleme başarısız, root iznini kontrol edin',
    },
    noCertFound: {
        'zh-CN': '未检测到已安装的证书',
        en: 'No installed certificates detected',
        tr: 'Yüklü sertifika bulunamadı',
    },
    getVersionFailed: {
        'zh-CN': '获取系统版本失败，请检查 root 权限',
        en: 'Failed to get system version, check root permission',
        tr: 'Sistem sürümü alınamadı, root iznini kontrol edin',
    },
    getCertListFailed: {
        'zh-CN': '获取证书列表失败，请检查 root 权限',
        en: 'Failed to get certificate list, check root permission',
        tr: 'Sertifika listesi alınamadı, root iznini kontrol edin',
    },
    getVersionInfoFailed: {
        'zh-CN': '加载版本信息失败',
        en: 'Failed to load version info',
        tr: 'Sürüm bilgisi yüklenemedi',
    },
    getLogFailed: {
        'zh-CN': '加载日志失败',
        en: 'Failed to load log',
        tr: 'Günlük yüklenemedi',
    },
    
    // ==================== 设置页 ====================
    languageSettings: {
        'zh-CN': '语言设置',
        en: 'Language',
        tr: 'Dil',
    },
    themeSettings: {
        'zh-CN': '主题设置',
        en: 'Theme',
        tr: 'Tema',
    },
    themeDark: {
        'zh-CN': '深色',
        en: 'Dark',
        tr: 'Koyu',
    },
    themeLight: {
        'zh-CN': '浅色',
        en: 'Light',
        tr: 'Açık',
    },
    themeAuto: {
        'zh-CN': '跟随系统',
        en: 'Auto',
        tr: 'Otomatik',
    },
    aboutSection: {
        'zh-CN': '关于',
        en: 'About',
        tr: 'Hakkında',
    },
    contributorsTitle: {
        'zh-CN': '贡献者',
        en: 'Contributors',
        tr: 'Katkıda Bulunanlar',
    },

    // ==================== 新版界面 ====================
    chipCerts: { 'zh-CN': '{0} 张', en: '{0} certs', tr: '{0} sertifika' },
    logSection: { 'zh-CN': '日志内容', en: 'Log output', tr: 'Günlük çıktısı' },
    navCerts: { 'zh-CN': '证书', en: 'Certs', tr: 'Sertifika' },
    navLog: { 'zh-CN': '日志', en: 'Log', tr: 'Günlük' },
    navSet: { 'zh-CN': '设置', en: 'Settings', tr: 'Ayarlar' },

    appSubtitle: {
        'zh-CN': '系统证书迁移',
        en: 'System CA migration',
        tr: 'Sistem CA taşıma',
    },

    certActive: { 'zh-CN': '已生效', en: 'Active', tr: 'Etkin' },
    certInactive: { 'zh-CN': '未生效', en: 'Inactive', tr: 'Etkin değil' },
    certEmpty: {
        'zh-CN': '还没有检测到证书，安装后重启即可',
        en: 'No certificates yet. Install one and reboot.',
        tr: 'Henüz sertifika yok. Yükleyip yeniden başlatın.',
    },
    unknownCert: { 'zh-CN': '未知证书', en: 'Unknown certificate', tr: 'Bilinmeyen sertifika' },
    certFootnote: {
        'zh-CN': '点右侧垃圾桶可删除证书，删除后重启生效',
        en: 'Tap the bin icon to delete a certificate, reboot to apply',
        tr: 'Silmek için çöp kutusuna dokunun, yeniden başlatın',
    },
    refreshCertsPlain: { 'zh-CN': '刷新证书列表', en: 'Refresh certificates', tr: 'Sertifikaları yenile' },
    refreshLogPlain: { 'zh-CN': '刷新日志', en: 'Refresh log', tr: 'Günlüğü yenile' },
    refreshDone: { 'zh-CN': '已刷新', en: 'Refreshed', tr: 'Yenilendi' },

    logHeroSub: {
        'zh-CN': '每次开机写入 /data/adb/modules/MoveCertificate/install.log',
        en: 'Written to install.log on every boot',
        tr: 'Her açılışta install.log dosyasına yazılır',
    },

    setHeroSub: {
        'zh-CN': '语言、外观与项目信息',
        en: 'Language, appearance and project info',
        tr: 'Dil, görünüm ve proje bilgisi',
    },
    prefsSection: { 'zh-CN': '偏好', en: 'Preferences', tr: 'Tercihler' },
    themeSettingsSub: {
        'zh-CN': '跟随系统 / 浅色 / 深色',
        en: 'Auto / Light / Dark',
        tr: 'Otomatik / Açık / Koyu',
    },
    moduleVersion: { 'zh-CN': '模块版本', en: 'Module version', tr: 'Modül sürümü' },
    upstreamTitle: { 'zh-CN': '上游项目', en: 'Upstream', tr: 'Üst kaynak' },
    languagePick: { 'zh-CN': '选择语言', en: 'Choose language', tr: 'Dil seçin' },
    langAuto: { 'zh-CN': '跟随系统', en: 'Follow system', tr: 'Sistemi izle' },
    langAutoSub: {
        'zh-CN': '根据系统语言自动选择',
        en: 'Auto-detect from system language',
        tr: 'Sistem dilinden otomatik algıla',
    },
} as const;

/** 所有翻译 key 的联合类型 */
export type I18nKey = keyof typeof translations;

// ==================== 语言列表 ====================

/** 支持的语言列表 */
export const supportedLangs: readonly LangItem[] = [
    { code: 'zh-CN', name: '中文', nativeName: '中文' },
    { code: 'en',    name: 'English', nativeName: 'English' },
    { code: 'tr',    name: 'Türkçe', nativeName: 'Türkçe' },
] as const;

/** 语言代码对应的显示名称（语言选择器按钮文字用），与 supportedLangs 保持一致 */
export const LANG_LABELS: Record<LangCode, string> = {
    'zh-CN': '中文',
    en: 'English',
    tr: 'Türkçe',
};

// ==================== 语言检测与存储 ====================

/** localStorage 存储键 */
const STORAGE_KEY = 'movecert_lang';

/** 获取当前语言 */
export function getLang(): LangCode {
    // 优先读取用户手动选择
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved && supportedLangs.some(l => l.code === saved)) {
        return saved as LangCode;
    }

    // 自动检测系统语言
    const navLang = navigator.language || '';
    if (navLang.startsWith('zh')) return 'zh-CN';
    if (navLang.startsWith('tr')) return 'tr';
    return 'en';
}

/**
 * 设置语言：保存到 localStorage 并同步内部状态
 * 调用后 t() 立即返回新语言的翻译，调用方无需再做任何额外操作
 */
export function setLang(code: LangCode): void {
    localStorage.setItem(STORAGE_KEY, code);
    currentLang = code;
}

/** 清除手动选择，恢复“跟随系统” */
export function clearLang(): void {
    localStorage.removeItem(STORAGE_KEY);
    currentLang = getLang();
}

/** 当前是否处于“跟随系统” */
export function isAutoLang(): boolean {
    return !localStorage.getItem(STORAGE_KEY);
}

// ==================== 翻译函数 ====================

/** 当前语言 */
let currentLang: LangCode = getLang();

/**
 * 获取翻译文字
 * 
 * @param key - 翻译 key
 * @param args - 可选的替换参数，对应文字中的 {0} {1} 等占位符
 * @returns 翻译后的文字
 * 
 * 用法：
 *   t('delete')                    → '删除'
 *   t('deletedReboot', 'abc.0')   → 'abc.0 已删除，重启生效！'
 */
export function t(key: I18nKey, ...args: string[]): string {
    const dict = translations[key];
    if (!dict) {
        console.warn(`i18n: 缺少翻译 key "${key}"`);
        return key;
    }

    let text: string = dict[currentLang] || dict['en'] || key;

    // 替换占位符 {0} {1} ...
    args.forEach((arg, i) => {
        text = text.replace(`{${i}}`, arg);
    });

    return text;
}

