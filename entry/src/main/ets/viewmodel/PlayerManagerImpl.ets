import media from '@ohos.multimedia.media';
import { IPlayer } from '../player/model/IPlayer';
import IPlayerManager, { PlayerStatus, VideoFit, PlayerListener } from '../player/model/IPlayerManager';
import window from '@ohos.window';
import { BusinessError } from '@kit.BasicServicesKit';
import EpisodeInfo from '../entity/EpisodeInfo';
import Logger from '../utils/Logger';
import SystemBarUtils from '../utils/SystemBarUtils';
import { appContinueModel } from './AppContinueModel';
import { APP_RESUME_PROGRESS_EVENT } from '../utils/EventBus';
import { AnimeState } from '../entryability/AnimeState';

/**
 * 播放器管理（总）
 */
export default class PlayerManagerImpl implements IPlayerManager {
  private url: string = ''
  //  private episode: EpisodeInfo
  private episodeList: EpisodeInfo[] = []
  private episodeIndex: number = 0
  private readonly listeners: PlayerListener[] = []
  private status: number = PlayerStatus.IDLE
  private fullScreenMode: boolean = false
  /** 自由窗口模式下通过 maximize 进入的全屏，退出时需 recover 恢复自由窗口 */
  private fullScreenByMaximize: boolean = false

  private totalTime: number = 0
  private currentTime: number = 0
  private videoSpeed: number = 1.0

  private playAfterInit: boolean = false

  /**
   * 待跳转的续播位置（毫秒）。续播位置不能只存 currentTime：
   * 播放器加载期间会推送 position=0 事件（notifyTime/notifyCurrentTime）覆盖 currentTime，
   * 因此用独立字段保存，仅在 start() 就绪分支消费一次。
   */
  private pendingSeekPos: number = -1

  /**
   * seek 加载圈反馈：播放中 seek 时显示加载圈，位置到达目标点后关闭。
   * mpv 等后端 seek 到已缓冲区域不会产生真实缓冲事件，因此由管理器
   * 在 notifyTime 检测位置到达后发 BUFFERING_END；真实 BUFFERING_END
   * 到达或超时兜底时也会结束等待，防止加载圈卡死。
   */
  private seekWaiting: boolean = false
  private seekTargetMs: number = -1
  private seekTimeoutId: number = -1

  private player: IPlayer = {
    setDataSource: async (url: string): Promise<void> => {
    },
    prepare: async (): Promise<void> => {
    },
    start: async (): Promise<void>  => {
    },
    stop: async (): Promise<void> => {
    },
    pause:async () => {
    },
    reset: async () => {
    },
    release: async () => {
    },
    seekTo: async (msec: number) => {
    },
    setSpeed: async (speed: number) => {
    },
  }

  init(player: IPlayer) {
    this.player = player
    Logger.e('tips', 'init url=' + this.url)
    if (this.url && this.status == PlayerStatus.IDLE && !this.isInitializing) {
      this.isInitializing = true
      this.player.setDataSource(this.url)
    }
  }

  //  async setEpisode(episode: EpisodeInfo) {
  //    if (this.episode == episode) {
  //      return
  //    }
  //    this.episode = episode;
  //    this.listeners.forEach((l) => {
  //      l.onEpisodeChanged(episode)
  //    })
  //    await this.setPlayerUrl(episode.videoUrl)
  //  }

  async playEpisode(episode: EpisodeInfo, startPos: number = -1) {
    //    if (this.episode == episode) {
    //      return
    //    }
    //    this.episode = episode;
    //    this.listeners.forEach((l) => {
    //      l.onEpisodeChanged(episode)
    //    })
    Logger.e('tips', '')
    await this.setPlayerUrl(episode.videoUrl as string, startPos)
    await this.start()
  }

  //  getEpisode(): EpisodeInfo {
  //    return this.episode
  //  }

  async playEpisodeList(episodeList: EpisodeInfo[], episodeIndex: number = 0,
    startPos: number = -1): Promise<void> {
    Logger.e('tips', 'playEpisodeList index=' + episodeIndex + ' startPos=' + startPos
      + ' episodeList=' + JSON.stringify(episodeList))
    this.episodeList = episodeList
    this.episodeIndex = episodeIndex
    this.listeners.forEach((l) => {
      l.onEpisodeChanged(this.episodeList, this.episodeIndex)
    })
    const episode = this.episodeList[this.episodeIndex]
    if (episode.videoUrl) {
      await this.playEpisode(episode, startPos)
    }
  }

