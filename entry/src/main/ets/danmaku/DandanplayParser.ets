import { BaseDanmaku, BaseDanmakuParser, DanmakuContext, DanmakuTimer, Danmakus, IDanmakus, ST_BY_TIME } from '@ohos/danmakuflamemaster'
import Logger from '../utils/Logger'
import { DandanplayComment } from './DandanplayModels'

/** 弹幕基础字号（dp），B 站标准；所有弹幕统一使用该字号，不随原始字号变化 */
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
    const total = this.comments.length
    let added = 0
    let rejected = 0
    let firstTime = -1
    let firstTextSize = -1
    let sampleLogged = 0
    for (const comment of this.comments) {
      if (sampleLogged < 3) {
        Logger.d('tips', `DandanplayParser 样本${sampleLogged} p=${comment.p}`)
        sampleLogged++
      }
      const item = this.parseComment(comment)
      if (item !== null) {
        if (danmakus.addItem(item)) {
          if (firstTime < 0) {
            firstTime = item.getTime()
            firstTextSize = item.textSize
          }
          added++
        } else {
          rejected++
        }
      } else {
        rejected++
      }
    }
    Logger.d('tips', `DandanplayParser 解析完成 输入=${total} 入集=${added} 丢弃=${rejected} size=${danmakus.size()} 首条时间=${firstTime} 首条字号=${firstTextSize} scaledDensity=${this.mScaledDensity} dispDensity=${this.mDispDensity}`)
    this.comments = []
    return danmakus
  }

  /** 解析单条评论: p = "时间(秒),模式,颜色,字号,发送时间戳,弹幕池,用户ID,弹幕ID"（dandanplay 官方格式，颜色在字号前） */
  private parseComment(comment: DandanplayComment): BaseDanmaku | null {
    const parts = comment.p.split(',')
    if (parts.length < 4) {
      return null
    }
    const timeSec = parseFloat(parts[0])
    const mode = parseInt(parts[1], 10)
    if (isNaN(timeSec) || isNaN(mode)) {
      return null
    }
    const v2 = parseFloat(parts[2])
    const v3 = parseFloat(parts[3])
    let color = v3
    if (!isNaN(v2) && v2 > 1000 && !isNaN(v3) && v3 >= 8 && v3 <= 144) {
      // dandanplay 官方顺序：颜色在前；若来源是 B 站 XML 顺序（字号在前，颜色是 0xFFFFFF 级大数）则保持默认
      color = v2
    }
    if (isNaN(color) || color < 0 || color > 0xFFFFFF) {
      color = 0xFFFFFF
    }
    const type = DandanplayParser.mapType(mode)
    if (type < 0) {
      return null
    }
    const context = this.mContext as DanmakuContext
    if (context === null || context === undefined) {
      return null
    }
    // 关键：显式传 context 走完整创建路径（createDanmakuByAll），弹幕才会绑定
    // 工厂按视口建立的共享 Duration，速度因子才能通过 updateDurationFactor 生效。
    // 零参 createDanmaku 依赖工厂的 sLastConfig/sLastDisp，prepare 阶段尚未就绪时
    // 返回 null 并走 createDefaultDanmaku 兜底——弹幕绑定独立的 Duration(3800)，
    // 速度控制完全失效（实测在屏弹幕 dur=3800ms，横屏 ~950px/s 比竖屏快）。
    const item = context.mDanmakuFactory.createDanmakuByContext(type, context)
    if (item === null) {
      return null
    }
    const timer = this.mTimer as DanmakuTimer
    if (timer !== null && timer !== undefined) {
      // 库不会为解析出的弹幕绑定时钟，未绑定时 isTimeOut()/isLate() 恒为 true，渲染循环会整体跳过
      item.setTimer(timer)
    }
    // 库只给实时弹幕(addDanmaku)绑定 flags，parser 产出的弹幕必须自行绑定，
    // 否则 isShown()/isMeasured() 中 flags != null 恒 false，永远绘制不出来（官方 demo 同款写法）
    item.flags = context.mGlobalFlagValues
    item.setTime(Math.round(timeSec * 1000))
    item.text = comment.m
    item.textColor = color
    // 统一字号：原始字号大小不一观感杂乱，全部使用基准字号（缩放仍由设置的字体系数控制）
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
