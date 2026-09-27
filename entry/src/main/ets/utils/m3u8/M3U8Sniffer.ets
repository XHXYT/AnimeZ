import { webview } from '@kit.ArkWeb';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import Logger from '../Logger';
import { AnimeState } from '../../entryability/AnimeState';

const SNIFFER_TAG = 'M3U8Sniffer';
/** 切片流总时长低于该阈值（秒）视为疑似广告片 */
const AD_DURATION_THRESHOLD = 60;
/** 疑似广告候选的静默等待时长（毫秒）：期间出现更优候选则改用之 */
const FALLBACK_QUIET_MS = 5000;
/** 验证请求超时（毫秒） */
const VALIDATE_TIMEOUT_MS = 6000;

/**
 * WebView 网络层 m3u8 嗅探器（WebSchemeHandler 纯旁路通道）：
 * 为解析用 WebView 注册 https scheme handler，onRequestStart 一律返回 false（不拦截，
 * 请求照常走默认网络栈），仅读取 URL 捕获 .m3u8 请求。与 iframeSelector JS/animeBridge
 * 桥通道并行工作，谁先拿到可用地址谁写入 webJsVideoLink。
 *
 * 多个 m3u8 的区分策略：
 * 1. 同 URL 去重；
 * 2. 内容验证（m3u8 为小文本文件，App 侧补一发 GET）：
 *    - 非 #EXTM3U 开头视为假阳性，丢弃；
 *    - 含 #EXT-X-STREAM-INF 为主播放列表（hls.js 加载源后的首个请求），直接交付；
 *    - 普通切片流按 #EXTINF 累计时长：≥阈值交付；过短疑似贴片广告，静默期待更优候选，
 *      超时后兜底交付；
 *    - 验证请求自身失败（CDN 校验请求头等）时信任页面请求，直接交付。
 */
export class M3U8Sniffer {
  private static armed: boolean = false;
  private static delivered: boolean = false;
  private static candidates: string[] = [];
  private static fallbackUrl: string = '';
  private static fallbackTimer: number = -1;
  private static handler: webview.WebSchemeHandler | null = null;

  /** 开始一次嗅探会话（每次解析尝试前调用） */
  static arm(): void {
    M3U8Sniffer.armed = true;
    M3U8Sniffer.delivered = false;
    M3U8Sniffer.candidates = [];
    M3U8Sniffer.fallbackUrl = '';
    M3U8Sniffer.clearFallbackTimer();
  }

  /** 结束嗅探会话（WebView 收尾时调用），非会话期间一律忽略 */
  static disarm(): void {
    M3U8Sniffer.armed = false;
    M3U8Sniffer.candidates = [];
    M3U8Sniffer.fallbackUrl = '';
    M3U8Sniffer.clearFallbackTimer();
  }

  /** 为解析 WebView 注册 scheme handler（幂等，在 controller 绑定后调用） */
  static attach(controller: webview.WebviewController): void {
    try {
      if (M3U8Sniffer.handler === null) {
        M3U8Sniffer.handler = new webview.WebSchemeHandler();
        M3U8Sniffer.handler.onRequestStart((request: webview.WebSchemeHandlerRequest,
          handler: webview.WebResourceHandler): boolean => {
          M3U8Sniffer.onRequest(request);
          return false;
        });
      }
      controller.setWebSchemeHandler('https', M3U8Sniffer.handler);
      Logger.d(SNIFFER_TAG, 'schemeHandler 已注册');
    } catch (error) {
      Logger.e('fail', '注册 schemeHandler 失败', error);
    }
  }

  private static onRequest(request: webview.WebSchemeHandlerRequest): void {
    if (!M3U8Sniffer.armed || M3U8Sniffer.delivered) {
      return;
    }
    const url: string = request.getRequestUrl();
    if (url === '' || url.toLowerCase().indexOf('.m3u8') < 0 ||
      (url.indexOf('https://') !== 0 && url.indexOf('http://') !== 0)) {
      return;
    }
    if (M3U8Sniffer.candidates.indexOf(url) >= 0) {
      return;
    }
    M3U8Sniffer.candidates.push(url);
    Logger.d(SNIFFER_TAG, `捕获 m3u8 候选: ${url}`);
    M3U8Sniffer.validate(url);
  }

  private static validate(url: string): void {
    const httpReq = http.createHttp();
    httpReq.request(url, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: VALIDATE_TIMEOUT_MS,
      readTimeout: VALIDATE_TIMEOUT_MS
    }).then((resp: http.HttpResponse) => {
      httpReq.destroy();
      const body: string = typeof resp.result === 'string' ? resp.result : '';
      if (resp.responseCode < 200 || resp.responseCode >= 300 || body.indexOf('#EXTM3U') !== 0) {
        Logger.d(SNIFFER_TAG, `候选非播放列表内容(code=${resp.responseCode})，按页面请求交付`);
        M3U8Sniffer.deliver(url);
        return;
      }
      if (body.indexOf('#EXT-X-STREAM-INF') >= 0) {
        Logger.d(SNIFFER_TAG, '主播放列表确认，立即交付');
        M3U8Sniffer.deliver(url);
        return;
      }
      const duration = M3U8Sniffer.sumExtinf(body);
      if (duration >= AD_DURATION_THRESHOLD) {
        Logger.d(SNIFFER_TAG, `切片流总时长 ${duration}s，交付`);
        M3U8Sniffer.deliver(url);
      } else {
        Logger.d(SNIFFER_TAG, `切片流总时长仅 ${duration}s，疑似广告，转入候补`);
        M3U8Sniffer.holdAsFallback(url);
      }
    }).catch((error: BusinessError) => {
      httpReq.destroy();
      Logger.d(SNIFFER_TAG, `验证请求失败(${error.message})，按页面请求交付`);
      M3U8Sniffer.deliver(url);
    });
  }

  private static sumExtinf(body: string): number {
    let total: number = 0;
    const lines: string[] = body.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];
      if (line.indexOf('#EXTINF:') === 0) {
        const value = Number(line.substring('#EXTINF:'.length));
        if (!Number.isNaN(value)) {
          total += value;
        }
      }
    }
    return total;
  }

  private static holdAsFallback(url: string): void {
    if (M3U8Sniffer.fallbackUrl === '') {
      M3U8Sniffer.fallbackUrl = url;
    }
    if (M3U8Sniffer.fallbackTimer >= 0) {
      return;
    }
    M3U8Sniffer.fallbackTimer = setTimeout(() => {
      M3U8Sniffer.fallbackTimer = -1;
      if (M3U8Sniffer.armed && !M3U8Sniffer.delivered && M3U8Sniffer.fallbackUrl !== '') {
        Logger.d(SNIFFER_TAG, '静默期结束，交付候补候选');
        M3U8Sniffer.deliver(M3U8Sniffer.fallbackUrl);
      }
    }, FALLBACK_QUIET_MS);
  }

  private static deliver(url: string): void {
    if (M3U8Sniffer.delivered || !M3U8Sniffer.armed) {
      return;
    }
    M3U8Sniffer.delivered = true;
    if (AnimeState.webJsVideoLink === '') {
      Logger.d(SNIFFER_TAG, `网络层嗅探交付播放地址: ${url}`);
      AnimeState.webJsVideoLink = url;
    }
  }

  private static clearFallbackTimer(): void {
    if (M3U8Sniffer.fallbackTimer >= 0) {
      clearTimeout(M3U8Sniffer.fallbackTimer);
      M3U8Sniffer.fallbackTimer = -1;
    }
  }
}