  /**
   * 仅切换集数索引并通知监听者，不直接播放。
   * 供选集面板使用：由 ViewModel 的 onEpisodeChanged 统一走 playVideo（含链接解析），
   * 避免面板直接 playEpisodeList 与 ViewModel 回声二次播放导致的状态错乱。
   */
  selectEpisode(index: number) {
    if (index < 0 || index >= this.episodeList.length || index == this.episodeIndex) {
      return
    }
    this.episodeIndex = index
    this.listeners.forEach((l) => {
      l.onEpisodeChanged(this.episodeList, this.episodeIndex)
    })
  }

  //  async playEpisodeAt(episodeIndex: number): Promise<void> {
  //    if (this.episodeList == episodeIndex) {
  //
  //    }
  //    this.episodeIndex = episodeIndex
  //    await this.playEpisode(this.episodeList[episodeIndex])
  //  }

  //  getEpisodeList(): EpisodeInfo[] {
  //    // TODO 获取播放列表
  //    return []
  //  }

  private isInitializing = false

  async setPlayerUrl(url: string, startPos: number = -1) {
    Logger.e('tips', 'setPlayerUrl status=' + this.status + ' url=' + url + ' startPos=' + startPos)
    this.url = url;
    if (this.player) {
      if (this.isPlaying()) {
        await this.player.stop()
      }
      this.isInitializing = true
      // 历史续播：起始位置大于0时从此处播放，否则从头播放
      this.currentTime = startPos > 0 ? startPos : 0
      this.pendingSeekPos = startPos > 0 ? startPos : -1
      if (this.status != PlayerStatus.IDLE) {
        await this.player.reset()
        this.status = PlayerStatus.IDLE
      }
      await this.player.setDataSource(url)
    }
  }

  async start(): Promise<void> {
    Logger.e('tips', 'start isPlaying=' + this.isPlaying() + ' status=' + this.status + ' url=' + this.url)
    if (!this.url || this.isPlaying()) {
      return
    }
    if (this.status == PlayerStatus.IDLE) {
      this.playAfterInit = true
      if (this.player && !this.isInitializing) {
        this.isInitializing = true
        await this.player.setDataSource(this.url)
      }
      return
    }
    if (this.player) {
      if (this.status == PlayerStatus.PAUSE) {
        await this.player.start()
      } else if (this.status == PlayerStatus.INITIALIZED) {
        // 标记待播，保证 prepare 完成进入 PREPARED 后能自动续播
        // （同步置 INITIALIZED 的后端如 ijk/mpv 会走到这里，AVPlayer 因异步时序走 IDLE 分支）
        this.playAfterInit = true
        await this.player.prepare()
      } else if (this.status == PlayerStatus.ERROR) {
        //        await this.stop()
        //        // TODO验证是否有问题
        //        await this.player.prepare()
        this.isInitializing = true
        this.currentTime = 0
        await this.player.reset()
        this.status = PlayerStatus.IDLE
        await this.player.setDataSource(this.url)
      } else {
        // 优先使用未消费的续播位置（currentTime 可能已被加载期间的 position=0 事件覆盖）
        const seekPos = this.pendingSeekPos >= 0 ? this.pendingSeekPos : this.currentTime
        this.pendingSeekPos = -1
        Logger.e('tips', 'start seekTo seekPos=' + seekPos)
        await this.player.setSpeed(this.videoSpeed)
        await this.player.seekTo(seekPos)
        await this.player.start()
      }
    } else {
      this.playAfterInit = true
    }
  }

  async pause() {
    if (this.player) {
      Logger.e('tips', 'pause isPlaying=' + this.isPlaying() + ' status=' + this.status)
      if (this.isPlaying()) {
        await this.player.pause()
      }
    }
  }

  async stop() {
    // 停止播放即取消待自动起播标记：防止加载中途 stop 后，
    // 异步到达的 PREPARED 仍触发自动播放（有声无画）
    this.playAfterInit = false
    // 换集/退出时静默重置 seek 等待，超时兜底不得再发事件
    this.resetSeekWaiting()
    if (this.player) {
      this.totalTime = 0
      this.currentTime = 0
      this.pendingSeekPos = -1
      await this.player.stop();
    }
  }

