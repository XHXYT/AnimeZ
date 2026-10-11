import { PiPWindow, typeNode } from '@kit.ArkUI';
import media from '@ohos.multimedia.media';
import { BusinessError } from '@kit.BasicServicesKit';
import Logger from '../utils/Logger';
import { _AnimeState, AnimeState } from '../entryability/AnimeState';
import { VideoNavigateInfo } from '../entity/VideoNavigateInfo';
import { appSettings } from '../entryability/Settings';
import EpisodeInfo from '../entity/EpisodeInfo';
import { dataSourceManager } from '../api/DataSourceManager';
import { WebVideoResolver } from '../utils/WebVideoResolver';

/** 支持小窗播放的播放器后端（小窗画面由独立 AVPlayer 渲染，其余后端隐藏入口且不自动触发） */
const PIP_SUPPORTED_PLAYERS: string[] = ['av', 'ijk'];

/**
 * PiP 播放导航信息（进入小窗时的播放现场，用于独立播放与恢复导航）
 */
export interface PiPNavigationInfo {
  /** 视频直链（媒体流地址，PiP 独立 AVPlayer 加载用） */
  url: string;
  /** 详情页链接（恢复导航用） */
  detailUrl: string;
  /** 历史记录 ID（恢复导航用） */
  videoId: number | null;
  /** 起播位置（毫秒） */
  position: number;
  /** 播放倍速 */
  speed: number;
  episodeListIndex: number;
  episodeIndex: number;
  episodeName: string;
  title: string;
  coverUrl: string;
  sourceKey: string;
  /** 当前剧集列表（小窗面板切集用；页面销毁后小窗仍可独立切集） */
  episodeList?: EpisodeInfo[];
}

/**
 * PiP 渲染表面控制器：typeNode XComponent 的 surface 创建/销毁回调
 */
class PiPSurfaceController extends XComponentController {
  onSurfaceCreated(surfaceId: string): void {
    PiPManager.onSurfaceCreated(surfaceId)
  }

  onSurfaceDestroyed(surfaceId: string): void {
    Logger.i('PiPManager', `onSurfaceDestroyed surfaceId=${surfaceId}`)
    PiPManager.onSurfaceDestroyed(surfaceId)
  }
}

/**
 * PiP 管理器单例
 * typeNode 方案：动态创建的 XComponent 自由节点（不挂任何页面）作为小窗内容载体，
 * 由独立 AVPlayer 渲染画面，小窗播放完全独立于播放页生命周期（页面退出后继续播）。
 */
export class _PiPManager {

  /** PiP 窗口是否活跃 */
  isActive: boolean = false

  /** 本次 PiP 会话信息（ABOUT_TO_RESTORE 时刷新实时进度，恢复导航消费） */
  navigationInfo: PiPNavigationInfo | null = null

  /** 主播放现场快照（播放中由详情页 VM 更新，退后台系统自动拉起时接管播放用） */
  playbackSnapshot: PiPNavigationInfo | null = null

  // ===== 详情页 VM 注册的委托 =====
  /** 手动小窗按钮 → 当前活跃详情页 VM 执行 */
  requestHandler: (() => void) | null = null
  /** 读取主播放器实时位置（自动拉起时对齐进度） */
  mainPositionProvider: (() => number) | null = null
  /** 自动拉起后暂停主播放器（防双音频） */
  mainPlayerPauser: (() => void) | null = null
  /** PiP 播放错误提示回调 */
  onPipError: ((message: string) => void) | null = null
  /** 小窗内切集回调（详情页 VM 注册：同步剧集状态、保存历史） */
  onEpisodeSwitched: ((listIndex: number, episodeIndex: number) => void) | null = null
  /** 点小窗恢复按钮原地收回播放（详情页 VM 注册；为 null 时走恢复导航 push 新页） */
  onPipRestore: ((position: number) => void) | null = null
  /** 主播放器要求起播但小窗仍活跃：详情页原地收回（收回流程内部自行续播） */
  requestTakeover: (() => void) | null = null
  /** 小窗被关闭（面板 X / 播放错误）：通知详情页清占位并对齐进度 */
  onPipStopped: ((position: number) => void) | null = null

