import { util } from '@kit.ArkTS'
import { CryptoJS } from '@ohos/crypto-js'
import HttpUtils from '../utils/HttpUtils'
import Logger from '../utils/Logger'
import {
  DandanplayAnime,
  DandanplayComment,
  DandanplayCommentResponse,
  DandanplayEpisode,
  DandanplayEpisodeMatch,
  DandanplaySearchResponse
} from './DandanplayModels'

/**
 * 配置说明（配置不进入 git 仓库，防止凭据/中转地址泄露）：
 * 在 entry/src/main/resources/rawfile/ 下创建 danmaku_config.json（已被 .gitignore 忽略），格式：
 * { "appId": "xxx", "appSecret": "xxx", "proxyBaseUrl": "https://xxx" }
 * - appId/appSecret：在 https://dev.dandanplay.com 注册开发者并创建应用后获得，
 *   官方要求所有请求必须携带验证头（X-AppId/X-Timestamp/X-Signature），留空请求将被拒绝（403）
 * - proxyBaseUrl：无需凭据的中转接口地址，响应结构与官方基本一致（数据在顶层平铺，解析时两种结构均兼容）
 * - 配置了官方凭据时自动优先使用官方接口；两者均未配置时弹幕功能禁用
 * - 文件缺失或解析失败时使用默认空配置，不影响其他功能
 * 注意：rawfile 会打包进 HAP，分发 HAP 时请勿携带真实凭据构建
 */
const DANDANPLAY_BASE_URL: string = 'https://api.dandanplay.net'

/** 弹幕配置文件结构（rawfile/danmaku_config.json） */
interface DanmakuFileConfig {
  appId: string
  appSecret: string
  proxyBaseUrl: string
}

/** 弹幕缓存有效期（官方要求 2~6 小时，取 4 小时） */
const CACHE_TTL_MS: number = 4 * 60 * 60 * 1000

/** 匹配缓存条目 */
interface MatchCacheEntry {
  episodeId: number
  matchedTitle: string
  cachedAt: number
}

/** 弹幕缓存条目 */
interface CommentCacheEntry {
  comments: DandanplayComment[]
  cachedAt: number
}

/** 弹幕加载状态 */
export enum DanmakuLoadStatus {
  /** 成功加载到弹幕 */
  LOADED = 0,
  /** 匹配失败或请求失败 */
  FAILED = 1,
  /** 匹配成功但该集无弹幕 */
  EMPTY = 2
}

/** 弹幕加载结果 */
export class DanmakuLoadResult {
  status: DanmakuLoadStatus = DanmakuLoadStatus.FAILED
  comments: DandanplayComment[] = []
  matchedTitle: string = ''
}

/** 从标题中提取集数数字，找不到返回 0 */
function extractEpisodeNumber(str: string): number {
  const match = str.match(new RegExp('\\d+'))
  return match ? parseInt(match[0], 10) : 0
}

/**
 * 弹弹play 开放 API 客户端：标题匹配 + 弹幕拉取（带会话内缓存）
 */
export class DandanplayApi {
  /** 匹配缓存：番剧标题#剧集标题 -> episodeId */
  private static matchCache: Map<string, MatchCacheEntry> = new Map()
  /** 弹幕缓存：episodeId -> comments */
  private static commentCache: Map<number, CommentCacheEntry> = new Map()
  /** 官方凭据（从配置文件加载） */
  private static appId: string = ''
  private static appSecret: string = ''
  /** 中转接口地址（从配置文件加载） */
  private static proxyBaseUrl: string = ''
  /** 配置是否已尝试加载（只加载一次，失败不重试） */
  private static configLoaded: boolean = false

