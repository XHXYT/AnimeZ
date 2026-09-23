import { PiPWindow, typeNode } from '@kit.ArkUI';
import media from '@ohos.multimedia.media';
import { BusinessError } from '@kit.BasicServicesKit';
import Logger from '../utils/Logger';
import { _AnimeState, AnimeState } from '../entryability/AnimeState';
import { VideoNavigateInfo } from '../entity/VideoNavigateInfo';

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
    if (!this.controller) {
      return
    }
    try {
      this.controller.setAutoStartEnabled(enabled)
    } catch (err) {
      Logger.e('tips', 'setAutoStartEnabled error: ' + JSON.stringify(err))
    }
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
        contentWidth: 1920,
        contentHeight: 1080,
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
      await this.setupPiPPlayer(info)
      const controller = this.controller
      if (!controller) {
        throw new Error('PiP controller null')
      }
      await controller.startPiP()
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

  /** 创建 PiP 独立 AVPlayer 并起播（url → surfaceId → prepare → seek/play/倍速） */
  private async setupPiPPlayer(info: PiPNavigationInfo): Promise<void> {
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
      if (state === 'prepared') {
        try {
          if (info.position > 0) {
            player.seek(info.position)
          }
          player.play()
        } catch (err) {
          Logger.e('tips', 'PiP player start error: ' + JSON.stringify(err))
        }
        this.applySpeed(player, info.speed)
        if (player.width > 0 && player.height > 0) {
          this.updateContentSize(player.width, player.height)
        }
      }
    })
    player.url = info.url
    player.surfaceId = surfaceId
    await player.prepare()
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
        break
      case PiPWindow.PiPState.ABOUT_TO_RESTORE:
        // 刷新实时进度供恢复导航/收回播放使用
        if (this.navigationInfo && this.pipPlayer) {
          this.navigationInfo.position = this.pipPlayer.currentTime
        }
        if (this.onRestoreCallback) {
          this.onRestoreCallback()
        }
        break
      case PiPWindow.PiPState.STOPPED:
        this.isActive = false
        this.cleanupPlayer()
        break
      case PiPWindow.PiPState.ERROR:
        Logger.e('tips', `PiP error reason=${reason}`)
        this.isActive = false
        this.cleanupPlayer()
        break
      default:
        break
    }
  }

  /**
   * STARTED：区分手动启动（播放器已就绪）与退后台系统自动拉起（需接管播放现场）
   */
  private handlePiPStarted(): void {
    if (this.pipPlayer) {
      // 手动启动：播放器已由 startPiP 流程就绪
      return
    }
    // 后台系统自动拉起：页面未销毁，恢复导航由页面 onShown 收回处理
    this.onRestoreCallback = null
    const snapshot = this.playbackSnapshot
    if (!snapshot || !snapshot.url) {
      Logger.w('PiPManager', 'auto start without snapshot, stop PiP')
      this.stopPiP()
      return
    }
    const pos = this.mainPositionProvider ? this.mainPositionProvider() : snapshot.position
    const info: PiPNavigationInfo = {
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
    }
    this.navigationInfo = info
    this.setupPiPPlayer(info).catch((err: BusinessError) => {
      Logger.e('tips', 'auto start setup player failed: ' + JSON.stringify(err))
      this.stopPiP()
    })
    // 暂停主播放器，防止双音频
    if (this.mainPlayerPauser) {
      this.mainPlayerPauser()
    }
  }

  /** PiP 控制面板事件（播放/暂停；关闭按钮由系统直接 STOPPED） */
  private handleControlEvent(event: PiPWindow.ControlEventParam): void {
    const player = this.pipPlayer
    if (!player) {
      return
    }
    if (event.controlType === PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE) {
      try {
        if (event.status === PiPWindow.PiPControlStatus.PAUSE) {
          player.pause()
        } else {
          player.play()
        }
      } catch (err) {
        Logger.e('tips', 'PiP control event error: ' + JSON.stringify(err))
      }
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
    }
    AnimeState.pageStack.pushPathByName('VideoDetailPage', params)
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
    await this.cleanupPlayer()
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
