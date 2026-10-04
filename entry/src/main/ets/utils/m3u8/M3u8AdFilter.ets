import Logger from '../Logger';
import HttpUtils from '../HttpUtils';
import M3U8Utils from './M3U8Utils';
import LocalPlaylistServer from './LocalPlaylistServer';
import M3u8PtsFilter from './M3u8PtsFilter';
import { appSettings } from '../../entryability/Settings';

// 广告分片路径特征：具体标识来自 MoviePilot lunatvsource 的 DEFAULT_HLS_AD_FILTER_REGEX，
// 通用模式匹配被 / _ . - 分隔的 ad/advert/promo/sponsor 路径段（边界保护，upload.ts 等不会误中）
const AD_SEGMENT_PATTERN =
  /adjump|redtraffic|alimama|chenggao|laomaotao|[/_.-](?:ad|ads|advert|advertisement|promo|sponsor)[/_.-]/i;

/**
 * m3u8 广告拦截：部分 CDN 会在播放列表中注入贴片广告分片，播放前抓取播放列表，
 * 两级过滤后经本地 HTTP 服务下发（播放器对本地 m3u8 文件解析不一致，统一走 HTTP 加载路径）：
 * 1. URL 特征过滤（removeAdSegments）：剔除路径含 ad/advert/promo 等特征的广告分片；
 * 2. PTS 连续性过滤（M3u8PtsFilter）：处理分片名无 URL 特征的混入广告——
 *    正片分片按 EXT-X-DISCONTINUITY 分组后 PTS 时钟全程连续，广告组拥有独立 PTS 时钟，
 *    小流量探测各组首分片后剔除不在主时间线上的广告组。
 * 地址为多码率主列表时下钻：单变体主列表抓取唯一变体继续过滤（WebView 嗅探常捕获到
 * 主列表而非媒体列表），多变体主列表不做改写。
 * 仅当源配置 adFilter 为 true（参与过滤）且全局设置 m3u8_ad_filter 开启时过滤，
 * 未配置/false 的源一律不过滤；任何失败均回退原始地址，不影响正常播放。
 */
export default class M3u8AdFilter {
  /** 原始地址 -> 本地服务播放地址（进程内缓存） */
  private static cache: Record<string, string> = {}
  /** 进行中的抓取任务：预热与正式播放并发时复用同一请求 */
  private static inflight: Record<string, Promise<string>> = {}
  /** 源级开关（详情页按当前源注入）：true=跟随全局设置参与过滤，false/null=该源不过滤 */
  private static sourceAdFilter: boolean | null = null

  /** 注入源级广告拦截开关：adFilter 为 true 且全局开关开启时才过滤 */
  static setSourceAdFilter(value: boolean | null): void {
    M3u8AdFilter.sourceAdFilter = value
  }

  /**
   * 预热：地址解析完成后立即抓取并过滤播放列表，
   * 正式播放时命中缓存/复用任务，过滤耗时被后续准备工作重叠掉
   */
  static prewarm(url: string): void {
    M3u8AdFilter.getPlayableUrl(url).then((_playableUrl: string): void => {
    })
  }

  static getPlayableUrl(url: string): Promise<string> {
    if (M3u8AdFilter.sourceAdFilter !== true || !appSettings.m3u8_ad_filter) {
      return Promise.resolve(url)
    }
    if (!url || !url.startsWith('http') || url.toLowerCase().indexOf('.m3u8') < 0) {
      return Promise.resolve(url)
    }
    const hit = M3u8AdFilter.cache[url]
    if (hit) {
      return Promise.resolve(hit)
    }
    let pending = M3u8AdFilter.inflight[url]
    if (!pending) {
      pending = M3u8AdFilter.filterPlaylist(url)
      M3u8AdFilter.inflight[url] = pending
    }
    return pending
  }

  private static async filterPlaylist(url: string): Promise<string> {
    try {
      let content = await HttpUtils.getString(url)
      if (!content || content.indexOf('#EXTM3U') < 0) {
        return url
      }
      // 分片地址解析基准：默认为列表自身，主列表下钻后为其变体地址
      let baseUrl = url
      if (content.indexOf('#EXT-X-STREAM-INF') >= 0) {
        // 多码率主列表：仅单变体时下钻到媒体列表过滤（WebView 嗅探常捕获到主列表，
        // 不下钻会导致变体列表中的广告全部漏过滤）；多变体保持原样
        const variantUrl = M3u8AdFilter.singleVariantUrl(content, url)
        if (!variantUrl) {
          return url
        }
        baseUrl = variantUrl
        content = await HttpUtils.getString(variantUrl)
        if (!content || content.indexOf('#EXTM3U') < 0) {
          return url
        }
      }
      if (content.indexOf('#EXT-X-ENDLIST') < 0) {
        // 直播列表不做改写
        return url
      }
      const urlFiltered = M3u8AdFilter.removeAdSegments(content)
      // PTS 连续性过滤：处理分片名无 URL 特征的混入广告（详见 M3u8PtsFilter）
      const filtered = await M3u8PtsFilter.filter(urlFiltered, baseUrl)
      if (filtered === content) {
        return url
      }
      const rewritten = M3u8AdFilter.absolutizeUrls(filtered, baseUrl)
      const httpUrl = await LocalPlaylistServer.register(rewritten, M3u8AdFilter.hashUrl(url))
      if (httpUrl) {
        M3u8AdFilter.cache[url] = httpUrl
        Logger.d('M3u8AdFilter', '已剔除广告分片，本地服务播放列表: ' + httpUrl
          + ' lines=' + rewritten.split('\n').length)
        return httpUrl
      }
      return url
    } catch (e) {
      Logger.e('fail', 'M3u8AdFilter 过滤失败，回退原始地址', e)
      return url
    }
  }

