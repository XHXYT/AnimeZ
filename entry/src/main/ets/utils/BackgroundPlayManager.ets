import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import Logger from './Logger';
import { appSettings } from '../entryability/Settings';
import { _AnimeState, AnimeState } from '../entryability/AnimeState';
import { PlayerStatus } from '../player/model/IPlayerManager';
import { CastManager } from '../player/CastManager';
import EpisodeInfo from '../entity/EpisodeInfo';

/**
 * 播控中心控制命令回调（由 PlayerManagerImpl 注册，规避管理器反向依赖播放器实现）
 */
export interface PlaybackCommandHandler {
  /** 继续播放 */
  play: () => void
  /** 暂停 */
  pause: () => void
  /** 跳转进度（毫秒） */
  seek: (positionMs: number) => void
  /** 下一集（无下一集时回调内自行忽略） */
  next: () => void
  /** 上一集（无上一集时回调内自行忽略） */
  previous: () => void
}

/**
 * 后台继续播放管理器单例（官方标准：AVSession + 长时任务，生命周期同步）：
 * - 开关开启且处于 PLAY 时申请 AUDIO_PLAYBACK 长时任务（进程保活），
 *   同时创建 video 类型 AVSession（元数据/控制命令/播放状态/activate），
 *   未接入 AVSession 时系统检测到后台播放会强制停止音频，长时任务无法生效；
 * - 暂停/停止/出错/播完或开关关闭时释放长时任务并销毁会话；
 * - PlayerManagerImpl.setStatus 每次状态变化回调 update()；
 * - 进度回调 updateProgress() 节流同步播控中心进度与元数据；
 * - 各设置开关 onChange 后调用 refresh() 按"最近一次状态"重估任务持有情况。
 */
class _BackgroundPlayManager {

  /** 长时任务是否在申请中（含异步在途） */
  private running: boolean = false

  /** 最近一次播放器状态（refresh() 重估用） */
  private lastStatus: PlayerStatus = PlayerStatus.IDLE

  /** 播控命令回调（PlayerManagerImpl 构造时注册） */
  private handler: PlaybackCommandHandler | null = null

  /** 后台播控 AVSession */
  private session: avSession.AVSession | null = null

  /** 会话是否已激活 */
  private sessionActive: boolean = false

  /** 最近一次写入会话的元数据 assetId（相同则跳过重复 setAVMetadata） */
  private lastMetadataAssetId: string = ''

  /** 最近一次同步到播控中心的进度(ms) */
  private lastSyncedPos: number = -1

  /** 最近一次同步到播控中心的时间戳 */
  private lastSyncedTime: number = 0

  /** 最近一次播放进度(ms) */
  private lastPositionMs: number = 0

  /** 最近一次媒体总时长(ms) */
  private lastDurationMs: number = 0

  /** 最近一次播放倍速 */
  private lastSpeed: number = 1.0

  /** 播放队列（供播控中心展示上/下集按钮可用性） */
  private queueEpisodes: EpisodeInfo[] = []

  /** 当前播放集在队列中的索引 */
  private queueIndex: number = 0

  /** 最近一次写入播控队列的列表指纹（相同则跳过重复 setAVQueueItems） */
  private lastQueueKey: string = ''

  /** 上一集命令是否已注册（未注册的命令播控中心按钮置灰） */
  private previousRegistered: boolean = false

  /** 下一集命令是否已注册（未注册的命令播控中心按钮置灰） */
  private nextRegistered: boolean = false

  /** 延迟销毁定时器 id（-1 表示无待执行销毁） */
  private pendingStopTask: number = -1

  /** 最近一次会话自愈重试时间戳（节流用） */
  private lastSessionRetryTime: number = 0

  /** 注册播控命令回调（PlayerManagerImpl 构造时调用） */
  attach(handler: PlaybackCommandHandler): void {
    this.handler = handler
  }

  /**
   * 是否处于后台播放保持状态：长时任务持有时窗口隐藏（退后台/锁屏）不自动暂停
   */
  isBackgroundPlaying(): boolean {
    return this.running
  }