  async seekTo(value: number) {
    if (this.player) {
      await this.player.seekTo(value)
      this.notifyCurrentTime(value)
      // 仅播放中展示 seek 加载圈（暂停/结束态由状态驱动转圈，事件会被控制器忽略）。
      // 关闭时机三重保障：位置到达目标点 / 真实 BUFFERING_END / 超时兜底，
      // 与后端无关，AV/IJK/mpv 均适用
      if (this.status == PlayerStatus.PLAY) {
        this.seekWaiting = true
        this.seekTargetMs = value
        if (this.seekTimeoutId !== -1) {
          clearTimeout(this.seekTimeoutId)
        }
        this.seekTimeoutId = setTimeout(() => {
          this.clearSeekWaiting()
        }, 10000)
        this.notifyBuffering(media.BufferingInfoType.BUFFERING_START, 0)
      }
    }
  }

  /** 位置到达 seek 目标：关闭 seek 加载圈 */
  private clearSeekWaiting() {
    if (this.seekTimeoutId !== -1) {
      clearTimeout(this.seekTimeoutId)
      this.seekTimeoutId = -1
    }
    if (this.seekWaiting) {
      this.seekWaiting = false
      this.seekTargetMs = -1
      this.notifyBuffering(media.BufferingInfoType.BUFFERING_END, 0)
    }
  }

  /** 静默重置 seek 等待状态（不发事件） */
  private resetSeekWaiting() {
    if (this.seekTimeoutId !== -1) {
      clearTimeout(this.seekTimeoutId)
      this.seekTimeoutId = -1
    }
    this.seekWaiting = false
    this.seekTargetMs = -1
  }

  /** 设置播放倍速（实际倍率数值），换源/重播后由 start() 重新应用 */
  async setSpeed(speed: number) {
    if (this.videoSpeed == speed) {
      return
    }
    this.videoSpeed = speed
    if (this.player) {
      await this.player.setSpeed(speed)
    }
    this.listeners.forEach((l) => {
      l.onVideoSpeedChanged(speed)
    })
  }

  getSpeed(): number {
    return this.videoSpeed
  }

  isPlaying(): boolean {
    return this.player != null && this.status == PlayerStatus.PLAY
  }

  setVideoFit(videoFit: VideoFit) {
    this.listeners.forEach((l) => {
      l.onVideoFitChanged(videoFit)
    })
  }

  setStatus(status: PlayerStatus) {
    if (this.status === status) {
      return
    }
    Logger.e('tips', 'setStatus status=' + status + ' playAfterInit=' + this.playAfterInit)
    this.status = status;
    for (let listener of this.listeners) {
      listener.onStatusChanged(status)
    }
    if (this.status == PlayerStatus.INITIALIZED) {
      this.isInitializing = false
      if (this.playAfterInit) {
        this.player.prepare()
      }
    } else if (this.status == PlayerStatus.PREPARED) {
      if (this.playAfterInit) {
        this.playAfterInit = false
        this.start()
      }
    } else if (this.status == PlayerStatus.DONE) {
      this.currentTime = 0
      this.pendingSeekPos = -1
    }
  }

  getStatus() {
    return this.status
  }

  isPrepared() {
    return this.player && this.status >= PlayerStatus.PREPARED
  }

  notifyTime(duration: number, currentTime: number) {
    this.currentTime = currentTime
    this.totalTime = duration
    // seek 位置已到达目标点：关闭 seek 加载圈
    if (this.seekWaiting && this.seekTargetMs >= 0 && Math.abs(currentTime - this.seekTargetMs) < 2000) {
      this.clearSeekWaiting()
    }
    this.listeners.forEach((l) => {
      l.onProgressChange(this.totalTime, this.currentTime)
    })
  }

  notifyDuration(duration: number) {
    if (!appContinueModel.isContinue) {
      APP_RESUME_PROGRESS_EVENT.emit()

      appContinueModel.isContinue = true
    }
    
    this.totalTime = duration
    this.listeners.forEach((l) => {
      l.onProgressChange(this.totalTime, this.currentTime)
    })
  }

  notifyCurrentTime(currentTime: number) {
    this.currentTime = currentTime
    // 有进度才保存进度
    if (currentTime > 0) {
      appContinueModel.setCurrentVideoDuration(currentTime)
    }
    this.listeners.forEach((l) => {
      l.onProgressChange(this.totalTime, this.currentTime)
    })
  }

  getDuration(): number {
    return this.totalTime
  }

  getCurrentPosition(): number {
    return this.currentTime
  }

