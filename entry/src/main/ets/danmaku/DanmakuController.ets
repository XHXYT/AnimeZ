import { display } from '@kit.ArkUI'
import {
  BaseDanmaku,
  Callback,
  DANMAKU_STYLE_STROKEN,
  DanmakuContext,
  DanmakuTimer,
  DanmakuViewV2,
  RenderMode
} from '@ohos/danmakuflamemaster'
import { appSettings } from '../entryability/Settings'
import Logger from '../utils/Logger'
import { DanmakuLoadResult, DanmakuLoadStatus, DandanplayApi } from './DandanplayApi'
import { DandanplayParser } from './DandanplayParser'
import { DandanplayComment } from './DandanplayModels'

/** 弹幕基础字号（dp），与解析器保持一致 */
const BASE_DANMAKU_TEXT_SIZE: number = 25
/** 行高估算系数（字号 × 系数） */
const DANMAKU_LINE_HEIGHT_FACTOR: number = 1.7
/** 进度漂移校正阈值（ms） */
const DRIFT_CORRECTION_THRESHOLD: number = 1500
/** 两次漂移校正最小间隔（ms） */
const DRIFT_CORRECTION_INTERVAL: number = 2000

/**
 * 弹幕控制中枢：管理 DanmakuViewV2.Model 生命周期、弹幕数据加载与播放器状态同步
 */
export class DanmakuController {
  readonly model: DanmakuViewV2.Model = new DanmakuViewV2.Model()
  /** 最近一次成功加载的弹幕条数（0 表示未加载/无弹幕） */
  loadedCount: number = 0

  private context: DanmakuContext | null = null
  private comments: DandanplayComment[] = []
  private viewMounted: boolean = false
  private prepared: boolean = false
  /** 弹幕时钟是否处于播放态 */
  private playing: boolean = false
  /** 播放器最新进度（ms），供 prepare 完成后定位 */
  private playerPos: number = 0
  /** 异步加载序号，防止切集竞态 */
  private loadSeq: number = 0
  /** 上次漂移校正时间 */
  private lastSyncAt: number = 0

  constructor() {
    this.model.setMode(RenderMode.XCOMPONENT_TEXTURE)
  }

  /** 弹幕视图挂载完成（DanmakuLayer onAppear 调用） */
  onViewMounted(): void {
    this.viewMounted = true
    this.model.setCallback(this.buildCallback())
    if (this.comments.length > 0 && this.context !== null) {
      this.prepareInternal()
    }
  }

  /** 弹幕视图卸载（DanmakuLayer onDisappear 调用） */
  onViewUnmounted(): void {
    this.viewMounted = false
    this.prepared = false
  }

  /** 为指定剧集加载弹幕（切集/开关打开时调用） */
  async load(animeTitle: string, episodeTitle: string): Promise<DanmakuLoadResult> {
    this.loadSeq++
    const seq = this.loadSeq
    this.prepared = false
    this.playing = false
    const result = await DandanplayApi.loadComments(animeTitle, episodeTitle)
    if (seq !== this.loadSeq) {
      // 已被更新一次加载取代，丢弃本次结果
      return result
    }
    if (result.status === DanmakuLoadStatus.LOADED && result.comments.length > 0) {
      this.comments = result.comments
      this.loadedCount = result.comments.length
      this.context = this.buildContext()
      this.prepareInternal()
    } else {
      this.comments = []
      this.loadedCount = 0
    }
    return result
  }

  /** 播放器开始/恢复播放 */
  onPlay(positionMs: number): void {
    this.playing = true
    this.playerPos = positionMs
    if (this.prepared) {
      this.model.start(positionMs)
    }
  }

  /** 播放器暂停/停止 */
  onPause(): void {
    this.playing = false
    if (this.prepared) {
      this.model.pause()
    }
  }

  /** 播放器 seek（playing 表示 seek 后是否处于播放态） */
  onSeek(positionMs: number, playing: boolean): void {
    this.playerPos = positionMs
    this.playing = playing
    if (!this.prepared) {
      return
    }
    this.model.seekTo(positionMs)
    if (!playing) {
      this.model.pause()
    }
    this.lastSyncAt = Date.now()
  }