  /**
   * 播放状态变化：开关开启且在播放则申请/保持音频长时任务与会话，否则延迟释放；
   * 切集会短暂经过 STOP/PREPARED，立即拆会话会与投播管理器并发抢占应用唯一会话
   * （抢输后进入"长时任务在但会话缺失"的僵死态，播控卡片落到无时长数据的
   * 投播会话上），故非播放状态延迟 5 秒销毁，期间回到 PLAY/PAUSE 自动取消
   */
  update(status: PlayerStatus): void {
    this.lastStatus = status
    // PLAY/PAUSE 均保持长时任务与会话（暂停时通知栏卡片保留，可继续播放），其余状态延迟释放
    if (appSettings.background_play
      && (status == PlayerStatus.PLAY || status == PlayerStatus.PAUSE)) {
      this.cancelPendingStop()
      this.start()
    } else {
      this.scheduleStop()
    }
    this.syncPlaybackState()
  }

  /**
   * 开关切换后重估：关闭时立即释放（用户预期开关即时生效），开启时按最近一次播放状态决定
   */
  refresh(): void {
    if (!appSettings.background_play) {
      this.cancelPendingStop()
      this.stop()
      return
    }
    this.update(this.lastStatus)
  }

  /**
   * 立即释放长时任务与会话（页面销毁等终态场景调用，不经延迟销毁）：
   * 播放器后端 stop/release 不发状态回调（mpv 仅补一个 PAUSE 事件），
   * 状态驱动感知不到页面销毁，播控卡片与长时任务会一直驻留
   */
  release(): void {
    this.cancelPendingStop()
    this.stop()
  }

  /** 延迟销毁：5 秒内回到 PLAY/PAUSE 则取消（切集解析可能耗时数秒），真正停止/出错时稍后清理 */
  private scheduleStop(): void {
    if (this.pendingStopTask >= 0) {
      return
    }
    this.pendingStopTask = setTimeout((): void => {
      this.pendingStopTask = -1
      if (this.lastStatus != PlayerStatus.PLAY && this.lastStatus != PlayerStatus.PAUSE) {
        this.stop()
      }
    }, 5000)
  }

  private cancelPendingStop(): void {
    if (this.pendingStopTask >= 0) {
      clearTimeout(this.pendingStopTask)
      this.pendingStopTask = -1
    }
  }

  /**
   * 进度回调（notifyTime/notifyCurrentTime 高频触发）：
   * 节流同步播控中心进度（进度跳变超 5 秒或距上次同步超 5 秒时刷新）
   */
  updateProgress(positionMs: number, durationMs: number, speed: number): void {
    this.lastPositionMs = positionMs
    this.lastDurationMs = durationMs > 0 ? durationMs : this.lastDurationMs
    this.lastSpeed = speed > 0 ? speed : this.lastSpeed
    if (!this.running || this.session == null) {
      return
    }
    const now = Date.now()
    const posJumped = this.lastSyncedPos < 0 || Math.abs(positionMs - this.lastSyncedPos) > 5000
    const timeElapsed = now - this.lastSyncedTime > 5000
    if (posJumped || timeElapsed) {
      this.syncPlaybackState()
      this.refreshMetadata()
    }
  }

  /**
   * 播放队列变化（playEpisodeList/selectEpisode 时由 PlayerManagerImpl 推送）：
   * 写入播控队列与当前集索引，通知栏/播控中心据此正确展示上/下集按钮
   */
  updateQueue(episodes: EpisodeInfo[], index: number): void {
    this.queueEpisodes = episodes
    this.queueIndex = index
    const session = this.session
    if (!this.running || session == null) {
      return
    }
    this.applyQueue()
    this.refreshMetadata()
    this.syncPlaybackState()
    this.syncEpisodeCommands(session)
  }