  addListener(listener: PlayerListener) {
    this.listeners.push(listener)
    Logger.e('tips', 'addListener len=' + this.listeners.length)

    if (this.episodeList.length != 0) {
      listener.onEpisodeChanged(this.episodeList, this.episodeIndex)
    }
  }

  removeListener(listener: PlayerListener) {
    let index = this.listeners.indexOf(listener)
    if (index >= 0) {
      let result = this.listeners.splice(index, 1)
      return true
    }
    return false
  }

  async destroy() {
    // 先关闭自动续播开关：视频加载完成前退出页面时，
    // 异步到达的 PREPARED 不应再自动起播（否则画面已销毁仍有声音）
    this.playAfterInit = false
    this.pendingSeekPos = -1
    this.isInitializing = false
    this.url = ''
    this.episodeList = []
    this.episodeIndex = 0
    this.totalTime = 0
    this.currentTime = 0
    await this.stop()
    // 彻底释放底层播放器：加载中 stop 可能是空操作，只有 release 能取消加载
    await this.player.release()
    this.listeners.length = 0
  }

  isFullScreen() {
    return this.fullScreenMode
  }

  enterFullScreen(sensorDriven: boolean = false) {
    if (this.fullScreenMode) {
      return
    }
    window.getLastWindow(getContext(this), (err, win) => {
      win.setWindowLayoutFullScreen(true)
      // 隐藏状态栏
      win.setWindowSystemBarEnable([])
      // 自由窗口（小窗）模式下，窗口本身只是悬浮窗，
      // 需 maximize 将窗口扩展为设备屏幕全屏（沉浸式，无标题栏），视频才能真正铺满屏幕
      if (AnimeState.windowMode) {
        win.maximize().then(() => {
          this.fullScreenByMaximize = true
        }).catch((e: BusinessError) => {
          Logger.e('fail', `enterFullScreen maximize code=${e.code}`, e)
        })
      }
      // 手动全屏锁定横屏；传感器触发的全屏保持跟随传感器旋转，
      // 保证手机转回竖屏时窗口随之转回竖屏，从而自动退出全屏
      const orientation = sensorDriven
        ? window.Orientation.AUTO_ROTATION_RESTRICTED
        : window.Orientation.AUTO_ROTATION_LANDSCAPE
      win.setPreferredOrientation(orientation)
      this.fullScreenMode = true
      this.listeners.forEach((listener) => {
        console.log('PlayerManagerlmpl #enterFullScreen isFullScreen：', this.isFullScreen())
        listener.onFullScreenChanged(true)
      })
    })
  }

  exitFullScreen() {
    if (!this.fullScreenMode) {
      return
    }
    window.getLastWindow(getContext(this), (err, win) => {
      win.setWindowLayoutFullScreen(true)
      // 显示状态栏
      win.setWindowSystemBarEnable(['status', 'navigation'])
      // 由 maximize 扩展的全屏需 recover 恢复为原自由窗口
      if (this.fullScreenByMaximize) {
        this.fullScreenByMaximize = false
        win.recover().catch((e: BusinessError) => {
          Logger.e('fail', `exitFullScreen recover code=${e.code}`, e)
        })
      }
      // 设置窗口方向为自动但受系统锁定
      win.setPreferredOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED)
      this.fullScreenMode = false
      this.listeners.forEach((listener) => {
        console.log('PlayerManagerlmpl #exitFullScreen isFullScreen：', this.isFullScreen())
        listener.onFullScreenChanged(false)
      })
    })
  }

  onVideoSizeChanged(width: number, height: number) {
    this.listeners.forEach((l) => {
      l.onVideoSizeChange(width, height)
    })
  }

  notifyBuffering(type: media.BufferingInfoType, value: number) {
    this.listeners.forEach((l) => {
      l.onBuffering(type, value)
    })
    // 真实缓冲结束事件到达：即使位置尚未接近目标，seek 等待也一并结束，
    // 防止后续超时兜底再发出多余的 BUFFERING_END
    if (type == media.BufferingInfoType.BUFFERING_END) {
      this.resetSeekWaiting()
    }
  }

  notifySeekDone() {
    // 底层 seek 完成（AVPlayer/IJK）：立即关闭 seek 加载圈。
    // IJK 非精准 seek 会落在关键帧上，可能与目标位置偏差较大，
    // 位置容差检测不可靠，必须依赖此回调
    this.clearSeekWaiting()
  }
}