  /** startPiP 手动启动标记（STARTED 时区分手动/系统自动拉起） */
  private pendingManualStart: boolean = false

  /** 小窗切集进行中（防面板连点重复解析） */
  private isSwitchingEpisode: boolean = false

  /** PiP 控制器 */
  private controller: PiPWindow.PiPController | null = null

  /** typeNode XComponent 节点（小窗内容载体） */
  private contentNode: typeNode.XComponent | null = null

  /** 渲染表面控制器 */
  private surfaceController: PiPSurfaceController = new PiPSurfaceController()

  /** surfaceId（onSurfaceCreated 回调写入） */
  private surfaceId: string = ''

  /** surface 就绪等待队列 */
  private surfaceWaiters: Array<(id: string) => void> = []

  /** PiP 独立播放器 */
  private pipPlayer: media.AVPlayer | null = null

  /** 恢复到详情页回调（手动启动场景 push 新页；后台自动拉起场景为 null，由页面 onShown 收回） */
  private onRestoreCallback: (() => void) | null = null

  /** startPiP 防重入 */
  private isStarting: boolean = false

  /** controller 创建中 */
  private isPreparing: boolean = false

  /** 当前设备是否支持 PiP */
  isPiPEnabled(): boolean {
    try {
      return PiPWindow.isPiPEnabled()
    } catch (err) {
      Logger.e('tips', 'isPiPEnabled error: ' + JSON.stringify(err))
      return false
    }
  }

  /** 播放器后端是否支持小窗（决定入口显隐与自动触发） */
  isPlayerSupported(playerKey: string): boolean {
    return PIP_SUPPORTED_PLAYERS.indexOf(playerKey) >= 0
  }

  /** 手动小窗按钮入口（转发给当前活跃详情页 VM） */
  requestPiP(): void {
    if (this.requestHandler) {
      this.requestHandler()
    }
  }

  /** typeNode surface 就绪回调 */
  onSurfaceCreated(surfaceId: string): void {
    Logger.i('PiPManager', `onSurfaceCreated surfaceId=${surfaceId}`)
    if (this.surfaceId === surfaceId) {
      return
    }
    this.surfaceId = surfaceId
    const waiters = this.surfaceWaiters
    this.surfaceWaiters = []
    waiters.forEach((resolve: (id: string) => void) => {
      resolve(surfaceId)
    })
  }

  /** surface 销毁（小窗关闭）：清缓存，下次启动等待新 surface，避免绑定过期 surface */
  onSurfaceDestroyed(surfaceId: string): void {
    if (this.surfaceId === surfaceId) {
      this.surfaceId = ''
    }
  }

  /** 等待 surface 就绪（typeNode 节点创建后 surface 异步创建） */
  private async waitForSurface(timeoutMs: number = 5000): Promise<string> {
    if (this.surfaceId) {
      return this.surfaceId
    }
    return new Promise<string>((resolve, reject) => {
      let done = false
      const timer = setTimeout(() => {
        if (!done) {
          done = true
          reject(new Error('PiP surface timeout'))
        }
      }, timeoutMs)
      this.surfaceWaiters.push((id: string) => {
        if (!done) {
          done = true
          clearTimeout(timer)
          resolve(id)
        }
      })
    })
  }

  /**
   * 预创建 PiP 控制器并开启后台自动拉起（视频开始播放时由 VM 调用）
   * 官方约束：应用后台禁止 startPiP，后台自动小窗必须在前台时 create + setAutoStartEnabled(true)
   */
  async prepare(): Promise<void> {
    if (this.isActive || this.isStarting) {
      return
    }
    const ok = await this.ensureController()
    if (ok) {
      this.setAutoStartEnabledSafe(true)
    }
  }