  /**
   * 按番剧/剧集标题加载弹幕（先匹配 episodeId 再拉取评论）
   */
  static async loadComments(animeTitle: string, episodeTitle: string): Promise<DanmakuLoadResult> {
    const result = new DanmakuLoadResult()
    if (animeTitle.length === 0) {
      return result
    }
    await DandanplayApi.ensureConfig()
    const cacheKey = `${animeTitle}#${episodeTitle}`
    let episodeId = -1
    const match = DandanplayApi.matchCache.get(cacheKey)
    if (match !== undefined && Date.now() - match.cachedAt < CACHE_TTL_MS) {
      episodeId = match.episodeId
      result.matchedTitle = match.matchedTitle
    } else {
      const found = await DandanplayApi.matchEpisode(animeTitle, episodeTitle)
      if (found === null) {
        return result
      }
      episodeId = found.episodeId
      result.matchedTitle = found.matchedTitle
      const entry: MatchCacheEntry = {
        episodeId: found.episodeId,
        matchedTitle: found.matchedTitle,
        cachedAt: Date.now()
      }
      DandanplayApi.matchCache.set(cacheKey, entry)
    }

    const cached = DandanplayApi.commentCache.get(episodeId)
    if (cached !== undefined && Date.now() - cached.cachedAt < CACHE_TTL_MS) {
      result.comments = cached.comments
      result.status = cached.comments.length > 0 ? DanmakuLoadStatus.LOADED : DanmakuLoadStatus.EMPTY
      return result
    }

    try {
      const comments = await DandanplayApi.fetchComments(episodeId)
      const entry: CommentCacheEntry = { comments: comments, cachedAt: Date.now() }
      DandanplayApi.commentCache.set(episodeId, entry)
      result.comments = comments
      result.status = comments.length > 0 ? DanmakuLoadStatus.LOADED : DanmakuLoadStatus.EMPTY
    } catch (e) {
      Logger.e('fail', `DandanplayApi 拉取弹幕失败 episodeId=${episodeId}`, e)
      result.status = DanmakuLoadStatus.FAILED
    }
    return result
  }

  /** 惰性加载弹幕配置文件（rawfile/danmaku_config.json，允许不存在） */
  private static async ensureConfig(): Promise<void> {
    if (DandanplayApi.configLoaded) {
      return
    }
    DandanplayApi.configLoaded = true
    try {
      const content: Uint8Array =
        await getContext(DandanplayApi).resourceManager.getRawFileContent('danmaku_config.json')
      const text = util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeToString(content)
      const cfg = JSON.parse(text) as DanmakuFileConfig
      if (cfg.appId !== undefined) {
        DandanplayApi.appId = cfg.appId
      }
      if (cfg.appSecret !== undefined) {
        DandanplayApi.appSecret = cfg.appSecret
      }
      if (cfg.proxyBaseUrl !== undefined) {
        DandanplayApi.proxyBaseUrl = cfg.proxyBaseUrl
      }
      Logger.d('tips', `DandanplayApi 配置加载成功 官方凭据=${DandanplayApi.appId.length > 0 ? '已配置' : '未配置'} 中转=${DandanplayApi.proxyBaseUrl.length > 0 ? '已配置' : '未配置'}`)
    } catch (e) {
      Logger.e('fail', 'DandanplayApi 配置文件加载失败(使用默认空配置，弹幕功能禁用)', e)
    }
  }

  /**
   * 标题搜索匹配剧集，返回 episodeId；无合适匹配返回 null
   */
  private static async matchEpisode(animeTitle: string, episodeTitle: string): Promise<DandanplayEpisodeMatch | null> {
    try {
      const episodeNumber = extractEpisodeNumber(episodeTitle)
      const episodeParam = episodeNumber > 0 ? episodeNumber.toString() : episodeTitle
      const path = '/api/v2/search/episodes'
      const baseUrl = DandanplayApi.getBaseUrl()
      if (baseUrl.length === 0) {
        Logger.d('tips', 'DandanplayApi 未配置弹幕数据源，跳过匹配')
        return null
      }
      const url = `${baseUrl}${path}?anime=${encodeURIComponent(animeTitle)}&episode=${encodeURIComponent(episodeParam)}`
      const resp = await DandanplayApi.getJsonWithRetry(url, DandanplayApi.buildHeaders(path)) as DandanplaySearchResponse
      // 兼容中转接口：errorCode/success 字段缺失时不视为错误
      const code = resp.errorCode
      if ((code !== undefined && code !== 0) || (resp.success !== undefined && !resp.success)) {
        Logger.e('fail', `DandanplayApi 搜索失败 code=${code} msg=${resp.errorMessage}`)
        return null
      }
      // 官方结构数据在 result 中，中转结构数据在顶层
      const animes = resp.result !== null && resp.result !== undefined
        ? resp.result.animes : resp.animes
      if (animes === null || animes === undefined || animes.length === 0) {
        Logger.e('fail', `DandanplayApi 搜索无结果 anime="${animeTitle}" episode="${episodeTitle}"`)
        return null
      }
      const bestAnime = DandanplayApi.pickBestAnime(animes, animeTitle)
      if (bestAnime === null) {
        Logger.e('fail', `DandanplayApi 搜索结果无匹配项 anime="${animeTitle}"`)
        return null
      }
      const episodes = bestAnime.episodes
      if (episodes === null || episodes === undefined || episodes.length === 0) {
        return null
      }
      const chosen = DandanplayApi.pickEpisode(episodes, episodeNumber)
      if (chosen === null) {
        return null
      }
      const matchResult: DandanplayEpisodeMatch = {
        episodeId: chosen.episodeId,
        matchedTitle: `${bestAnime.animeTitle} ${chosen.episodeTitle}`
      }
      Logger.d('tips', `DandanplayApi 匹配成功 anime="${animeTitle}" episode="${episodeTitle}" -> "${matchResult.matchedTitle}" episodeId=${matchResult.episodeId} via=${baseUrl}`)
      return matchResult
    } catch (e) {
      Logger.e('fail', 'DandanplayApi 搜索匹配异常', e)
      return null
    }
  }

