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
import {
  DanmakuColorFilter,
  DanmakuDuplicateFilter,
  DanmakuKeywordFilter,
  DanmakuTypeFilter,
  parseDanmakuBlockWords
} from './DanmakuBlockFilters'

/** 弹幕基础字号（dp），与解析器保持一致 */
const BASE_DANMAKU_TEXT_SIZE: number = 25
/** 行高估算系数（字号 × 系数） */
const DANMAKU_LINE_HEIGHT_FACTOR: number = 1.7
/** 进度漂移校正阈值（ms） */
const DRIFT_CORRECTION_THRESHOLD: number = 1500
/** 两次漂移校正最小间隔（ms） */
const DRIFT_CORRECTION_INTERVAL: number = 2000
/** 库的滚动弹幕基准时长（ms），对应 B 站原始分辨率 682px 宽 */
const COMMON_DANMAKU_DURATION: number = 3800
/** 库计算时长基数的参考播放器宽度（px） */
const BILI_PLAYER_WIDTH: number = 682
/** 库时长基数的下限/上限钳制（ms） */
const MIN_DANMAKU_DURATION: number = 4000
const MAX_DANMAKU_DURATION_HIGH_DENSITY: number = 9000

/**
 * 弹幕控制中枢：管理 DanmakuViewV2.Model 生命周期、弹幕数据加载与播放器状态同步
 */
export class DanmakuController {
  readonly model: DanmakuViewV2.Model = new DanmakuViewV2.Model()
  /** 最近一次成功加载的弹幕条数（0 表示未加载/无弹幕） */
  loadedCount: number = 0
  /**
   * 弹幕基准滚动速度（vp/s，速度滑条 100% 时的值，也是滑条最慢档）。
   * vp 为密度无关单位（与 25dp 基准字号同尺度），跨设备物理观感一致。
   * 36vp/s ≈ 120px/s：竖屏滚动时长约 11s、视觉穿越约 9s（库默认速度的 1.5 倍慢）
   */
  scrollSpeedVpPerS: number = 36


  private context: DanmakuContext | null = null
  private comments: DandanplayComment[] = []
  private viewMounted: boolean = false
  private prepared: boolean = false
  /** 自定义过滤器实例（注册到 context 后长期持有） */
  private typeFilter: DanmakuTypeFilter = new DanmakuTypeFilter()
  private colorFilter: DanmakuColorFilter = new DanmakuColorFilter()
  private duplicateFilter: DanmakuDuplicateFilter = new DanmakuDuplicateFilter()
  private keywordFilter: DanmakuKeywordFilter = new DanmakuKeywordFilter()
  /** 过滤器是否已注册到当前 context */
  private filtersRegistered: boolean = false
  /** 弹幕时钟是否处于播放态 */
  private playing: boolean = false
  /** 播放器最新进度（ms），供 prepare 完成后定位 */
  private playerPos: number = 0
  /** 异步加载序号，防止切集竞态 */
  private loadSeq: number = 0
  /** 上次漂移校正时间 */
  private lastSyncAt: number = 0
  /** 播放器进度对应的时间戳（Date.now()），供时钟外推 */
  private playerPosAt: number = 0
  /** 诊断：进度回调计数 */
  private progressCount: number = 0
  /** 诊断：已显示弹幕计数 */
  private shownCount: number = 0

  constructor() {
    this.model.setMode(RenderMode.XCOMPONENT_TEXTURE)
  }

  /** 弹幕视图挂载完成（DanmakuLayer onAppear 调用） */
  onViewMounted(): void {
    this.viewMounted = true
    this.model.setCallback(this.buildCallback())
    if (this.comments.length > 0) {
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
      // context 延迟到视图挂载后创建：DanmakuViewV2.aboutToAppear 才注册 uiContext，
      // 提前创建会导致 OhosDisplayer 密度初始化失败（density=0），字号/测量全部失效
      this.context = null
      this.prepareInternal()
    } else {
      this.comments = []
      this.loadedCount = 0
      this.context = null
    }
    return result
  }