  /** 同步后台自动拉起开关 */
  setAutoStartEnabledSafe(enabled: boolean): void {
    // 记录开关状态：窗口隐藏（锁屏/退后台）时据此决定等待小窗接管还是立即暂停主播放器
    this.isAutoStartEnabled = enabled
    if (!this.controller) {
      return
    }
    try {
      this.controller.setAutoStartEnabled(enabled)
    } catch (err) {
      Logger.e('tips', 'setAutoStartEnabled error: ' + JSON.stringify(err))
    }
  }

  /** 后台自动拉起开关当前是否开启 */
  isAutoStartEnabled: boolean = false

  /** 默认尺寸配置已变更：待小窗停止后丢弃缓存控制器，下次按新配置重建 */
  private pendingRecreate: boolean = false

  /**
   * 默认尺寸配置变更后调用：丢弃缓存的 PiP 控制器，
   * 下次 ensureController 按新 defaultWindowSizeType 重建；
   * 小窗活跃中不销毁（会中断播放），标记待停止时重建
   */
  invalidateController(): void {
    if (this.isActive) {
      this.pendingRecreate = true
      return
    }
    this.controller = null
  }

  /** 记录小窗实际窗口尺寸（验证默认档位实际生效情况） */
  logWindowSize(): void {
    const controller = this.controller
    if (!controller) {
      return
    }
    controller.getPiPWindowInfo().then((info: PiPWindow.PiPWindowInfo) => {
      Logger.i('PiPManager',
        `PiP window size=${info.size.width}x${info.size.height} scale=${info.size.scale} defaultType=${appSettings.pip_default_size}`)
    }).catch((err: BusinessError) => {
      Logger.e('tips', `getPiPWindowInfo failed code=${err.code} msg=${err.message}`)
    })
  }

  /** 确保 typeNode 节点与 PiP 控制器就绪（幂等） */
  private async ensureController(): Promise<boolean> {
    if (this.controller) {
      return true
    }
    if (this.isPreparing) {
      return false
    }
    if (!this.isPiPEnabled()) {
      Logger.w('PiPManager', 'PiP not supported on this device')
      return false
    }
    const uiContext = _AnimeState.UIContext
    const context = _AnimeState.Context
    if (!uiContext || !context) {
      Logger.e('tips', 'UIContext/Context not ready')
      return false
    }
    this.isPreparing = true
    try {
      if (!this.contentNode) {
        this.contentNode = typeNode.createNode(uiContext, 'XComponent', {
          type: XComponentType.SURFACE,
          controller: this.surfaceController,
        })
      }
      const config: PiPWindow.PiPConfiguration = {
        context: context,
        componentController: this.surfaceController,
        templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY,
        // 面板显示上一个/下一个剧集按钮（默认仅播放/暂停）
        controlGroups: [PiPWindow.VideoPlayControlGroup.VIDEO_PREVIOUS_NEXT],
        contentWidth: 1920,
        contentHeight: 1080,
        // 小窗默认尺寸档位（1~4 透传系统，真机验证实际生效档位）
        defaultWindowSizeType: appSettings.pip_default_size,
      }
      const controller = await PiPWindow.create(config, this.contentNode)
      controller.on('stateChange', (state: PiPWindow.PiPState, reason: string): void => {
        this.handleStateChange(state, reason)
      })
      controller.on('controlEvent', (event: PiPWindow.ControlEventParam): void => {
        this.handleControlEvent(event)
      })
      this.controller = controller
      Logger.i('PiPManager', 'PiP controller created')
      return true
    } catch (err) {
      const e = err as BusinessError
      Logger.e('tips', `create PiP controller failed code=${e.code} message=${e.message}`)
      return false
    } finally {
      this.isPreparing = false
    }
  }