  /** 选择标题最相近的动画 */
  private static pickBestAnime(animes: DandanplayAnime[], animeTitle: string): DandanplayAnime | null {
    let best: DandanplayAnime | null = null
    let bestScore = -1
    for (const anime of animes) {
      let score = 0
      if (anime.animeTitle === animeTitle) {
        score = 100
      } else if (anime.animeTitle.includes(animeTitle) || animeTitle.includes(anime.animeTitle)) {
        score = 50
      }
      if (score > bestScore) {
        bestScore = score
        best = anime
      }
    }
    return best
  }

  /** 按集数选择剧集；无法确定时仅在唯一剧集时兜底 */
  private static pickEpisode(episodes: DandanplayEpisode[], episodeNumber: number): DandanplayEpisode | null {
    if (episodeNumber > 0) {
      for (const ep of episodes) {
        if (extractEpisodeNumber(ep.episodeTitle) === episodeNumber) {
          return ep
        }
      }
    }
    if (episodes.length === 1) {
      return episodes[0]
    }
    return null
  }

  /** 拉取某集弹幕评论 */
  private static async fetchComments(episodeId: number): Promise<DandanplayComment[]> {
    const path = `/api/v2/comment/${episodeId}`
    const url = `${DandanplayApi.getBaseUrl()}${path}?withRelated=true&chConvert=0`
    const resp = await DandanplayApi.getJsonWithRetry(url, DandanplayApi.buildHeaders(path)) as DandanplayCommentResponse
    // 中转接口弹幕端点顶层可能没有 errorCode/success 字段，字段缺失时视为成功
    const code = resp.errorCode
    if ((code !== undefined && code !== 0) || (resp.success !== undefined && !resp.success)) {
      throw new Error(`dandanplay error ${code}: ${resp.errorMessage}`)
    }
    // 官方结构数据在 result 中，中转结构数据在顶层
    const comments = resp.result !== null && resp.result !== undefined
      ? resp.result.comments : resp.comments
    const list = comments === null || comments === undefined ? [] : comments
    Logger.d('tips', `DandanplayApi 弹幕拉取成功 episodeId=${episodeId} count=${list.length}`)
    return list
  }

  /** 官方凭据已配置时使用官方接口（带签名），否则使用中转接口；均未配置返回空串 */
  private static getBaseUrl(): string {
    if (DandanplayApi.appId.length > 0 && DandanplayApi.appSecret.length > 0) {
      return DANDANPLAY_BASE_URL
    }
    return DandanplayApi.proxyBaseUrl
  }

  /**
   * 带重试的 JSON GET 请求：网络抖动、超时、网关错误页（502 HTML 等非 JSON 响应）自动重试
   * 最多 3 次，间隔递增
   */
  private static async getJsonWithRetry(url: string, headers: Record<string, string>): Promise<object> {
    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        const text = await HttpUtils.getString(url, headers)
        // 网关/反代错误页（如 502 HTML）不是合法 JSON，解析失败同样触发重试
        return JSON.parse(text)
      } catch (e) {
        Logger.e('fail', `DandanplayApi 请求失败(第${attempt}/3次) url=${url}`, e)
        if (attempt === 3) {
          throw new Error(`DandanplayApi 请求失败(已重试3次) url=${url}`)
        }
        await DandanplayApi.delay(800 * attempt)
      }
    }
    throw new Error('unreachable')
  }

  /** 延时工具 */
  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms)
    })
  }

  /**
   * 构造签名请求头；未配置凭据时返回空表（匿名请求）
   * 签名算法: base64(sha256(AppId + Timestamp + Path + AppSecret))
   */
  private static buildHeaders(path: string): Record<string, string> {
    const headers: Record<string, string> = {}
    if (DandanplayApi.appId.length === 0 || DandanplayApi.appSecret.length === 0) {
      return headers
    }
    const timestamp = Math.floor(Date.now() / 1000).toString()
    const raw = DandanplayApi.appId + timestamp + path + DandanplayApi.appSecret
    const signature = CryptoJS.SHA256(raw).toString(CryptoJS.enc.Base64)
    headers['X-AppId'] = DandanplayApi.appId
    headers['X-Timestamp'] = timestamp
    headers['X-Signature'] = signature
    return headers
  }
}