  /** 播放进度同步（随播放器 onProgressChange 周期调用），漂移超阈值时自动校正 */
  onProgress(positionMs: number): void {
    this.playerPos = positionMs
    if (!this.prepared || !this.playing) {
      return
    }
    const now = Date.now()
    if (now - this.lastSyncAt < DRIFT_CORRECTION_INTERVAL) {
      return
    }
    const drift = Math.abs(this.model.getCurrentTime() - positionMs)
    if (drift > DRIFT_CORRECTION_THRESHOLD) {
      this.model.seekTo(positionMs)
      this.lastSyncAt = now
    }
  }

  /** 弹幕样式设置变化（设置面板实时调用） */
  applyStyle(): void {
    if (this.context === null) {
      return
    }
    this.context.setDanmakuTransparency(appSettings.danmaku_opacity)
    this.context.setScaleTextSize(appSettings.danmaku_font_scale)
    this.context.setScrollSpeedFactor(appSettings.danmaku_speed)
    this.applyMaxLines(this.context)
  }

  /** 视口尺寸变化（DanmakuLayer onAreaChange 调用） */
  onViewportChanged(): void {
    if (this.context !== null) {
      this.applyMaxLines(this.context)
    }
  }

  release(): void {
    this.model.release()
  }

  /** 用当前数据重建 parser 并 prepare（每次 prepare 都需要新的 parser 实例） */
  private prepareInternal(): void {
    if (!this.viewMounted || this.comments.length === 0 || this.context === null) {
      return
    }
    this.prepared = false
    const parser = new DandanplayParser(this.comments)
    this.model.stop()
    this.model.prepare(parser, this.context)
  }

  /** 按当前设置构建弹幕上下文 */
  private buildContext(): DanmakuContext {
    const context = DanmakuContext.create()
      .setDanmakuStyle(DANMAKU_STYLE_STROKEN, 3)
      .setDuplicateMergingEnabled(false)
      .setDanmakuTransparency(appSettings.danmaku_opacity)
      .setScaleTextSize(appSettings.danmaku_font_scale)
      .setScrollSpeedFactor(appSettings.danmaku_speed)
    this.applyMaxLines(context)
    return context
  }

  /** 按显示区域限制滚动弹幕最大行数（顶部/底部固定弹幕不受限） */
  private applyMaxLines(context: DanmakuContext): void {
    const areaRatio = appSettings.danmaku_area
    if (areaRatio >= 1.0) {
      return
    }
    const heightPx = this.model.getHeight()
    if (heightPx <= 0) {
      return
    }
    const density = display.getDefaultDisplaySync().densityPixels
    const lineHeight = BASE_DANMAKU_TEXT_SIZE * density * appSettings.danmaku_font_scale * DANMAKU_LINE_HEIGHT_FACTOR
    const maxLines = Math.max(1, Math.floor(heightPx * areaRatio / lineHeight))
    const linesMap = new Map<number, number>()
    linesMap.set(BaseDanmaku.TYPE_SCROLL_RL, maxLines)
    linesMap.set(BaseDanmaku.TYPE_SCROLL_LR, maxLines)
    context.setMaximumLines(linesMap)
    Logger.d('tips', `DanmakuController 弹幕显示区域 ratio=${areaRatio} maxLines=${maxLines}`)
  }

  /** 弹幕 prepare 完成回调：按播放器当前状态启动或定帧 */
  private buildCallback(): Callback {
    const controller = this
    const callback: Callback = {
      prepared: (): void => {
        controller.prepared = true
        if (controller.playing) {
          controller.model.start(controller.playerPos)
        } else {
          controller.model.start(controller.playerPos)
          controller.model.pause()
        }
      },
      updateTimer: (_timer: DanmakuTimer): void => {
      },
      danmakuShown: (_danmaku: BaseDanmaku): void => {
      },
      drawingFinished: (): void => {
      }
    }
    return callback
  }
}