  /**
   * 启动小窗（手动按钮/返回/导航离开场景）
   * @param info 播放现场（url/进度/剧集/恢复导航信息）
   */
  async startPiP(info: PiPNavigationInfo): Promise<boolean> {
    if (this.isActive) {
      Logger.w('PiPManager', 'PiP already active')
      return true
    }
    if (this.isStarting) {
      Logger.w('PiPManager', 'PiP starting')
      return false
    }
    this.isStarting = true
    try {
      this.navigationInfo = info
      if (!await this.ensureController()) {
        throw new Error('PiP controller unavailable')
      }
      const controller = this.controller
      if (!controller) {
        throw new Error('PiP controller null')
      }
      // 播放器必须等窗口 STARTED 后创建（surface 在 ABOUT_TO_START→STARTED 间才创建，
      // 提前创建会绑定过期/不存在的 surface 导致画面不渲染）
      this.pendingManualStart = true
      await controller.startPiP()
      this.logWindowSize()
      // 已在小窗中，防止退后台时系统重复拉起
      this.setAutoStartEnabledSafe(false)
      // 手动启动场景：点击小窗恢复时 push 回详情页
      this.onRestoreCallback = () => {
        this.restoreToDetailPage()
      }
      return true
    } catch (err) {
      Logger.e('tips', 'startPiP failed: ' + JSON.stringify(err))
      await this.cleanupPlayer()
      return false
    } finally {
      this.isStarting = false
    }
  }

  /**
   * 创建 PiP 独立 AVPlayer 并起播（url → surfaceId → prepare → seek/play/倍速）
   * 注意：url 设置后异步进入 initialized，surfaceId/prepare 必须等 stateChange(initialized)
   * 再执行，立即调用会抛 5400102（unsupport prepare operation）
   * @param useMainPosition true=起播瞬间取主播放器实时进度（系统自动拉起接管，消除接管时差）
   */
  private async setupPiPPlayer(info: PiPNavigationInfo, useMainPosition: boolean): Promise<void> {
    const surfaceId = await this.waitForSurface()
    const player = await media.createAVPlayer()
    this.pipPlayer = player
    player.on('error', (err: BusinessError) => {
      Logger.e('tips', `PiP player error code=${err.code} message=${err.message}`)
      if (this.onPipError) {
        this.onPipError('小窗播放出错，已退出小窗')
      }
      this.stopPiP()
    })
    player.on('stateChange', (state: string) => {
      if (state === 'initialized') {
        // initialized 状态才允许设置 surfaceId 并 prepare（官方 typeNode 画中画示例同款时序）
        try {
          player.surfaceId = surfaceId
        } catch (err) {
          Logger.e('tips', 'PiP player set surfaceId error: ' + JSON.stringify(err))
          this.stopPiP()
          return
        }
        player.prepare().catch((err: BusinessError) => {
          Logger.e('tips', `PiP player prepare error code=${err.code} message=${err.message}`)
          this.stopPiP()
        })
        return
      }
      if (state === 'prepared') {
        try {
          // 自动接管场景：起播瞬间读主播放器实时进度（prepare 期间主播放器仍在走）
          let pos = info.position
          if (useMainPosition && this.mainPositionProvider) {
            const live = this.mainPositionProvider()
            if (live > 0) {
              pos = live
            }
          }
          if (pos > 0) {
            // SEEK_CLOSEST 精确续播：默认 SEEK_PREV_SYNC 会落到上一个关键帧，观感进度回退
            player.seek(pos, media.SeekMode.SEEK_CLOSEST)
          }
          player.play()
        } catch (err) {
          Logger.e('tips', 'PiP player start error: ' + JSON.stringify(err))
        }
        this.applySpeed(player, info.speed)
        if (player.width > 0 && player.height > 0) {
          this.updateContentSize(player.width, player.height)
        }
        // 小窗起播后再暂停主播放器：声音画面无断层交接（此前 STARTED 即暂停会有 1~2s 空窗）
        if (this.mainPlayerPauser) {
          this.mainPlayerPauser()
        }
      }
    })
    player.url = info.url
  }

