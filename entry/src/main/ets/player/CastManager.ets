import { avSession } from '@kit.AVSessionKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common, wantAgent } from '@kit.AbilityKit';
import EpisodeInfo from '../entity/EpisodeInfo';
import Logger from '../utils/Logger';

/** 投播/播控事件回调（由 VideoPlayerController 注册） */
export interface CastListener {

  onCastConnected: (deviceName: string) => void

  onCastDisconnected: () => void

  onCastStateChanged: (isPlaying: boolean) => void

  onCastProgressChange: (duration: number, position: number) => void

  onCastEndOfStream: () => void

  /** 播控中心"播放"命令 */
  onControlPlay: () => void

  /** 播控中心"暂停"命令 */
  onControlPause: () => void

  /** 播控中心进度条拖动（position 单位 ms） */
  onControlSeek: (position: number) => void

  /** 播控中心"下一集" */
  onControlNext: () => void

  /** 播控中心"上一集" */
  onControlPrevious: () => void

}

/**
 * 系统投播管理器（AVSession Kit）
 * 封装 AVSession 生命周期、投播元数据维护（配合 AVCastPicker 组件的设备选择面板）、
 * 远端资源推送（prepare/start）与远端播放控制（sendControlCommand）。
 */
export class CastManager {

  private session: avSession.AVSession | null = null
  private castController: avSession.AVCastController | null = null
  private listener: CastListener | null = null
  private context: common.UIAbilityContext | null = null
  private episodeList: EpisodeInfo[] = []
  private episodeIndex: number = 0
  private deviceName: string = ''
  /** 发起投播时希望远端从该位置开播(ms) */
  private pendingStartPos: number = 0
  /** 远端最近一次进度(ms)，设备切换时作为续播位置 */
  private lastCastPos: number = 0
  /** 是否已声明支持投播（requireAbilityList 只需设置一次） */
  private extrasSet: boolean = false
  /** 会话是否已激活（激活必须在元数据与控制命令注册完成之后执行） */
  private sessionActive: boolean = false
  /** 最近一次写入会话的元数据 assetId（相同则跳过重复 setAVMetadata） */
  private lastMetadataAssetId: string = ''
  /** 最近一次写入会话的元数据时长(ms) */
  private lastMetadataDuration: number = 0
  /** 投播元数据展示用：媒体标题（如番剧名） */
  private mediaTitle: string = ''
  /** 投播元数据展示用：封面URL */
  private mediaCoverUrl: string = ''
  /** 投播元数据展示用：媒体时长(ms) */
  private mediaDuration: number = 0
  /** 最近一次写入播控队列的列表指纹（相同则跳过重复 setAVQueueItems） */
  private lastQueueKey: string = ''
  /** 最近一次同步到播控中心的进度(ms) */
  private lastSyncedPos: number = -1
  /** 最近一次同步到播控中心的时间戳 */
  private lastSyncedTime: number = 0

  setListener(listener: CastListener): void {
    this.listener = listener
  }

  isCasting(): boolean {
    return this.castController != null
  }

  getDeviceName(): string {
    return this.deviceName
  }

  /** 更新剧集列表与当前集索引（投播中切集用） */
  updateEpisodes(episodeList: EpisodeInfo[], episodeIndex: number): void {
    this.episodeList = episodeList
    this.episodeIndex = episodeIndex
  }

