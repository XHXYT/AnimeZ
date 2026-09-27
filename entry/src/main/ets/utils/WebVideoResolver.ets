// WebVideoResolver.ets
// 全局 WebView 视频链接解析器：
// 1. 解析通道单用（AnimeState 上的 WebView 状态字段仅一份），播放与下载的并发请求
//    经 Promise 链串行排队，避免相互覆盖 webviewUrl 导致解析串台；
// 2. 自动模式（隐藏 1x1 WebView 执行源 JS）失败后转手动点击兜底（底部半模态页面，
//    用户点击站点播放按钮后经 animeBridge 桥回传地址）；
// 3. 解析结果内存缓存（TTL 控制）：播放解析过一次后，下载同一集可直接复用，
//    反之亦然；重试过期链接时传 skipCache 强制重新解析；
// 4. WebView 宿主为 Index 根部的 WebParseOverlay 组件（components/WebParseOverlay.ets），
//    本类只驱动 AnimeState 状态，不持有任何 UI。
import { AnimeState } from '../entryability/AnimeState';
import { M3U8Sniffer } from './m3u8/M3U8Sniffer';
import { StringUtils } from './StringUtils';
import Logger from './Logger';
import { registerWebResolveFns } from './download/WebResolveRegistry';

/** 解析结果缓存条目 */
interface ResolvedLinkEntry {
  url: string;
  resolvedAt: number;
}

export class WebVideoResolver {

  /**
   * 手动点击兜底模式注入的钩子 JS：
   * 拦截站点自身发起的 resolve XHR，捕获其响应中的真实播放地址，
   * 同时通用嗅探 XHR/fetch 中的 .m3u8 请求地址（适用于 hls.js/MSE 型播放器，
   * 其 video.src 为 blob: 无法直接读取），
   * 经 animeBridge.onLink 桥回传给应用完成原生播放。
   * 前 10 秒内收到的 403 视为站点残留的自动尝试，忽略不回传。
   */
  private static readonly MANUAL_HOOK_JS: string =
    `(function(){var posted=false;var t0=Date.now();function post(v){if(posted){return;}try{window.animeBridge.onLink(String(v));posted=true;}catch(e){}}function sniff(u){try{u=String(u);if(u.indexOf('http')===0&&u.indexOf('.m3u8')>=0){post(u);}}catch(e){}}var oo=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(m,u){try{sniff(u);if(String(u).indexOf('resolve-play-url')>=0){var x=this;x.addEventListener('load',function(){try{var st=x.status;var late=Date.now()-t0>10000;if(st>=200&&st<300){var r=JSON.parse(x.responseText);var d=(r&&r.data)?r.data:r;if(d&&d.url&&String(d.url).indexOf('http')===0){post(d.url);}else{post('ERR_SITE_BADRESP');}}else if(st===403){if(late){post('ERR_HTTP_403');}}else{if(late){post('ERR_HTTP_'+st);}}}catch(e){}});}}catch(e){}return oo.apply(this,arguments);};var of=window.fetch;window.fetch=function(){try{var a=arguments[0];sniff(typeof a==='string'?a:((a&&a.url)||''));}catch(e){}return of.apply(this,arguments);};return 'HOOK';})()`;

  /** 解析结果缓存（key 为原始 _|_ 链接），内存级，应用重启失效 */
  private static cache: Map<string, ResolvedLinkEntry> = new Map();
  /** 缓存有效期（签名链接时效未知，取保守值，过期后由 403 触发重新解析兜底） */
  private static readonly CACHE_TTL_MS: number = 30 * 60 * 1000;
  /** 串行队列尾：解析通道单用，并发请求依次执行 */
  private static chain: Promise<void> = Promise.resolve();

  /**
   * 解析视频链接
   * @param input 形如 'rawLink_|_js' 的链接，或直接的URL（原样返回）
   * @param skipCache 跳过缓存强制走 WebView 重新解析（链接过期重试场景）
   */
  static async resolve(input: string, skipCache: boolean = false): Promise<string> {
    if (!input || !input.includes('_|_')) {
      return input
    }
    if (!skipCache) {
      const cached = WebVideoResolver.peekCache(input)
      if (cached !== '') {
        Logger.d('tips', 'WebVideoResolver 命中解析缓存，跳过WebView')
        return cached
      }
    }
    const url = await WebVideoResolver.enqueue(input)
    WebVideoResolver.putCache(input, url)
    return url
  }

  /** 加入串行队列执行解析（失败时错误原样抛出，不写缓存） */
  private static enqueue(input: string): Promise<string> {
    const result = WebVideoResolver.chain.then((): Promise<string> => {
      return WebVideoResolver.resolveInner(input)
    })
    WebVideoResolver.chain = result.then((): void => {
    }, (): void => {
    })
    return result
  }

