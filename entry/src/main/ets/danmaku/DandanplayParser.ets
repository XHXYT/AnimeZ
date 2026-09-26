import { BaseDanmaku, BaseDanmakuParser, DanmakuContext, Danmakus, IDanmakus, ST_BY_TIME } from '@ohos/danmakuflamemaster'
import { DandanplayComment } from './DandanplayModels'

/** 弹幕基础字号（dp），B 站标准 */
const BASE_DANMAKU_TEXT_SIZE: number = 25

/**
 * 弹弹play 弹幕解析器：把评论数据解析为可渲染的弹幕集合
 */
export class DandanplayParser extends BaseDanmakuParser {
  private comments: DandanplayComment[] = []

  constructor(comments: DandanplayComment[]) {
    super()
    this.comments = comments
  }

  protected parse(): IDanmakus {
    const danmakus = new Danmakus({ sortType: ST_BY_TIME, duplicateMergingEnabled: false })
    for (const comment of this.comments) {
      const item = this.parseComment(comment)
      if (item !== null) {
        danmakus.addItem(item)
      }
    }
    this.comments = []
    return danmakus
  }

  /** 解析单条评论: p = "时间(秒),模式,颜色,来源" */
  private parseComment(comment: DandanplayComment): BaseDanmaku | null {
    const parts = comment.p.split(',')
    if (parts.length < 3) {
      return null
    }
    const timeSec = parseFloat(parts[0])
    const mode = parseInt(parts[1], 10)
    const color = parseInt(parts[2], 10)
    if (isNaN(timeSec) || isNaN(mode) || isNaN(color)) {
      return null
    }
    const type = DandanplayParser.mapType(mode)
    if (type < 0) {
      return null
    }
    const context = this.mContext as DanmakuContext
    if (context === null || context === undefined) {
      return null
    }
    const factory = context.mDanmakuFactory
    const item = factory.createDanmaku(type)
    if (item === null) {
      return null
    }
    item.setTime(Math.round(timeSec * 1000))
    item.text = comment.m
    item.textColor = color
    item.textSize = BASE_DANMAKU_TEXT_SIZE * this.mScaledDensity
    item.setVisibility(true)
    return item
  }

  /**
   * dandanplay 弹幕模式 -> 渲染类型
   * 1=右到左滚动 4=底部固定 5=顶部固定 6=左到右滚动
   * 2/3 为废弃的旧版滚动模式，按普通滚动处理；7/8 高级弹幕暂不支持
   */
  private static mapType(mode: number): number {
    if (mode === 1 || mode === 2 || mode === 3) {
      return BaseDanmaku.TYPE_SCROLL_RL
    }
    if (mode === 4) {
      return BaseDanmaku.TYPE_FIX_BOTTOM
    }
    if (mode === 5) {
      return BaseDanmaku.TYPE_FIX_TOP
    }
    if (mode === 6) {
      return BaseDanmaku.TYPE_SCROLL_LR
    }
    return -1
  }
}