  /** 应用播放倍速（AVPlayer 仅支持标准档位，超出的回退 2.0） */
  private applySpeed(player: media.AVPlayer, speed: number): void {
    let target: media.PlaybackSpeed = media.PlaybackSpeed.SPEED_FORWARD_2_00_X
    if (speed <= 0.75) {
      target = media.PlaybackSpeed.SPEED_FORWARD_0_75_X
    } else if (speed <= 1.0) {
      target = media.PlaybackSpeed.SPEED_FORWARD_1_00_X
    } else if (speed <= 1.25) {
      target = media.PlaybackSpeed.SPEED_FORWARD_1_25_X
    } else if (speed <= 1.75) {
      target = media.PlaybackSpeed.SPEED_FORWARD_1_75_X
    }
    try {
      player.setSpeed(target)
    } catch (err) {
      Logger.e('tips', 'setSpeed error: ' + JSON.stringify(err))
    }
  }

  /** PiP 窗口生命周期 */
  private handleStateChange(state: PiPWindow.PiPState, reason: string): void {
    Logger.i('PiPManager', `PiP state=${state} reason=${reason}`)
    switch (state) {
      case PiPWindow.PiPState.STARTED:
        this.isActive = true
        this.handlePiPStarted()
        this.logWindowSize()
        break
      case PiPWindow.PiPState.ABOUT_TO_RESTORE:
        // 刷新实时进度供恢复导航/收回播放使用
        if (this.navigationInfo && this.pipPlayer) {
          this.navigationInfo.position = this.pipPlayer.currentTime
        }
        if (this.onPipRestore) {
          // 详情页仍在栈内：原地收回播放（不 push 新页）
          this.onPipRestore(this.navigationInfo ? this.navigationInfo.position : 0)
        } else if (this.onRestoreCallback) {
          this.onRestoreCallback()
        }
        break
      case PiPWindow.PiPState.STOPPED:
        this.isActive = false
        this.pendingManualStart = false
        this.notifyPipStopped()
        this.cleanupPlayer()
        // 默认尺寸配置已变更：丢弃控制器，下次启动按新档位重建
        if (this.pendingRecreate) {
          this.pendingRecreate = false
          this.controller = null
        }
        break
      case PiPWindow.PiPState.ERROR:
        Logger.e('tips', `PiP error reason=${reason}`)
        this.isActive = false
        this.pendingManualStart = false
        this.notifyPipStopped()
        this.cleanupPlayer()
        if (this.pendingRecreate) {
          this.pendingRecreate = false
          this.controller = null
        }
        break
      default:
        break
    }
  }

  /**
   * STARTED：surface 已创建，此时创建播放器才能绑到有效 surface。
   * 手动启动（startPiP 标记）用进入小窗时的播放现场；
   * 退后台系统自动拉起则从主播放现场快照接管。
   */
  private handlePiPStarted(): void {
    if (this.pipPlayer) {
      return
    }
    const manual: boolean = this.pendingManualStart
    this.pendingManualStart = false
    if (!manual) {
      // 后台系统自动拉起：页面未销毁，恢复导航由页面 onShown 收回处理
      this.onRestoreCallback = null
      const snapshot = this.playbackSnapshot
      if (!snapshot || !snapshot.url) {
        Logger.w('PiPManager', 'auto start without snapshot, stop PiP')
        this.stopPiP()
        return
      }
      const pos = this.mainPositionProvider ? this.mainPositionProvider() : snapshot.position
      this.navigationInfo = {
        url: snapshot.url,
        detailUrl: snapshot.detailUrl,
        videoId: snapshot.videoId,
        position: pos > 0 ? pos : 0,
        speed: snapshot.speed,
        episodeListIndex: snapshot.episodeListIndex,
        episodeIndex: snapshot.episodeIndex,
        episodeName: snapshot.episodeName,
        title: snapshot.title,
        coverUrl: snapshot.coverUrl,
        sourceKey: snapshot.sourceKey,
        episodeList: snapshot.episodeList,
      }
    }
    const info = this.navigationInfo
    if (!info || !info.url) {
      Logger.w('PiPManager', 'PiP start without playable url, stop PiP')
      this.stopPiP()
      return
    }
    this.setupPiPPlayer(info, !manual).catch((err: BusinessError) => {
      Logger.e('tips', 'PiP setup player failed: ' + JSON.stringify(err))
      // 小窗未接管成功：兜底暂停主播放器，避免后台失控
      if (this.mainPlayerPauser) {
        this.mainPlayerPauser()
      }
      this.stopPiP()
    })
    this.syncEpisodeControlState()
  }