  /**
   * 单变体主列表下钻：返回唯一变体（媒体列表）的绝对地址；
   * 无变体或多变体（逐一探测过滤成本高，保持原样）返回 null
   */
  private static singleVariantUrl(content: string, playlistUrl: string): string | null {
    const lines: string[] = content.split('\n')
    let variant: string | null = null
    let expectUri = false
    for (const raw of lines) {
      const line = raw.trim()
      if (line.startsWith('#EXT-X-STREAM-INF')) {
        if (variant !== null) {
          return null
        }
        expectUri = true
      } else if (expectUri && line.length > 0 && !line.startsWith('#')) {
        variant = line
        expectUri = false
      }
    }
    if (!variant) {
      return null
    }
    return M3U8Utils.getM3U8MasterUrl(playlistUrl, variant)
  }

  /**
   * 剔除广告分片：优先处理 EXT-X-DISCONTINUITY 标记的区块（区块内全部为广告分片时
   * 连同两侧标记一并删除）；无标记时退化为直接剔除命中特征的分片及其 EXTINF 行。
   */
  private static removeAdSegments(content: string): string {
    const lines: string[] = content.split('\n')
    const output: string[] = []
    let changed = false
    let i = 0
    while (i < lines.length) {
      const line = lines[i].trim()
      if (line === '#EXT-X-DISCONTINUITY') {
        let j = i + 1
        while (j < lines.length && lines[j].trim() !== '#EXT-X-DISCONTINUITY') {
          j++
        }
        const block: string[] = lines.slice(i + 1, j)
        if (M3u8AdFilter.isAllAdSegments(block)) {
          changed = true
          i = Math.min(j + 1, lines.length)
          continue
        }
      }
      output.push(lines[i])
      i++
    }
    if (changed) {
      return output.join('\n')
    }
    return M3u8AdFilter.removeBareAdLines(content)
  }

  private static isAllAdSegments(block: string[]): boolean {
    let urlCount = 0
    let adCount = 0
    for (const raw of block) {
      const line = raw.trim()
      if (line.length === 0 || line.startsWith('#')) {
        continue
      }
      urlCount++
      if (AD_SEGMENT_PATTERN.test(line)) {
        adCount++
      }
    }
    return urlCount > 0 && urlCount === adCount
  }

  private static removeBareAdLines(content: string): string {
    const lines: string[] = content.split('\n')
    const output: string[] = []
    let changed = false
    for (const raw of lines) {
      const line = raw.trim()
      if (line.length > 0 && !line.startsWith('#') && AD_SEGMENT_PATTERN.test(line)) {
        changed = true
        if (output.length > 0 && output[output.length - 1].trim().startsWith('#EXTINF')) {
          output.pop()
        }
        continue
      }
      output.push(raw)
    }
    return changed ? output.join('\n') : content
  }

  /**
   * 分片/密钥地址全部改写为绝对地址：本地播放列表中的相对地址无法被播放器解析
   */
  private static absolutizeUrls(content: string, playlistUrl: string): string {
    const lines: string[] = content.split('\n')
    const output: string[] = []
    for (const raw of lines) {
      const line = raw.trim()
      if (line.length === 0) {
        output.push(raw)
        continue
      }
      if (line.startsWith('#EXT-X-KEY') || line.startsWith('#EXT-X-MAP')) {
        output.push(raw.replace(/URI="([^"]+)"/, (m: string, u: string): string => {
          return 'URI="' + M3U8Utils.getM3U8MasterUrl(playlistUrl, u) + '"'
        }))
        continue
      }
      if (line.startsWith('#')) {
        output.push(raw)
        continue
      }
      output.push(M3U8Utils.getM3U8MasterUrl(playlistUrl, line))
    }
    return output.join('\n')
  }

  private static hashUrl(url: string): string {
    let h = 5381
    for (let i = 0; i < url.length; i++) {
      h = ((h << 5) + h + url.charCodeAt(i)) | 0
    }
    return (h >>> 0).toString(16)
  }
}
