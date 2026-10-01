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

/** 弹幕发送结果 */
export enum DanmakuSendOutcome {
  /** 已上屏，仅本机可见（未配置凭据或服务端发送失败） */
  LOCAL = 0,
  /** 已上屏并同步到弹弹play 开放弹幕网络 */
  SERVER = 1,
  /** 发送失败（未上屏） */
  FAILED = 2
}

/** 弹幕删除结果 */
export enum DanmakuRemoveOutcome {
  /** 仅本地移除（未同步服务端） */
  LOCAL_HIDE = 0,
  /** 已从弹弹play 弹幕库删除（自己发送的弹幕，服务端异步生效） */
  SERVER_DELETED = 1
}

/** 本会话发送的弹幕记录（供删除列表展示与删除） */
export class SentDanmakuRecord {
  timeMs: number = 0
  text: string = ''
  /** 服务端 cid（-1 表示仅本机） */
  cid: number = -1

  constructor(timeMs: number, text: string, cid: number) {
    this.timeMs = timeMs
    this.text = text
    this.cid = cid
  }
}

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
  scrollSpeedVpPerS: number = 86


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
  /** 当前弹幕对应的弹弹play 剧集 ID（发送/删除应用弹幕用，未加载为 -1） */
  private currentEpisodeId: number = -1
  /** 本会话发送的弹幕记录（删除列表数据源） */
  private sentRecords: SentDanmakuRecord[] = []

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
      this.currentEpisodeId = result.episodeId
      this.sentRecords = []
      // context 延迟到视图挂载后创建：DanmakuViewV2.aboutToAppear 才注册 uiContext，
      // 提前创建会导致 OhosDisplayer 密度初始化失败（density=0），字号/测量全部失效
      this.context = null
      this.prepareInternal()
    } else {
      this.comments = []
      this.loadedCount = 0
      this.currentEpisodeId = -1
      this.sentRecords = []
      this.context = null
    }
    return result
  }

  /** 手动指定剧集 ID 加载弹幕（切换弹幕功能，跳过标题匹配） */
  async loadByEpisodeId(episodeId: number, matchedTitle: string): Promise<DanmakuLoadResult> {
    this.loadSeq++
    const seq = this.loadSeq
    this.prepared = false
    this.playing = false
    const result = new DanmakuLoadResult()
    result.matchedTitle = matchedTitle
    result.episodeId = episodeId
    try {
      const comments = await DandanplayApi.loadCommentsByEpisodeId(episodeId)
      result.comments = comments
      if (seq !== this.loadSeq) {
        // 已被更新一次加载取代，丢弃本次结果
        result.status = comments.length > 0 ? DanmakuLoadStatus.LOADED : DanmakuLoadStatus.EMPTY
        return result
      }
      if (comments.length > 0) {
        result.status = DanmakuLoadStatus.LOADED
        this.comments = comments
        this.loadedCount = comments.length
        this.currentEpisodeId = episodeId
        this.sentRecords = []
        // context 延迟到视图挂载后创建：DanmakuViewV2.aboutToAppear 才注册 uiContext，
        // 提前创建会导致 OhosDisplayer 密度初始化失败（density=0），字号/测量全部失效
        this.context = null
        this.prepareInternal()
      } else {
        result.status = DanmakuLoadStatus.EMPTY
        this.comments = []
        this.loadedCount = 0
        this.currentEpisodeId = -1
        this.sentRecords = []
        this.context = null
      }
    } catch (e) {
      Logger.e('fail', `DanmakuCtrl 手动加载弹幕失败 episodeId=${episodeId}`, e)
      result.status = DanmakuLoadStatus.FAILED
      if (seq === this.loadSeq) {
        this.comments = []
        this.loadedCount = 0
        this.currentEpisodeId = -1
        this.sentRecords = []
        this.context = null
      }
    }
    return result
  }

  /**
   * 发送一条弹幕（当前弹幕时钟位置，右到左滚动，白色），即时上屏。
   * 写入源数据后 seek 回该时间仍会显示。
   * 配置了官方应用凭据且当前剧集已匹配时，同时 POST 到弹弹play 开放弹幕网络
   * （存入本应用私有弹幕库，拉取时与官方弹幕合并返回）；否则仅本机可见，下一次 load 后丢弃。
   */
  async sendDanmaku(text: string): Promise<DanmakuSendOutcome> {
    const trimmed = text.trim()
    const context = this.context
    if (trimmed.length === 0 || context === null || !this.prepared) {
      return DanmakuSendOutcome.FAILED
    }
    const posMs = Math.max(0, Math.round(this.model.getCurrentTime()))
    const nowSec = Math.floor(Date.now() / 1000)
    const comment: DandanplayComment = {
      cid: -1,
      p: `${(posMs / 1000).toFixed(3)},1,16777215,25,${nowSec},0,0,${nowSec}`,
      m: trimmed
    }
    this.comments.push(comment)
    this.loadedCount = this.comments.length
    // 即时上屏：与 parser 相同的完整创建路径（绑定工厂共享 Duration，速度因子生效），
    // flags 与 timer 由 DrawHandler.addDanmaku 自动绑定
    const item = context.mDanmakuFactory.createDanmakuByContext(BaseDanmaku.TYPE_SCROLL_RL, context)
    if (item === null) {
      return DanmakuSendOutcome.FAILED
    }
    item.setTime(posMs)
    item.text = trimmed
    item.textColor = 0xFFFFFF
    item.textSize = BASE_DANMAKU_TEXT_SIZE * context.mDisplayer.getScaledDensity()
    item.setVisibility(true)
    this.model.addDanmaku(item)
    const record = new SentDanmakuRecord(posMs, trimmed, -1)
    this.sentRecords.push(record)
    // 有官方凭据且当前剧集已匹配时同步到弹弹play（应用私有弹幕库）
    if (DandanplayApi.isAppCredentialConfigured() && this.currentEpisodeId > 0) {
      const cid = await DandanplayApi.sendComment(this.currentEpisodeId, posMs, 1, 0xFFFFFF, trimmed, 'AnimeZ')
      if (cid > 0) {
        comment.cid = cid
        record.cid = cid
        Logger.d('tips', `DanmakuCtrl 弹幕已同步服务端 pos=${posMs} cid=${cid} text="${trimmed}"`)
        return DanmakuSendOutcome.SERVER
      }
      Logger.d('tips', `DanmakuCtrl 服务端发送失败，仅本机可见 pos=${posMs} text="${trimmed}"`)
    } else {
      Logger.d('tips', `DanmakuCtrl 本地弹幕已发送 pos=${posMs} text="${trimmed}"`)
    }
    return DanmakuSendOutcome.LOCAL
  }

  /** 本会话发送的弹幕记录（最近在前，最多 50 条，供删除列表） */
  listSentDanmakus(): SentDanmakuRecord[] {
    const list: SentDanmakuRecord[] = []
    for (let i = this.sentRecords.length - 1; i >= 0 && list.length < 50; i--) {
      list.push(this.sentRecords[i])
    }
    return list
  }

  /**
   * 删除一条自己发送的弹幕：屏上实例立即隐藏（渲染每帧检查 isShown），
   * 从源数据与发送记录中移除；已同步服务端的弹幕同时从弹弹play 弹幕库删除（异步生效）。
   */
  removeSentDanmaku(record: SentDanmakuRecord): DanmakuRemoveOutcome {
    // 从发送记录中移除
    const next: SentDanmakuRecord[] = []
    for (const r of this.sentRecords) {
      if (r !== record) {
        next.push(r)
      }
    }
    this.sentRecords = next
    // 屏上实例立即隐藏
    const visible = this.snapshotVisibleDanmakus()
    for (const item of visible) {
      if (item.getTime() === record.timeMs && item.text === record.text) {
        item.setVisibility(false)
        this.model.invalidateDanmaku(item, false)
        this.model.forceRender()
        break
      }
    }
    // 从源数据移除，下次 prepare 起彻底消失
    for (let i = 0; i < this.comments.length; i++) {
      const parts = this.comments[i].p.split(',')
      if (parts.length > 0 && Math.round(parseFloat(parts[0]) * 1000) === record.timeMs
        && this.comments[i].m === record.text) {
        this.comments.splice(i, 1)
        this.loadedCount = this.comments.length
        break
      }
    }
    // 已同步服务端的弹幕同时从弹弹play 删除（异步生效，失败仅记日志）
    let outcome = DanmakuRemoveOutcome.LOCAL_HIDE
    if (record.cid > 0 && this.currentEpisodeId > 0) {
      outcome = DanmakuRemoveOutcome.SERVER_DELETED
      const episodeId = this.currentEpisodeId
      const cid = record.cid
      DandanplayApi.deleteComment(episodeId, cid).then((ok: boolean) => {
        if (!ok) {
          Logger.e('fail', `DanmakuCtrl 服务端删除弹幕失败 episodeId=${episodeId} cid=${cid}`)
        }
      })
    }
    Logger.d('tips', `DanmakuCtrl 弹幕已删除 time=${record.timeMs} server=${outcome === DanmakuRemoveOutcome.SERVER_DELETED} text="${record.text}"`)
    return outcome
  }

  /** 当前屏幕在显弹幕快照（未就绪返回空） */
  snapshotVisibleDanmakus(): BaseDanmaku[] {
    if (!this.prepared) {
      return []
    }
    return this.model.getCurrentVisibleDanmakus().getCollection()
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
    this.context.setDanmakuBold(appSettings.danmaku_bold)
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
    this.reapplyScrollSpeedWhenReady()
    const density = this.context.mDisplayer.getDensity()
    Logger.d('tips', `DanmakuController prepare已提交 comments=${this.comments.length} w=${this.model.getWidth()} h=${this.model.getHeight()} density=${density}`)
  }

  /**
   * model.prepare 是异步的：DrawHandler 线程稍后才执行 DrawTask.prepare，
   * 在那之前工厂会重置 Duration、且尚未按视口建立时长基数（real=3800 默认值）。
   * 同步补调 applyScrollSpeed 只能走回退公式，弹幕会按错误的短时长创建
   * （实测曾延迟 4s 才被偶然事件校准，期间速度比目标快近一倍）。
   * 这里轮询直至工厂视口就绪（CURRENT_DISP_WIDTH > 0）后重新校准。
   */
  private reapplyScrollSpeedWhenReady(): void {
    if (this.context === null) {
      return
    }
    const context = this.context
    const delays: number[] = [200, 500, 1000, 2000, 4000]
    for (const delay of delays) {
      setTimeout(() => {
        if (this.context !== context) {
          return
        }
        const factory = context.mDanmakuFactory
        if (factory.CURRENT_DISP_WIDTH > 0) {
          this.applyScrollSpeed(context)
        }
      }, delay)
    }
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
      .setDanmakuBold(appSettings.danmaku_bold)
    this.applyScrollSpeed(context)
    this.applyMaxLines(context)
    return context
  }

  /**
   * 弹幕滚动速度：设置值 danmaku_speed 是"速度倍率"（越大越快），
   * scrollSpeedVpPerS 是基准速度（vp/s），库的 setScrollSpeedFactor 是"时长倍率"（越大越慢）。
   *
   * 目标：像素速度恒定（vp/s × density），穿越时长 = 视口像素宽 / 像素速度，与宽度无关。
   * 实现直接读工厂的 REAL_DANMAKU_DURATION（库内基准，随视口变化、含 4000/9000ms 钳制），
   * factor = 目标穿越时长 / REAL，实际时长 = REAL × factor = 目标穿越——自校准，
   * 无需复算库的钳制公式（工厂内部视口宽与像素宽并非线性一致，实测竖屏 real 被 MIN 钳到 4000ms）。
   */
  private applyScrollSpeed(context: DanmakuContext): void {
    const speed = appSettings.danmaku_speed > 0 ? appSettings.danmaku_speed : 1.0
    const baseVpPerS = this.scrollSpeedVpPerS > 0 ? this.scrollSpeedVpPerS : 7.1
    // 滑条语义"越大越快"：目标速度 = 基准速度 × 滑条倍率
    const vpPerS = baseVpPerS * speed
    const density = display.getDefaultDisplaySync().densityPixels
    const width = this.model.getWidth()
    const targetCrossMs = width > 0 ? width * 1000 / (vpPerS * density) : 0
    const factory = context.mDanmakuFactory
    const real = factory.REAL_DANMAKU_DURATION
    let factor: number
    if (width > 0 && factory.CURRENT_DISP_WIDTH > 0 && real > 0) {
      // 工厂已按当前视口建立基准：直接反推 factor，弹幕实际时长即目标穿越时长
      factor = targetCrossMs / real
    } else {
      // prepare 前工厂尚未建立视口基准，按未钳制公式估算，prepare 后会重新校准
      factor = BILI_PLAYER_WIDTH * 1000 / (COMMON_DANMAKU_DURATION * vpPerS * density)
    }
    context.setScrollSpeedFactor(factor)
    // setScrollSpeedFactor 有同值守卫，且 prepare 之前工厂的 Duration 尚未创建时
    // updateDurationFactor 会空守卫提前返回——之后同值调用被外层守卫拦截，
    // 因子永远不会生效（渲染退回默认 1.0，约 7s 穿越）。
    // 这里强制重放绕过两层守卫：Duration 已创建则应用（setFactor 内部同值幂等），未创建则安全返回。
    factory.updateDurationFactor(factor)
    // R2LDanmaku 在 measure() 时缓存 stepPerMs = mDistance / duration.value，
    // 改 Duration 后必须 bump 测量标志触发重测，否则在屏弹幕仍按旧速度走完。
    // setScrollSpeedFactor 同值守卫拦截时会跳过 bump，这里手动补上。
    context.mGlobalFlagValues.updateMeasureFlag()
    context.mGlobalFlagValues.updateVisibleFlag()
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