  private async start(): Promise<void> {
    if (this.running) {
      // 僵死自愈：长时任务在但会话创建失败过（接管重试撞上异步销毁），节流补建会话
      await this.healSession()
      return
    }
    const context: common.UIAbilityContext | null = _AnimeState.Context
    if (context == null) {
      return
    }
    this.running = true
    // 1. 创建并接入 AVSession（官方要求：未接入时系统会强停后台音频）；
    //    创建失败不阻断长时任务申请（会话被占用等场景下任务保活仍生效）
    try {
      await this.createSession(context)
    } catch (err) {
      const e = err as BusinessError
      Logger.e('fail', `BackgroundPlay createSession code=${e.code} msg=${e.message}`)
    }
    // 2. 申请音频长时任务（进程保活，失败则整体回退）
    try {
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: context.abilityInfo.bundleName,
          abilityName: context.abilityInfo.name
        }],
        operationType: wantAgent.OperationType.START_ABILITIES,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      }
      // 注意：无 callback 的 getWantAgent 返回 Promise<WantAgent>，必须 await
      const agent = await wantAgent.getWantAgent(wantAgentInfo)
      await backgroundTaskManager.startBackgroundRunning(context,
        backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, agent)
      Logger.i('BackgroundPlay', '后台播放长时任务已申请')
      this.lastSyncedPos = -1
      this.syncPlaybackState()
    } catch (err) {
      const e = err as BusinessError
      this.running = false
      Logger.e('fail', `startBackgroundRunning code=${e.code} msg=${e.message}`)
    }
  }

  /**
   * 僵死自愈：长时任务持有时会话缺失则补建（5 秒节流防高频重试），
   * 补建走接管流程（释放占用的投播会话后重试）
   */
  private async healSession(): Promise<void> {
    if (this.session != null) {
      return
    }
    const context: common.UIAbilityContext | null = _AnimeState.Context
    if (context == null) {
      return
    }
    const now = Date.now()
    if (now - this.lastSessionRetryTime < 5000) {
      return
    }
    this.lastSessionRetryTime = now
    Logger.i('BackgroundPlay', '会话缺失，自愈补建中')
    try {
      await this.createSession(context)
    } catch (err) {
      const e = err as BusinessError
      Logger.e('fail', `会话自愈补建 code=${e.code} msg=${e.message}`)
    }
  }

  private async stop(): Promise<void> {
    if (!this.running) {
      return
    }
    this.running = false
    const context: common.UIAbilityContext | null = _AnimeState.Context
    this.destroySession()
    if (context == null) {
      return
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(context)
      Logger.i('BackgroundPlay', '后台播放长时任务已释放')
    } catch (err) {
      const e = err as BusinessError
      Logger.e('fail', `stopBackgroundRunning code=${e.code} msg=${e.message}`)
    }
  }

  /** 创建 AVSession：元数据 → 控制命令注册 → activate（官方流程顺序） */
  private async createSession(context: common.UIAbilityContext): Promise<void> {
    if (this.session != null) {
      return
    }
    const session = await this.createSessionWithTakeover(context)
    if (session == null) {
      Logger.e('fail', 'BackgroundPlay AVSession 创建失败，长时任务继续但播控中心不可用')
      return
    }
    this.session = session
    this.sessionActive = false
    this.lastMetadataAssetId = ''
    session.on('play', () => {
      Logger.i('BackgroundPlay', '播控中心：继续播放')
      if (this.handler != null) {
        this.handler.play()
      }
    })
    session.on('pause', () => {
      Logger.i('BackgroundPlay', '播控中心：暂停')
      if (this.handler != null) {
        this.handler.pause()
      }
    })
    session.on('seek', (time: number) => {
      Logger.i('BackgroundPlay', `播控中心：跳转 ${time}ms`)
      if (this.handler != null) {
        this.handler.seek(time)
      }
    })
    await this.refreshMetadata()
    if (!this.sessionActive) {
      await session.activate()
      this.sessionActive = true
      Logger.i('BackgroundPlay', 'AVSession 已激活')
    }
    await this.applyQueue()
    // 上一集/下一集按队列位置动态注册（第一集置灰上一集、最后一集置灰下一集）
    this.syncEpisodeCommands(session)
  }

  /** 按当前队列位置动态注册/注销上一集与下一集命令（未注册的命令播控中心按钮置灰） */
  private syncEpisodeCommands(session: avSession.AVSession): void {
    const hasPrevious = this.queueIndex > 0
    const hasNext = this.queueIndex < this.queueEpisodes.length - 1
    if (hasPrevious && !this.previousRegistered) {
      session.on('playPrevious', () => {
        Logger.i('BackgroundPlay', '播控中心：上一集')
        if (this.handler != null) {
          this.handler.previous()
        }
      })
      this.previousRegistered = true
    } else if (!hasPrevious && this.previousRegistered) {
      session.off('playPrevious')
      this.previousRegistered = false
    }
    if (hasNext && !this.nextRegistered) {
      session.on('playNext', () => {
        Logger.i('BackgroundPlay', '播控中心：下一集')
        if (this.handler != null) {
          this.handler.next()
        }
      })
      this.nextRegistered = true
    } else if (!hasNext && this.nextRegistered) {
      session.off('playNext')
      this.nextRegistered = false
    }
  }

  /**
   * 创建后台播控 AVSession；应用唯一会话被投播管理器预创建占用时（6600101），
   * 先请求释放投播会话再重试一次，仍失败返回 null 由调用方降级处理
   */
  private async createSessionWithTakeover(context: common.UIAbilityContext): Promise<avSession.AVSession | null> {
    try {
      return await avSession.createAVSession(context, 'AnimeZBackgroundPlay', 'video')
    } catch (err) {
      const e = err as BusinessError
      if (e.code != 6600101) {
        Logger.e('fail', `createAVSession code=${e.code} msg=${e.message}`)
        return null
      }
      const released: boolean = await CastManager.releaseActiveSession()
      Logger.i('BackgroundPlay', `投播预创建会话占用，已请求释放=${released}`)
      // 释放是异步的，立即重试会再次 6600101；间隔重试等待服务端完成销毁
      for (let attempt = 0; attempt < 3; attempt++) {
        await _BackgroundPlayManager.sleep(500 * (attempt + 1))
        const session = await avSession.createAVSession(context, 'AnimeZBackgroundPlay', 'video')
          .catch((retryErr: BusinessError): avSession.AVSession | null => {
            Logger.e('fail', `createAVSession retry${attempt} code=${retryErr.code} msg=${retryErr.message}`)
            return null
          })
        if (session != null) {
          return session
        }
      }
      return null
    }
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: (value: void) => void) => {
      setTimeout((): void => {
        resolve()
      }, ms)
    })
  }

  /** 销毁 AVSession：与长时任务生命周期保持一致 */
  private async destroySession(): Promise<void> {
    const session = this.session
    this.session = null
    this.sessionActive = false
    this.lastMetadataAssetId = ''
    this.lastQueueKey = ''
    this.lastSyncedPos = -1
    this.previousRegistered = false
    this.nextRegistered = false
    if (session == null) {
      return
    }
    try {
      session.off('play')
      session.off('pause')
      session.off('seek')
      session.off('playNext')
      session.off('playPrevious')
      await session.destroy()
      Logger.i('BackgroundPlay', 'AVSession 已销毁')
    } catch (err) {
      const e = err as BusinessError
      Logger.e('fail', `session destroy code=${e.code} msg=${e.message}`)
    }
  }

  /**
   * 写入播控队列（全量剧集，itemId = 索引+1），列表未变化时跳过；
   * 当前集通过 AVPlaybackState.activeItemId 持续同步
   */
  private async applyQueue(): Promise<void> {
    const session = this.session
    if (session == null || !this.running || this.queueEpisodes.length == 0) {
      return
    }
    const queueKey = `${this.queueEpisodes.length}-${this.queueEpisodes[0].link}`
    if (queueKey == this.lastQueueKey) {
      return
    }
    const items: avSession.AVQueueItem[] =
      this.queueEpisodes.map((episode: EpisodeInfo, idx: number): avSession.AVQueueItem => {
        const episodeTitle: string = episode.desc != '' ? episode.desc : episode.title
        const description: avSession.AVMediaDescription = {
          assetId: `bg-${idx}-${episode.link}`,
          title: AnimeState.playingTitle != '' ? `${AnimeState.playingTitle} ${episodeTitle}` : episodeTitle,
          mediaType: 'VIDEO',
          duration: this.lastDurationMs,
          albumCoverUri: AnimeState.playingCoverUrl,
          albumTitle: AnimeState.playingTitle,
          appName: 'AnimeZ'
        }
        return { itemId: idx + 1, description: description }
      })
    await session.setAVQueueItems(items).then((): void => {
      this.lastQueueKey = queueKey
    }).catch((err: BusinessError) => {
      Logger.e('fail', `setAVQueueItems code=${err.code} msg=${err.message}`)
    })
  }

  /** 刷新播控中心元数据（标题/封面/时长），assetId 未变化时跳过 */
  private async refreshMetadata(): Promise<void> {
    const session = this.session
    if (session == null || !this.running) {
      return
    }
    let episode: EpisodeInfo | null = null
    if (this.queueIndex >= 0 && this.queueIndex < this.queueEpisodes.length) {
      episode = this.queueEpisodes[this.queueIndex]
    }
    const episodeTitle: string = episode != null ? (episode.desc != '' ? episode.desc : episode.title) : ''
    const assetId: string = episode != null
      ? `${AnimeState.playingTitle}-${this.queueIndex}-${episode.link}-${this.lastDurationMs}`
      : `${AnimeState.playingTitle}-${this.lastDurationMs}`
    if (assetId == this.lastMetadataAssetId) {
      return
    }
    const title: string = episodeTitle != '' && AnimeState.playingTitle != ''
      ? `${AnimeState.playingTitle} ${episodeTitle}`
      : (AnimeState.playingTitle != '' ? AnimeState.playingTitle : episodeTitle)
    const metadata: avSession.AVMetadata = {
      assetId: assetId,
      title: title,
      subtitle: episodeTitle,
      mediaImage: AnimeState.playingCoverUrl,
      duration: this.lastDurationMs
    }
    await session.setAVMetadata(metadata).then((): void => {
      this.lastMetadataAssetId = assetId
    }).catch((err: BusinessError) => {
      Logger.e('fail', `setAVMetadata code=${err.code} msg=${err.message}`)
    })
  }

  /** 同步播放状态到播控中心（任务持有时才写） */
  private async syncPlaybackState(): Promise<void> {
    const session = this.session
    if (session == null || !this.running) {
      return
    }
    let state: avSession.PlaybackState = avSession.PlaybackState.PLAYBACK_STATE_PAUSE
    if (this.lastStatus == PlayerStatus.PLAY) {
      state = avSession.PlaybackState.PLAYBACK_STATE_PLAY
    } else if (this.lastStatus == PlayerStatus.STOP || this.lastStatus == PlayerStatus.DONE
      || this.lastStatus == PlayerStatus.ERROR) {
      state = avSession.PlaybackState.PLAYBACK_STATE_STOP
    }
    this.lastSyncedPos = this.lastPositionMs
    this.lastSyncedTime = Date.now()
    const playbackState: avSession.AVPlaybackState = {
      state: state,
      speed: this.lastSpeed,
      position: { elapsedTime: this.lastPositionMs, updateTime: Date.now() },
      duration: this.lastDurationMs,
      activeItemId: this.queueIndex + 1
    }
    await session.setAVPlaybackState(playbackState).catch((err: BusinessError) => {
      Logger.e('fail', `setAVPlaybackState code=${err.code} msg=${err.message}`)
    })
  }
}

export const BackgroundPlayManager = new _BackgroundPlayManager()
