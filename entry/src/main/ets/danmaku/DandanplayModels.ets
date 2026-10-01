/**
 * 弹弹play 开放弹幕 API 数据模型
 * 文档: https://api.dandanplay.net/swagger
 */

/** 剧集搜索响应（兼容官方 result 包裹层与中转接口顶层平铺两种结构） */
export interface DandanplaySearchResponse {
  errorCode: number
  success: boolean
  errorMessage: string
  /** 官方结构：数据包裹在 result 中 */
  result: DandanplaySearchResult | null
  /** 中转结构：数据直接在顶层 */
  animes: DandanplayAnime[] | null
}

/** 弹幕拉取响应（兼容官方 result 包裹层与中转接口顶层平铺两种结构） */
export interface DandanplayCommentResponse {
  errorCode: number
  success: boolean
  errorMessage: string
  /** 官方结构：数据包裹在 result 中 */
  result: DandanplayCommentResult | null
  /** 中转结构：数据直接在顶层 */
  count: number
  comments: DandanplayComment[] | null
}

/** 剧集信息 */
export interface DandanplayEpisode {
  episodeId: number
  episodeTitle: string
}

/** 动画（含剧集列表） */
export interface DandanplayAnime {
  animeId: number
  animeTitle: string
  type: string
  episodes: DandanplayEpisode[]
}

/** 剧集搜索结果 */
export interface DandanplaySearchResult {
  hasMore: boolean
  animes: DandanplayAnime[]
}

/** 单条弹幕评论 */
export interface DandanplayComment {
  cid: number
  /** 格式: "出现时间(秒),弹幕模式,颜色(十进制RGB),来源" */
  p: string
  /** 弹幕文本 */
  m: string
}

/** 弹幕拉取结果 */
export interface DandanplayCommentResult {
  count: number
  comments: DandanplayComment[]
}

/** 剧集匹配结果 */
export interface DandanplayEpisodeMatch {
  episodeId: number
  matchedTitle: string
}

/** 应用弹幕发送请求体（POST /api/v2/comment/{episodeId}/app） */
export interface DandanplaySendBody {
  /** 出现时间（毫秒） */
  time: number
  /** 弹幕模式：1=滚动 4=底部 5=顶部 */
  mode: number
  /** 颜色（十进制 RGB） */
  color: number
  /** 弹幕文本 */
  comment: string
  /** 发送者用户名（应用自定义标识） */
  userName: string
}

/** 应用弹幕发送响应 */
export interface DandanplaySendResponse {
  errorCode: number
  success: boolean
  errorMessage: string
  errorDetail: string
  /** 发送成功的弹幕编号（删除时使用） */
  cid: number
}

/** 弹幕删除响应（DELETE /api/v2/comment/app/{episodeId}/{cid}） */
export interface DandanplayDeleteResponse {
  errorCode: number
  success: boolean
  errorMessage: string
  errorDetail: string
}