  /**
   * 创建/复用 AVSession 并刷新投播元数据
   * AVCastPicker 组件被点击时要求对应类型的 AVSession 已存在，
   * 因此需在 aboutToAppear、切集、播放开始时调用本方法
   * @param duration 本端当前媒体时长(ms)，未知时传 0
   * @param mediaTitle 媒体标题（如番剧名），用于投播面板展示
   * @param coverUrl 媒体封面URL，用于投播面板展示
   */
  async prepare(context: common.UIAbilityContext, episodeList: EpisodeInfo[], episodeIndex: number,
    duration: number, mediaTitle: string, coverUrl: string): Promise<void> {
    this.context = context
    this.episodeList = episodeList
    this.episodeIndex = episodeIndex
    this.mediaTitle = mediaTitle
    this.mediaCoverUrl = coverUrl
    if (duration > 0) {
      this.mediaDuration = duration
    }
    const session = await this.ensureSession()
    if (session == null) {
      return
    }
    if (!this.extrasSet) {
      const extras: Record<string, Object> = { 'requireAbilityList': ['url-cast'] }
      await session.setExtras(extras).then((): void => {
        this.extrasSet = true
      }).catch((err: BusinessError) => {
        Logger.e('fail', `setExtras code=${err.code} msg=${err.message}`)
      })
    }
    if (episodeIndex >= 0 && episodeIndex < episodeList.length) {
      const episode = episodeList[episodeIndex]
      const assetId = this.buildAssetId(episodeIndex, episode.link)
      // assetId 未变且时长已写入过则跳过；首次拿到有效时长时补写一次
      if (assetId != this.lastMetadataAssetId || (this.lastMetadataDuration <= 0 && duration > 0)) {
        const metadata: avSession.AVMetadata = {
          assetId: assetId,
          title: this.buildDisplayTitle(episode, false),
          subtitle: this.buildEpisodeTitle(episode),
          mediaImage: this.mediaCoverUrl,
          duration: duration,
          filter: avSession.ProtocolType.TYPE_CAST_PLUS_STREAM | avSession.ProtocolType.TYPE_DLNA
        }
        await session.setAVMetadata(metadata).then((): void => {
          this.lastMetadataAssetId = assetId
          this.lastMetadataDuration = duration
        }).catch((err: BusinessError) => {
          Logger.e('fail', `setAVMetadata code=${err.code} msg=${err.message}`)
        })
      }
    }
    // 播控中心播放队列：写入全量剧集，供播控中心展示上一集/下一集按钮
    const queueKey = `${episodeList.length}-${episodeList.length > 0 ? episodeList[0].link : ''}`
    if (episodeList.length > 1 && queueKey != this.lastQueueKey) {
      const items: avSession.AVQueueItem[] =
        episodeList.map((episode: EpisodeInfo, idx: number): avSession.AVQueueItem => {
          const description: avSession.AVMediaDescription = {
            assetId: this.buildAssetId(idx, episode.link),
            title: this.buildDisplayTitle(episode, true),
            subtitle: this.buildEpisodeTitle(episode),
            mediaType: 'VIDEO',
            duration: this.mediaDuration,
            albumCoverUri: this.mediaCoverUrl,
            albumTitle: this.mediaTitle,
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
    // 激活须在元数据与控制命令注册完成之后执行，否则播控中心可能不展示卡片
    await this.activateSession()
  }

  /** 激活会话（仅首次生效）；须在 setAVMetadata/setAVQueueItems/控制命令注册完成后调用 */
  private async activateSession(): Promise<void> {
    const session = this.session
    if (session == null || this.sessionActive) {
      return
    }
    await session.activate().then((): void => {
      this.sessionActive = true
      Logger.e('tips', 'AVSession activated after metadata ready')
    }).catch((err: BusinessError) => {
      Logger.e('fail', `activate code=${err.code} msg=${err.message}`)
    })
    if (this.sessionActive) {
      // 激活后立即写入一次初始状态，确保播控中心卡片有可展示的播放状态
      await this.setPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE, this.pendingStartPos, 1.0)
    }
  }

  /** 本端播放进度变化时刷新远端起播位置，并节流同步播控中心进度（seek 后自动纠正） */
  updateProgress(position: number, speed: number): void {
    this.pendingStartPos = position
    if (this.session == null || this.castController != null) {
      return
    }
    const now = Date.now()
    // 进度跳变超过 5 秒（seek/切集）或距上次同步超过 30 秒时刷新播控中心进度
    const posJumped = this.lastSyncedPos < 0 || Math.abs(position - this.lastSyncedPos) > 5000
    const timeElapsed = now - this.lastSyncedTime > 30000
    if (posJumped || timeElapsed) {
      this.setPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PLAY, position, speed)
    }
  }

  /** 同步本端播放状态到系统播控中心 */
  async updatePlaybackState(playing: boolean, position: number, speed: number): Promise<void> {
    if (this.castController != null) {
      // 投播中播控中心状态由远端回传驱动，不写本端状态
      return
    }
    await this.setPlaybackState(
      playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
      position, speed)
  }

  private async setPlaybackState(state: avSession.PlaybackState, position: number, speed: number): Promise<void> {
    const session = this.session
    if (session == null) {
      return
    }
    this.lastSyncedPos = position
    this.lastSyncedTime = Date.now()
    const playbackState: avSession.AVPlaybackState = {
      state: state,
      speed: speed,
      position: { elapsedTime: position, updateTime: Date.now() },
      duration: this.mediaDuration,
      activeItemId: this.episodeIndex + 1
    }
    await session.setAVPlaybackState(playbackState).catch((err: BusinessError) => {
      Logger.e('fail', `setAVPlaybackState code=${err.code} msg=${err.message}`)
    })
  }

  /**
   * 向远端推送并播放指定剧集（投播中切集无需断开连接）
   * @returns 是否成功推送到远端
   */
  async castEpisode(episodeIndex: number, startPos: number): Promise<boolean> {
    const controller = this.castController
    if (controller == null) {
      return false
    }
    if (episodeIndex < 0 || episodeIndex >= this.episodeList.length) {
      return false
    }
    const episode = this.episodeList[episodeIndex]
    const url = episode.videoUrl
    if (!url) {
      Logger.e('fail', 'castEpisode videoUrl 为空，无法投播')
      return false
    }
    this.episodeIndex = episodeIndex
    this.lastCastPos = startPos
    const description: avSession.AVMediaDescription = {
      assetId: this.buildAssetId(episodeIndex, episode.link),
      title: this.buildDisplayTitle(episode, true),
      subtitle: 'video',
      mediaUri: url,
      mediaType: 'VIDEO',
      startPosition: startPos,
      duration: this.mediaDuration,
      albumCoverUri: this.mediaCoverUrl,
      albumTitle: this.mediaTitle,
      appName: 'AnimeZ'
    }
    const item: avSession.AVQueueItem = {
      itemId: episodeIndex,
      description: description
    }
    const prepared = await controller.prepare(item).then((): boolean => {
      return true
    }).catch((err: BusinessError): boolean => {
      Logger.e('fail', `cast prepare code=${err.code} msg=${err.message}`)
      return false
    })
    if (!prepared) {
      return false
    }
    await controller.start(item).catch((err: BusinessError) => {
      Logger.e('fail', `cast start code=${err.code} msg=${err.message}`)
    })
    return true
  }

  async play(): Promise<void> {
    await this.sendCommand('play')
  }

  async pause(): Promise<void> {
    await this.sendCommand('pause')
  }

  async seek(pos: number): Promise<void> {
    await this.sendCommand('seek', pos)
  }

  async setSpeed(speed: number): Promise<void> {
    await this.sendCommand('setSpeed', speed)
  }

  /** 结束投播（释放投播控制器并断开远端连接） */
  async stopCast(): Promise<void> {
    const controller = this.castController
    this.castController = null
    this.lastCastPos = 0
    if (controller != null) {
      await controller.release().catch((err: BusinessError) => {
        Logger.e('fail', `cast release code=${err.code} msg=${err.message}`)
      })
    }
    const session = this.session
    if (session != null) {
      await session.stopCasting().catch((err: BusinessError) => {
        Logger.e('fail', `stopCasting code=${err.code} msg=${err.message}`)
      })
    }
  }

  /** 页面销毁时调用：结束投播并销毁 AVSession */
  async destroy(): Promise<void> {
    await this.stopCast()
    const session = this.session
    if (session != null) {
      session.off('play')
      session.off('pause')
      session.off('seek')
      session.off('playNext')
      session.off('playPrevious')
      session.off('outputDeviceChange')
      await session.destroy().catch((err: BusinessError) => {
        Logger.e('fail', `session destroy code=${err.code} msg=${err.message}`)
      })
      this.session = null
      this.sessionActive = false
    }
    this.deviceName = ''
  }

  /** 注册播控中心控制命令回调（播控中心按钮 → 应用内播放控制） */
  private registerControlCommands(session: avSession.AVSession): void {
    session.on('play', () => {
      const listener = this.listener
      if (listener != null) {
        listener.onControlPlay()
      }
    })
    session.on('pause', () => {
      const listener = this.listener
      if (listener != null) {
        listener.onControlPause()
      }
    })
    session.on('seek', (time: number) => {
      const listener = this.listener
      if (listener != null) {
        listener.onControlSeek(time)
      }
    })
    session.on('playNext', () => {
      const listener = this.listener
      if (listener != null) {
        listener.onControlNext()
      }
    })
    session.on('playPrevious', () => {
      const listener = this.listener
      if (listener != null) {
        listener.onControlPrevious()
      }
    })
  }

  private buildAssetId(episodeIndex: number, link: string): string {
    return `cast-${episodeIndex}-${link}`
  }

  /** 剧集标题（优先剧集描述，其次剧集名） */
  private buildEpisodeTitle(episode: EpisodeInfo): string {
    return episode.desc != '' ? episode.desc : episode.title
  }

  /**
   * 投播展示标题
   * @param withEpisode 是否拼接剧集名（远端播放器无副标题展示位，拼进标题）
   */
  private buildDisplayTitle(episode: EpisodeInfo, withEpisode: boolean): string {
    const episodeTitle = this.buildEpisodeTitle(episode)
    if (this.mediaTitle == '') {
      return episodeTitle
    }
    if (withEpisode) {
      return `${this.mediaTitle} ${episodeTitle}`
    }
    return this.mediaTitle
  }

  private async ensureSession(): Promise<avSession.AVSession | null> {
    if (this.session != null) {
      return this.session
    }
    const context = this.context
    if (context == null) {
      return null
    }
    try {
      const session = await avSession.createAVSession(context, 'AnimeZVideoCast', 'video')
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: context.abilityInfo.bundleName,
          abilityName: context.abilityInfo.name
        }],
        operationType: wantAgent.OperationType.START_ABILITIES,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      }
      const agent = wantAgent.getWantAgent(wantAgentInfo)
      await session.setLaunchAbility(agent)
      this.registerControlCommands(session)
      session.on('outputDeviceChange', (state: avSession.ConnectionState, device: avSession.OutputDeviceInfo) => {
        this.onOutputDeviceChange(state, device)
      })
      this.session = session
      return session
    } catch (err) {
      const e = err as BusinessError
      Logger.e('fail', `createAVSession code=${e.code} msg=${e.message}`)
      return null
    }
  }

  private onOutputDeviceChange(state: avSession.ConnectionState, device: avSession.OutputDeviceInfo): void {
    if (device.devices.length == 0) {
      return
    }
    const info = device.devices[0]
    Logger.e('tips', `outputDeviceChange state=${state} name=${info.deviceName} category=${info.castCategory}`)
    if (info.castCategory == avSession.AVCastCategory.CATEGORY_REMOTE) {
      if (state == avSession.ConnectionState.STATE_CONNECTED) {
        this.onRemoteConnected(info.deviceName)
      } else if (state == avSession.ConnectionState.STATE_DISCONNECTED) {
        this.onRemoteDisconnected()
      }
    } else if (info.castCategory == avSession.AVCastCategory.CATEGORY_LOCAL && this.castController != null) {
      // 用户在设备选择面板切回本机
      this.onRemoteDisconnected()
    }
  }

  private async onRemoteConnected(deviceName: string): Promise<void> {
    this.deviceName = deviceName
    if (this.castController == null) {
      const session = this.session
      if (session == null) {
        return
      }
      const controller: avSession.AVCastController | null =
        await session.getAVCastController().catch((err: BusinessError): null => {
          Logger.e('fail', `getAVCastController code=${err.code} msg=${err.message}`)
          return null
        })
      if (controller == null) {
        return
      }
      this.castController = controller
      this.registerCastListeners(controller)
    }
    const listener = this.listener
    if (listener != null) {
      listener.onCastConnected(deviceName)
    }
    // 设备切换（非首次连接）时从远端最近进度续播
    const startPos = this.lastCastPos > 0 ? this.lastCastPos : this.pendingStartPos
    await this.castEpisode(this.episodeIndex, startPos)
  }

  private async onRemoteDisconnected(): Promise<void> {
    if (this.castController == null) {
      return
    }
    this.deviceName = ''
    await this.stopCast()
    const listener = this.listener
    if (listener != null) {
      listener.onCastDisconnected()
    }
  }

  private registerCastListeners(controller: avSession.AVCastController): void {
    controller.on('playbackStateChange', 'all', (state: avSession.AVPlaybackState) => {
      const listener = this.listener
      if (listener == null) {
        return
      }
      if (state.state == avSession.PlaybackState.PLAYBACK_STATE_PLAY) {
        listener.onCastStateChanged(true)
      } else if (state.state == avSession.PlaybackState.PLAYBACK_STATE_PAUSE) {
        listener.onCastStateChanged(false)
      }
      if (state.position != undefined) {
        const duration = state.duration != undefined ? state.duration : 0
        this.lastCastPos = state.position.elapsedTime
        listener.onCastProgressChange(duration, state.position.elapsedTime)
      }
    })
    controller.on('endOfStream', () => {
      const listener = this.listener
      if (listener != null) {
        listener.onCastEndOfStream()
      }
    })
    controller.on('error', (error: BusinessError) => {
      Logger.e('fail', `cast error code=${error.code} msg=${error.message}`)
    })
  }

  private async sendCommand(command: avSession.AVCastControlCommandType, parameter?: number): Promise<void> {
    const controller = this.castController
    if (controller == null) {
      return
    }
    try {
      const cmd: avSession.AVCastControlCommand = { command: command }
      if (parameter != undefined) {
        cmd.parameter = parameter
      }
      await controller.sendControlCommand(cmd)
    } catch (err) {
      const e = err as BusinessError
      Logger.e('fail', `sendCommand ${command} code=${e.code} msg=${e.message}`)
    }
  }

}
