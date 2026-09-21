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
  private videoSpeed: number = PlaybackSpeed.Speed_Forward_1_00_X

  private playAfterInit: boolean = false

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
    setSpeed: async (speed: media.PlaybackSpeed) => {
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

  async playEpisode(episode: EpisodeInfo) {
    //    if (this.episode == episode) {
    //      return
    //    }
    //    this.episode = episode;
    //    this.listeners.forEach((l) => {
    //      l.onEpisodeChanged(episode)
    //    })
    Logger.e('tips', '')
    await this.setPlayerUrl(episode.videoUrl as string)
    await this.start()
  }

  //  getEpisode(): EpisodeInfo {
  //    return this.episode
  //  }

  async playEpisodeList(episodeList: EpisodeInfo[], episodeIndex: number = 0): Promise<void> {
    Logger.e('tips', 'playEpisodeList index=' + episodeIndex + ' episodeList=' + JSON.stringify(episodeList))
    this.episodeList = episodeList
    this.episodeIndex = episodeIndex
    this.listeners.forEach((l) => {
      l.onEpisodeChanged(this.episodeList, this.episodeIndex)
    })
    const episode = this.episodeList[this.episodeIndex]
    if (episode.videoUrl) {
      await this.playEpisode(episode)
    }
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

  async setPlayerUrl(url: string) {
    Logger.e('tips', 'setPlayerUrl status=' + this.status + ' url=' + url)
    this.url = url;
    if (this.player) {
      if (this.isPlaying()) {
        await this.player.stop()
      }
      this.isInitializing = true
      this.currentTime = 0
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
        await this.player.setSpeed(this.videoSpeed)
        await this.player.seekTo(this.currentTime)
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
    if (this.player) {
      this.totalTime = 0
      this.currentTime = 0
      await this.player.stop();
    }
  }

  async seekTo(value: number) {
    if (this.player) {
      await this.player.seekTo(value)
      this.notifyBuffering(media.BufferingInfoType.BUFFERING_START, 0)
      this.notifyCurrentTime(value)
    }
  }

  async setSpeed(speed: media.PlaybackSpeed) {
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

  getSpeed(): media.PlaybackSpeed {
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

  destroy() {
    this.stop()
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
  }
}