  /** 播放器开始/恢复播放 */
  onPlay(positionMs: number): void {
    Logger.d('tips', `DanmakuCtrl onPlay pos=${positionMs} prepared=${this.prepared}`)
    this.playing = true
    this.playerPos = positionMs
    this.playerPosAt = Date.now()
    if (this.prepared) {
      this.model.start(positionMs)
    }
  }

  /** 播放器暂停/停止 */
  onPause(): void {
    Logger.d('tips', `DanmakuCtrl onPause prepared=${this.prepared}`)
    this.playing = false
    if (this.prepared) {
      this.model.pause()
    }
  }

  /** 播放器 seek（playing 表示 seek 后是否处于播放态） */
  onSeek(positionMs: number, playing: boolean): void {
    Logger.d('tips', `DanmakuCtrl onSeek pos=${positionMs} playing=${playing} prepared=${this.prepared}`)
    this.playerPos = positionMs
    this.playerPosAt = Date.now()
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
    this.playerPosAt = Date.now()
    this.progressCount++
    if (this.progressCount <= 6) {
      Logger.d('tips', `DanmakuCtrl onProgress#${this.progressCount} pos=${positionMs} cur=${this.model.getCurrentTime()} prepared=${this.prepared} playing=${this.playing}`)
    }
    if (!this.prepared || !this.playing) {
      return
    }
    const now = Date.now()
    if (now - this.lastSyncAt < DRIFT_CORRECTION_INTERVAL) {
      return
    }
    const drift = Math.abs(this.model.getCurrentTime() - positionMs)
    if (drift > DRIFT_CORRECTION_THRESHOLD) {
      Logger.d('tips', `DanmakuCtrl 漂移校正 drift=${drift} pos=${positionMs} cur=${this.model.getCurrentTime()}`)
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
    this.applyScrollSpeed(this.context)
    this.applyMaxLines(this.context)
    this.syncFilters()
  }

  /** 视口尺寸变化（DanmakuLayer onAreaChange 调用） */
  onViewportChanged(): void {
    if (this.context !== null) {
      // 宽度变化会改变库的时长基数，需按新宽度归一化速度因子（横竖屏穿越用时一致）
      this.applyScrollSpeed(this.context)
      this.applyMaxLines(this.context)
    }
  }

  release(): void {
    this.model.release()
  }

  /** 用当前数据重建 parser 并 prepare（每次 prepare 都需要新的 parser 实例） */
  private prepareInternal(): void {
    if (!this.viewMounted || this.comments.length === 0) {
      Logger.d('tips', `DanmakuController prepare跳过 mounted=${this.viewMounted} comments=${this.comments.length}`)
      return
    }
    if (this.context === null) {
      this.context = this.buildContext()
      this.filtersRegistered = false
      this.syncFilters()
    }
    this.prepared = false
    this.shownCount = 0
    const parser = new DandanplayParser(this.comments)
    this.model.stop()
    this.model.prepare(parser, this.context)
    // prepare 之后工厂 Duration 才存在，此时应用速度因子才会真正生效
    this.applyScrollSpeed(this.context)
    const density = this.context.mDisplayer.getDensity()
    Logger.d('tips', `DanmakuController prepare已提交 comments=${this.comments.length} w=${this.model.getWidth()} h=${this.model.getHeight()} density=${density}`)
  }

  /** 临时诊断：start 提交后探测弹幕时钟是否被意外重置 */
  private scheduleClockProbes(): void {
    const model = this.model
    const probes: number[] = [300, 800, 1500]
    for (const delay of probes) {
      setTimeout(() => {
        Logger.d('tips', `DanmakuCtrl 时钟探测 +${delay}ms cur=${model.getCurrentTime()} paused=${model.isPaused()}`)
      }, delay)
    }
  }

  /**
   * 时钟看门狗：prepared 后前 12 秒内周期校验弹幕时钟。
   * 防御库内部竞态把时钟重置回 0 基准（日志曾观察到 start(pos) 后时钟从 0 起跑）。
   */
  private scheduleClockWatchdog(): void {
    const controller = this
    let ticks = 0
    const watchdog = (): void => {
      ticks++
      if (!controller.prepared || !controller.playing) {
        return
      }
      const expected = controller.playerPos + (Date.now() - controller.playerPosAt)
      const cur = controller.model.getCurrentTime()
      if (Math.abs(cur - expected) > 3000) {
        Logger.d('tips', `DanmakuCtrl 时钟看门狗校正 cur=${cur} expected=${Math.round(expected)} pos=${controller.playerPos}`)
        controller.model.seekTo(Math.round(expected))
      }
      if (ticks < 6) {
        setTimeout(watchdog, 2000)
      }
    }
    setTimeout(watchdog, 2000)
  }

  /** 临时诊断：延迟输出渲染管线状态（时钟是否前进/是否存在可见弹幕） */
  private scheduleDiagnostics(): void {
    const model = this.model
    setTimeout(() => {
      Logger.d('tips', `DanmakuDiag +2s prepared=${model.isPrepared()} paused=${model.isPaused()} cur=${model.getCurrentTime()} ready=${model.isViewReady()} visible=${model.getCurrentVisibleDanmakus().size()} shown=${this.shownCount}`)
    }, 2000)
    setTimeout(() => {
      const cur = model.getCurrentTime()
      let expected = 0
      for (const c of this.comments) {
        const parts = c.p.split(',')
        const t = parseFloat(parts[0]) * 1000
        if (t >= cur - 8000 && t <= cur + 8000) {
          expected++
        }
      }
      const visible = model.getCurrentVisibleDanmakus()
      let sample = ''
      if (visible.size() > 0) {
        const first = visible.first()
        if (first !== null) {
          sample = ` 测量w=${Math.round(first.paintWidth)} h=${Math.round(first.paintHeight)}`
        }
      }
      Logger.d('tips', `DanmakuDiag +5s prepared=${model.isPrepared()} paused=${model.isPaused()} cur=${cur} visible=${visible.size()} shown=${this.shownCount} 理论应有=${expected}${sample}`)
    }, 5000)
  }

  /** 按当前设置构建弹幕上下文 */
  private buildContext(): DanmakuContext {
    const context = DanmakuContext.create()
      .setDanmakuStyle(DANMAKU_STYLE_STROKEN, 3)
      .setDuplicateMergingEnabled(false)
      .setDanmakuTransparency(appSettings.danmaku_opacity)
      .setScaleTextSize(appSettings.danmaku_font_scale)
    this.applyScrollSpeed(context)
    this.applyMaxLines(context)
    return context
  }

  /**
   * 弹幕滚动速度：设置值 danmaku_speed 是"速度倍率"（越大越快），
   * scrollSpeedVpPerS 是基准速度（vp/s），库的 setScrollSpeedFactor 是"时长倍率"（越大越慢）。
   *
   * 库的时长基数 initial = clamp(3800 × width / 682, 4000, 9000) ms。
   * 未钳制时 duration ∝ width，像素速度恒为 682/(3800×factor) px/ms——与宽度无关。
   * 由目标速度（vp/s × density → px/ms）反推 factor，使速度成为真正的瞬时量：
   * 不随视口宽度变化；再按 rawInitial/clampedInitial 补偿上下限钳制
   * （横屏宽屏触顶 9000ms 后时长被压缩、速度会变快），横竖屏速度保持一致。
   */
  private applyScrollSpeed(context: DanmakuContext): void {
    const speed = appSettings.danmaku_speed > 0 ? appSettings.danmaku_speed : 1.0
    const baseVpPerS = this.scrollSpeedVpPerS > 0 ? this.scrollSpeedVpPerS : 7.1
    // 滑条语义"越大越快"：目标速度 = 基准速度 × 滑条倍率
    const vpPerS = baseVpPerS * speed
    const density = display.getDefaultDisplaySync().densityPixels
    let factor = BILI_PLAYER_WIDTH * 1000 / (COMMON_DANMAKU_DURATION * vpPerS * density)
    const width = this.model.getWidth()
    if (width > 0) {
      const rawInitial = COMMON_DANMAKU_DURATION * width / BILI_PLAYER_WIDTH
      const clampedInitial = Math.min(MAX_DANMAKU_DURATION_HIGH_DENSITY,
        Math.max(MIN_DANMAKU_DURATION, rawInitial))
      factor = factor * rawInitial / clampedInitial
      const crossMs = clampedInitial * factor
      Logger.d('tips', `applyScrollSpeed 滑条=${speed} width=${Math.round(width)} factor=${factor.toFixed(2)} 穿越=${Math.round(crossMs / 100) / 10}s 速度=${vpPerS.toFixed(1)}vp/s(${(vpPerS * density).toFixed(0)}px/s)`)
    }
    context.setScrollSpeedFactor(factor)
    // setScrollSpeedFactor 有同值守卫，且 prepare 之前工厂的 Duration 尚未创建时
    // updateDurationFactor 会空守卫提前返回——之后同值调用被外层守卫拦截，
    // 因子永远不会生效（渲染退回默认 1.0，约 7s 穿越）。
    // 这里强制重放绕过两层守卫：Duration 已创建则应用（setFactor 内部同值幂等），未创建则安全返回。
    context.mDanmakuFactory.updateDurationFactor(factor)
  }

  /**
   * 同步弹幕屏蔽过滤器：注册/注销 + 更新过滤条件。
   * 库机制：registerFilter/unregisterFilter 自动 bump FILTER_RESET_FLAG 代际，
   * 已渲染弹幕的 mFilterParam 随代际变化自动失效，开关即时生效无残留。
   */
  private syncFilters(): void {
    if (this.context === null) {
      return
    }
    const ctx = this.context
    if (!this.filtersRegistered) {
      ctx.registerFilter(this.typeFilter)
      ctx.registerFilter(this.colorFilter)
      ctx.registerFilter(this.duplicateFilter)
      ctx.registerFilter(this.keywordFilter)
      this.filtersRegistered = true
    }
    this.typeFilter.setConfig(appSettings.danmaku_block_scroll, appSettings.danmaku_block_fixed)
    this.colorFilter.setConfig(appSettings.danmaku_block_color)
    this.duplicateFilter.setConfig(appSettings.danmaku_hide_duplicate)
    this.keywordFilter.setWords(parseDanmakuBlockWords(appSettings.danmaku_block_words))
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
        controller.progressCount = 0
        Logger.d('tips', `DanmakuController prepare完成 pos=${controller.playerPos} playing=${controller.playing} w=${controller.model.getWidth()} h=${controller.model.getHeight()}`)
        if (controller.playing) {
          controller.model.start(controller.playerPos)
        } else {
          controller.model.start(controller.playerPos)
          controller.model.pause()
        }
        Logger.d('tips', `DanmakuCtrl start已提交 cur=${controller.model.getCurrentTime()}`)
        controller.scheduleClockProbes()
        controller.scheduleClockWatchdog()
        controller.scheduleDiagnostics()
      },
      updateTimer: (_timer: DanmakuTimer): void => {
      },
      danmakuShown: (_danmaku: BaseDanmaku): void => {
        controller.shownCount++
        if (controller.shownCount === 1 || controller.shownCount === 20) {
          Logger.d('tips', `DanmakuController 弹幕已显示 ${controller.shownCount} 条 time=${controller.model.getCurrentTime()}`)
        }
      },
      drawingFinished: (): void => {
      }
    }
    return callback
  }
}