  /** PiP 控制面板事件（播放/暂停、上一个/下一个；关闭按钮由系统直接 STOPPED） */
  private handleControlEvent(event: PiPWindow.ControlEventParam): void {
    if (event.controlType === PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE) {
      const player = this.pipPlayer
      if (!player) {
        return
      }
      try {
        if (event.status === PiPWindow.PiPControlStatus.PAUSE) {
          player.pause()
        } else {
          player.play()
        }
      } catch (err) {
        Logger.e('tips', 'PiP control event error: ' + JSON.stringify(err))
      }
      return
    }
    if (event.controlType === PiPWindow.PiPControlType.VIDEO_PREVIOUS) {
      this.trySwitchEpisode(false)
      return
    }
    if (event.controlType === PiPWindow.PiPControlType.VIDEO_NEXT) {
      this.trySwitchEpisode(true)
    }
  }

  /** 面板上一个/下一个：小窗内原地切集（窗口不关，播放器重建换源） */
  private async trySwitchEpisode(next: boolean): Promise<void> {
    const nav = this.navigationInfo
    if (!nav || !nav.episodeList || this.isSwitchingEpisode) {
      return
    }
    const target = nav.episodeIndex + (next ? 1 : -1)
    if (target < 0 || target >= nav.episodeList.length) {
      return
    }
    const episode = nav.episodeList[target]
    this.isSwitchingEpisode = true
    try {
      let url = episode.videoUrl
      if (!url) {
        // 未播放过的集：走与详情页一致的解析链，结果缓存回剧集对象供恢复复用
        url = await dataSourceManager.parseVideoUrl(episode.link, nav.sourceKey)
        url = await WebVideoResolver.resolve(url)
        episode.videoUrl = url
      }
      nav.url = url
      nav.episodeIndex = target
      nav.episodeName = episode.title
      nav.position = 0
      if (this.onEpisodeSwitched) {
        this.onEpisodeSwitched(nav.episodeListIndex, target)
      }
      this.switchPiPEpisode()
    } catch (err) {
      // 解析失败：小窗继续播当前集
      Logger.e('tips', 'PiP switch episode failed: ' + JSON.stringify(err))
    } finally {
      this.isSwitchingEpisode = false
    }
  }

  /** 小窗切集：复用小窗 surface，仅重建小窗播放器 */
  private switchPiPEpisode(): void {
    const nav = this.navigationInfo
    if (!nav || !nav.url) {
      return
    }
    this.cleanupPlayer().then(() => {
      this.setupPiPPlayer(nav, false).catch((err: BusinessError) => {
        Logger.e('tips', 'PiP switch episode setup failed: ' + JSON.stringify(err))
        this.stopPiP()
      })
    })
    this.syncEpisodeControlState()
  }