  /**
   * 解析含 _|_ 的网页链接
   * 阶段一：自动解析，最多2次尝试（_r 参数供页面 JS 区分尝试序号，每次重建 WebView 获取新凭证）
   * 阶段二：自动失败后进入手动点击兜底模式
   */
  private static async resolveInner(input: string): Promise<string> {
    const rawLink = StringUtils.splitString(input, '_|_').first
    const js = StringUtils.splitString(input, '_|_').second
    if (!rawLink || !js) {
      throw new Error('Invalid URL format for JS parsing.')
    }

    const sep = rawLink.includes('?') ? '&' : '?'
    let lastErr = 'ERR_UNKNOWN'

    // 阶段一：自动解析，最多2次尝试
    for (let attempt = 1; attempt <= 2; attempt++) {
      AnimeState.webviewManual = false
      AnimeState.webviewManualReason = ''
      AnimeState.webJsVideoLink = ''
      AnimeState.webviewUrl = `${rawLink}${sep}_r=${attempt}`
      AnimeState.runJs = js
      M3U8Sniffer.arm()
      // src 变化不会触发已存在的 Web 组件重新加载，必须重建组件
      AnimeState.showWebView = false
      await WebVideoResolver.sleep(300)
      AnimeState.showWebView = true
      Logger.d('tips', `WebVideoResolver 自动解析第${attempt}次尝试，目标URL: ${AnimeState.webviewUrl}`)

      const result = await WebVideoResolver.waitWebViewResult(25000)
      if (result.includes('http') && !result.startsWith('ERR_')) {
        Logger.d('tips', `WebVideoResolver 成功获取JS链接: ${result}`)
        WebVideoResolver.finishWebView()
        return result
      }
      lastErr = result
      // 仅凭证失败(403)时换帧率参数再试一次，其它错误直接进入手动兜底
      if (!lastErr.startsWith('ERR_HTTP_403')) {
        break
      }
    }

    // 阶段二：自动解析失败，进入手动点击兜底模式（显示真实页面，用户点击播放后捕获站点自身解析结果）
    Logger.e('tips', `WebVideoResolver 自动解析失败(${lastErr})，进入手动点击模式`)
    let reason = '自动解析未能获取播放地址'
    if (lastErr.startsWith('ERR_HTTP_403')) {
      reason = '站点播放凭证校验未通过'
    } else if (lastErr === 'ERR_TIMEOUT') {
      reason = '自动解析超时'
    }
    AnimeState.webviewManualReason = `${reason} · ${lastErr}`
    AnimeState.webviewManual = true
    AnimeState.webJsVideoLink = ''
    AnimeState.webviewUrl = `${rawLink}${sep}_m=${Date.now()}`
    AnimeState.runJs = WebVideoResolver.MANUAL_HOOK_JS
    M3U8Sniffer.arm()
    AnimeState.showWebView = false
    await WebVideoResolver.sleep(300)
    AnimeState.showWebView = true

    const manualResult = await WebVideoResolver.waitWebViewResult(120000)
    WebVideoResolver.finishWebView()
    if (manualResult.includes('http') && !manualResult.startsWith('ERR_')) {
      Logger.d('tips', `WebVideoResolver 手动模式成功获取链接: ${manualResult}`)
      return manualResult
    }
    Logger.e('fail', `WebVideoResolver 手动模式解析失败: ${manualResult}`)
    throw new Error(`播放地址解析失败: ${manualResult}`)
  }

  /**
   * 轮询等待 WebView JS 结果（runJavaScript 返回值或 animeBridge 桥回调写入 webJsVideoLink）
   * @param timeoutMs 超时时间
   * @returns 回传内容（http 链接或 ERR_ 错误串），超时返回 'ERR_TIMEOUT'
   */
  private static async waitWebViewResult(timeoutMs: number): Promise<string> {
    const startTime = Date.now()
    while (true) {
      const jsLink = AnimeState.webJsVideoLink
      if (jsLink && jsLink !== '') {
        return jsLink
      }
      if (Date.now() - startTime > timeoutMs) {
        AnimeState.showWebView = false
        Logger.e('fail', 'waitWebViewResult: 等待JS结果超时。')
        return 'ERR_TIMEOUT'
      }
      await WebVideoResolver.sleep(500)
    }
  }

  /** 收尾：隐藏 WebView 并复位手动模式标志 */
  private static finishWebView(): void {
    AnimeState.showWebView = false
    AnimeState.webviewManual = false
    AnimeState.webviewManualReason = ''
    M3U8Sniffer.disarm()
  }

  /** 读取缓存，过期或不存在返回空串 */
  private static peekCache(key: string): string {
    const entry = WebVideoResolver.cache.get(key)
    if (!entry) {
      return ''
    }
    if (Date.now() - entry.resolvedAt > WebVideoResolver.CACHE_TTL_MS) {
      WebVideoResolver.cache.delete(key)
      return ''
    }
    return entry.url
  }

  /** 写入缓存 */
  private static putCache(key: string, url: string): void {
    if (!url) {
      return
    }
    const entry: ResolvedLinkEntry = { url: url, resolvedAt: Date.now() }
    WebVideoResolver.cache.set(key, entry)
  }

  /**
   * 按解析结果失效缓存条目（播放器报错重试场景）：
   * 直链由 CDN 签名/时效控制，播放失败大概率是链接过期，
   * 删除命中该直链的缓存条目后，下一次 resolve 将强制走 WebView 重新解析
   */
  static invalidateResolved(url: string): void {
    if (!url) {
      return
    }
    const staleKeys: string[] = []
    WebVideoResolver.cache.forEach((entry: ResolvedLinkEntry, key: string) => {
      if (entry.url === url) {
        staleKeys.push(key)
      }
    })
    for (let i = 0; i < staleKeys.length; i++) {
      WebVideoResolver.cache.delete(staleKeys[i])
    }
    if (staleKeys.length > 0) {
      Logger.d('tips', `WebVideoResolver 已失效 ${staleKeys.length} 条过期解析缓存`)
    }
  }

  /** 异步等待 */
  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms)
    })
  }
}

/** 应用启动时调用（EntryAbility.onCreate），把解析封装注入注册表供 .ts 下载层调用 */
export function initWebVideoResolver(): void {
  registerWebResolveFns({
    resolveWebVideoUrl: (url: string, skipCache: boolean): Promise<string> => {
      return WebVideoResolver.resolve(url, skipCache)
    }
  })
}
