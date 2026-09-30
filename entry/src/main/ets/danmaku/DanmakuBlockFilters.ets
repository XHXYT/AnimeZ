import { BaseDanmaku, BaseDanmakuFilter, DanmakuContext, DanmakuTimer } from '@ohos/danmakuflamemaster'

/**
 * 自定义过滤位：库内置位（1~512）之外的空闲区间
 */
const FILTER_BIT_CUSTOM: number = 0x10000

/**
 * 弹幕类型常量（与库 BaseDanmaku 静态常量一致）
 */
const DANMAKU_TYPE_SCROLL_RL: number = 1
const DANMAKU_TYPE_SCROLL_LR: number = 6
const DANMAKU_TYPE_FIX_TOP: number = 5
const DANMAKU_TYPE_FIX_BOTTOM: number = 4

/**
 * 按类型屏蔽：滚动（1/6）或固定（4/5）
 */
export class DanmakuTypeFilter extends BaseDanmakuFilter<Object> {
  private mBlockScroll: boolean = false
  private mBlockFixed: boolean = false

  public setConfig(blockScroll: boolean, blockFixed: boolean): void {
    this.mBlockScroll = blockScroll
    this.mBlockFixed = blockFixed
  }

  public filter(danmaku: BaseDanmaku, index: number, totalsizeInScreen: number,
    timer: DanmakuTimer, fromCachingTask: boolean, config: DanmakuContext): boolean {
    if (danmaku == null) {
      return false
    }
    const type = danmaku.getType()
    let filtered = false
    if (this.mBlockScroll && (type == DANMAKU_TYPE_SCROLL_RL || type == DANMAKU_TYPE_SCROLL_LR)) {
      filtered = true
    }
    if (this.mBlockFixed && (type == DANMAKU_TYPE_FIX_TOP || type == DANMAKU_TYPE_FIX_BOTTOM)) {
      filtered = true
    }
    if (filtered) {
      danmaku.mFilterParam |= FILTER_BIT_CUSTOM
    }
    return filtered
  }

  public setData(data: Object | null): void {
  }

  public reset(): void {
    this.mBlockScroll = false
    this.mBlockFixed = false
  }
}

/**
 * 屏蔽彩色弹幕（非白色）
 */
export class DanmakuColorFilter extends BaseDanmakuFilter<Object> {
  private mBlockColor: boolean = false

  public setConfig(blockColor: boolean): void {
    this.mBlockColor = blockColor
  }

  public filter(danmaku: BaseDanmaku, index: number, totalsizeInScreen: number,
    timer: DanmakuTimer, fromCachingTask: boolean, config: DanmakuContext): boolean {
    if (danmaku == null) {
      return false
    }
    const filtered = this.mBlockColor && (danmaku.textColor & 0x00FFFFFF) != 0x00FFFFFF
    if (filtered) {
      danmaku.mFilterParam |= FILTER_BIT_CUSTOM
    }
    return filtered
  }

  public setData(data: Object | null): void {
  }

  public reset(): void {
    this.mBlockColor = false
  }
}

/**
 * 隐藏重复弹幕：相同文本在时间窗口内仅显示首条
 */
export class DanmakuDuplicateFilter extends BaseDanmakuFilter<Object> {
  private static readonly WINDOW_MS: number = 20000
  private mEnable: boolean = false
  private mLastSeen: Map<string, number> = new Map()

  public setConfig(enable: boolean): void {
    this.mEnable = enable
    if (!enable) {
      this.mLastSeen.clear()
    }
  }

  public filter(danmaku: BaseDanmaku, index: number, totalsizeInScreen: number,
    timer: DanmakuTimer, fromCachingTask: boolean, config: DanmakuContext): boolean {
    if (danmaku == null || !this.mEnable) {
      return false
    }
    const key = danmaku.text
    const now = timer.currMillisecond
    const last = this.mLastSeen.get(key)
    if (last != undefined && now - last < DanmakuDuplicateFilter.WINDOW_MS) {
      danmaku.mFilterParam |= FILTER_BIT_CUSTOM
      return true
    }
    this.mLastSeen.set(key, now)
    return false
  }

  public setData(data: Object | null): void {
  }

  public reset(): void {
    this.mLastSeen.clear()
  }
}

/**
 * 屏蔽词过滤：命中任一关键词即过滤（大小写不敏感）
 */
export class DanmakuKeywordFilter extends BaseDanmakuFilter<Object> {
  private mWords: string[] = []

  public setWords(words: string[]): void {
    this.mWords = words
  }

  public filter(danmaku: BaseDanmaku, index: number, totalsizeInScreen: number,
    timer: DanmakuTimer, fromCachingTask: boolean, config: DanmakuContext): boolean {
    if (danmaku == null || this.mWords.length == 0) {
      return false
    }
    const text = danmaku.text.toLowerCase()
    for (let i = 0; i < this.mWords.length; i++) {
      if (this.mWords[i].length > 0 && text.includes(this.mWords[i])) {
        danmaku.mFilterParam |= FILTER_BIT_CUSTOM
        return true
      }
    }
    return false
  }

  public setData(data: Object | null): void {
  }

  public reset(): void {
    this.mWords = []
  }
}

/**
 * 解析屏蔽词字符串（逗号/空格分隔）为小写数组
 */
export function parseDanmakuBlockWords(raw: string): string[] {
  const result: string[] = []
  if (!raw) {
    return result
  }
  const parts = raw.split(/[,，\s]+/)
  for (let i = 0; i < parts.length; i++) {
    const w = parts[i].trim().toLowerCase()
    if (w.length > 0) {
      result.push(w)
    }
  }
  return result
}