  /** 同步面板上一个/下一个按钮可用态（边界置灰） */
  private syncEpisodeControlState(): void {
    const controller = this.controller
    const nav = this.navigationInfo
    if (!controller || !nav) {
      return
    }
    const list = nav.episodeList
    const hasPrevious: boolean = list !== undefined && nav.episodeIndex > 0
    const hasNext: boolean = list !== undefined && nav.episodeIndex < list.length - 1
    try {
      controller.setPiPControlEnabled(PiPWindow.PiPControlType.VIDEO_PREVIOUS, hasPrevious)
      controller.setPiPControlEnabled(PiPWindow.PiPControlType.VIDEO_NEXT, hasNext)
    } catch (err) {
      Logger.e('tips', 'setPiPControlEnabled error: ' + JSON.stringify(err))
    }
  }

  /** 暂停小窗播放（收回播放前静音小窗，避免与主播放器双声/断层） */
  pausePlayback(): void {
    const player = this.pipPlayer
    if (!player) {
      return
    }
    try {
      player.pause()
    } catch (err) {
      Logger.e('tips', 'PiP pause playback error: ' + JSON.stringify(err))
    }
  }

  /** 播控卡片上一个/下一个命令：小窗活跃时由小窗原地切集（主播放器让位中） */
  switchEpisode(next: boolean): void {
    if (this.isActive) {
      this.trySwitchEpisode(next)
    }
  }

  /** 点击小窗恢复：push 回详情页并以小窗实时进度续播 */
  private restoreToDetailPage(): void {
    const nav = this.navigationInfo
    if (!nav) {
      return
    }
    const params: VideoNavigateInfo = {
      id: nav.videoId,
      url: nav.detailUrl,
      sourceKey: nav.sourceKey,
      title: nav.title,
      cover: nav.coverUrl,
      isPiPRestore: true,
      pipPosition: nav.position,
      // 小窗内切过集时同步最后播放的集（页面已销毁场景历史里还是旧集）
      pipEpisodeListIndex: nav.episodeListIndex,
      pipEpisodeIndex: nav.episodeIndex,
      pipEpisodeName: nav.episodeName,
    }
    AnimeState.pushPage('VideoDetailPage', params)
  }

  /** 小窗当前播放位置（收回播放时续播用） */
  getPlaybackPosition(): number {
    if (this.pipPlayer) {
      return this.pipPlayer.currentTime
    }
    return this.navigationInfo ? this.navigationInfo.position : 0
  }

  /** 停止小窗并释放播放器 */
  async stopPiP(): Promise<void> {
    const controller = this.controller
    if (controller) {
      try {
        await controller.stopPiP()
      } catch (err) {
        Logger.e('tips', 'stopPiP error: ' + JSON.stringify(err))
      }
    }
    // 同步清活跃标记：收回后立刻 recover/start 时读不到陈旧的 isActive
    // （STOPPED 事件可能晚于本方法返回）
    this.isActive = false
    this.pendingManualStart = false
    await this.cleanupPlayer()
  }

  /** 小窗关闭通知详情页（取实时进度；VM 未注册/已让位时忽略） */
  private notifyPipStopped(): void {
    if (!this.onPipStopped) {
      return
    }
    const position = this.getPlaybackPosition()
    this.onPipStopped(position)
  }

  /** 释放 PiP 独立播放器 */
  private async cleanupPlayer(): Promise<void> {
    const player = this.pipPlayer
    if (!player) {
      return
    }
    this.pipPlayer = null
    try {
      player.off('stateChange')
      player.off('error')
    } catch (err) {
      Logger.e('tips', 'player off error: ' + JSON.stringify(err))
    }
    try {
      await player.release()
    } catch (err) {
      Logger.e('tips', 'player release error: ' + JSON.stringify(err))
    }
  }

  /** 更新小窗比例（PREPARED 后按视频实际宽高调整） */
  updateContentSize(width: number, height: number): void {
    if (!this.controller) {
      return
    }
    try {
      this.controller.updateContentSize(width, height)
    } catch (err) {
      Logger.e('tips', 'updateContentSize error: ' + JSON.stringify(err))
    }
  }
}

// 全局单例
export const PiPManager: _PiPManager = new _PiPManager()
