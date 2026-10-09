// WebResolveRegistry.ts
// WebView 视频链接解析注册表：解析器依赖 AnimeState(@ObservedV2) 与全局 Overlay（.ets），
// 而 M3U8Downloader.ts 等 .ts 调用方不能 import .ets —— 由 WebVideoResolver.ets
// 在应用启动时（EntryAbility.onCreate -> initWebVideoResolver）注入实现，.ts 侧经此获取。

/** WebView 视频链接解析封装（由 WebVideoResolver.ets 提供） */
export interface WebResolveFns {
    /**
     * 解析含 _|_ 的网页链接为真实播放地址
     * @param url 形如 'rawLink_|_js' 的链接
     * @param skipCache true 时跳过缓存强制走 WebView 重新解析（链接过期重试场景）
     */
    resolveWebVideoUrl: (url: string, skipCache: boolean) => Promise<string>;
    /**
     * 设置 WebView 解析通道的 User-Agent（源级配置）
     * @param ua 源配置的 userAgent，空串表示恢复系统默认
     */
    setWebViewUserAgent: (ua: string) => void;
}

let webResolveFns: WebResolveFns | null = null;

/** 由 WebVideoResolver.ets 在应用启动时调用（EntryAbility.onCreate -> initWebVideoResolver） */
export function registerWebResolveFns(fns: WebResolveFns): void {
    webResolveFns = fns;
}

export function getWebResolveFns(): WebResolveFns {
    if (webResolveFns === null) {
        throw new Error('WebView解析器未注册：需在 EntryAbility 启动时调用 initWebVideoResolver');
    }
    return webResolveFns;
}
