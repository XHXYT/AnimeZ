import IPlayerManager, { PlayerListener, PlayerStatus, VideoFit } from '../model/IPlayerManager';
import media from '@ohos.multimedia.media';
import { IPlayer } from '../model/IPlayer';
import { VideoPlayerController } from '../VideoPlayerController';
import EpisodeInfo from '../../entity/EpisodeInfo';
import DisplayUtils from '../../utils/DisplayUtils';
import Logger from '../../utils/Logger';
import { DEFAULT_DURATION } from '../../utils/TransitionHelper';
import { AnimeState } from '../../entryability/AnimeState';

const DEFAULT_ASPECT = 1.9


/**
 * 视频播放器，封装系统Video TODO 已损坏
 */
@ComponentV2
export struct SystemVideoPlayer {

  @Local videoAspRatio: number = DEFAULT_ASPECT
  @Local aspRatio: number = DEFAULT_ASPECT
  @Local playerStatus: number = PlayerStatus.IDLE
  @Local isFullScreen: boolean = false
  @Local videoUrl: string = ''
  @Local videoSpeed: PlaybackSpeed = PlaybackSpeed.Speed_Forward_1_00_X
  @Local videoFit: ImageFit = ImageFit.Contain
  @Require @Param playerManager: IPlayerManager
  /** 播放器区域为全高（左右分栏等）时撑满容器，控制层可利用上下黑边空间 */
  @Param fillHeight: boolean = false
  private timer: number = -1;
  private originalVideoAspRatio: number = DEFAULT_ASPECT;
  private readonly controller: VideoController = new VideoController()
  /** 播放器 */
  private readonly player: IPlayer = {
    setDataSource: async (url: string): Promise<void> => {
      this.playerManager.setStatus(PlayerStatus.INITIALIZED)
      this.videoUrl = url
    },

    prepare: async (): Promise<void> => {
      // this.controller.prepareAsync()
    },

    start: async (): Promise<void>  => {
      this.controller.start()
      this.playerManager.setStatus(PlayerStatus.PLAY)
    },

    stop: async (): Promise<void> => {
      this.controller.stop()
      this.playerManager.setStatus(PlayerStatus.STOP)
    },

    pause:async () => {
      this.controller.pause()
      this.playerManager.setStatus(PlayerStatus.PAUSE)
    },

    reset: async () => {
      this.playerManager.setStatus(PlayerStatus.IDLE)
    },

    release: async () => {
    },

    seekTo: async (msec: number) => {
      this.controller.setCurrentTime(msec / 1000, SeekMode.ClosestKeyframe)
    },

    setSpeed: (speed: number) => {
      return new Promise<void>((resolve, reject) => {
        try {
          this.videoSpeed = this.rateToPlaybackSpeed(speed)
          resolve()
        } catch (error) {
          reject(error)
        }
      })
    },
  }

  /**
   * 实际倍率数值映射为 Video 组件的固定档位枚举：
   * Video 组件仅支持 0.75/1.0/1.25/1.75/2.0 档位，
   * 按最接近档位映射；超出 2x（如长按 3x 倍速）取最高档 2x
   */
  private rateToPlaybackSpeed(speed: number): PlaybackSpeed {
    if (speed < 0.875) {
      return PlaybackSpeed.Speed_Forward_0_75_X
    }
    if (speed < 1.125) {
      return PlaybackSpeed.Speed_Forward_1_00_X
    }
    if (speed < 1.5) {
      return PlaybackSpeed.Speed_Forward_1_25_X
    }
    if (speed < 1.875) {
      return PlaybackSpeed.Speed_Forward_1_75_X
    }
    return PlaybackSpeed.Speed_Forward_2_00_X
  }

  /**播放器监听回调*/
  private readonly playerListener: PlayerListener = {
    onStatusChanged: (status: number) => {

    },
    onEpisodeChanged: (episodeList: EpisodeInfo[], episodeIndex: number) => {

    },
    onVideoSpeedChanged: (videoSpeed: number) => {

    },
    onVideoFitChanged: (videoFit: VideoFit) => {
      switch (videoFit) {
        case VideoFit.Contain:
          this.videoAspRatio = DEFAULT_ASPECT
          this.videoFit = ImageFit.Contain
          break
        case VideoFit.Cover:
          this.videoAspRatio = this.aspRatio
          this.videoFit = ImageFit.Cover
          break
        case VideoFit.Fill:
          this.videoAspRatio = this.originalVideoAspRatio
          this.videoFit = ImageFit.Fill
          break
        case VideoFit.Fit_16_9:
          this.videoAspRatio = 16 / 9
          this.videoFit = ImageFit.Fill
          break
        case VideoFit.Fit_4_3:
          this.videoAspRatio = 4/ 3
          this.videoFit = ImageFit.Fill
          break
        case VideoFit.Fit_1_1:
          this.videoAspRatio = 1
          this.videoFit = ImageFit.Fill
          break
        default:
          this.videoAspRatio = DEFAULT_ASPECT
          this.videoFit = ImageFit.Contain
          break
      }
    },
    onFullScreenChanged: (isFullScreen: boolean) => {
      this.isFullScreen = isFullScreen
      animateTo({
        duration: DEFAULT_DURATION,
        curve: Curve.Smooth,
        iterations: 1,
        playMode: PlayMode.Normal
      }, () => {
        if (isFullScreen) {
          this.aspRatio = DisplayUtils.getRealScreenHWRatio()
        } else {
          this.aspRatio = Math.min(DEFAULT_ASPECT, this.videoAspRatio);
        }
      })
    },
    onVideoSizeChange: (w: number, h: number) => {
      this.originalVideoAspRatio = w / h
      animateTo({
        duration: DEFAULT_DURATION,
        curve: Curve.Smooth,
        iterations: 1,
        playMode: PlayMode.Normal
      }, () => {
        this.videoAspRatio = w / h
        if (this.isFullScreen) {
          this.aspRatio = DisplayUtils.getRealScreenHWRatio()
        } else {
          this.aspRatio = Math.min(DEFAULT_ASPECT, this.videoAspRatio);
        }
        Logger.e('tips', 'VideoSizeChange w=' + w + ' h=' + h + ' videoAspRatio=' + this.videoAspRatio + ' aspRatio=' + this.aspRatio)
      })
    },
    onProgressChange: (totalTime: number, currentTime: number) => {

    },
    onBuffering: (type: media.BufferingInfoType, value: number) => {

    }
  }

  aboutToAppear() {
    if (this.playerManager) {
      this.playerManager.init(this.player)
      this.playerManager.addListener(this.playerListener)
    } else {
      throw new Error('You must set playerManager firstly!')
    }
  }

  aboutToDisappear() {
    this.playerManager?.removeListener(this.playerListener)
    if (this.timer >= 0) {
      clearTimeout(this.timer)
      this.timer = -1
    }
  }


  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 视频组件
      Video({ src: this.videoUrl, currentProgressRate: this.videoSpeed, controller: this.controller })
        .width('100%')
        .autoPlay(true)
        .controls(false)
        .objectFit(this.videoFit)
        .aspectRatio(this.fillHeight || this.isFullScreen ? undefined : Math.max(this.videoAspRatio, this.getOuterAspRatio()))
        .height(this.fillHeight || this.isFullScreen ? '100%' : undefined)
        .onStart(() => {
          Logger.e('tips', 'onStart')
          this.playerManager?.setStatus(PlayerStatus.PLAY)
        })
        .onError(() => {
          Logger.e('tips', 'onError')
          this.playerManager?.setStatus(PlayerStatus.ERROR)
        })
        .onPrepared((e) => {
          Logger.e('tips', 'onPrepared')
          this.playerManager?.setStatus(PlayerStatus.PREPARED)
          this.playerManager?.notifyDuration(e.duration * 1000)
        })
        .onPause(() => {
          let status = this.playerManager?.getStatus()
          Logger.e('tips', 'onPause currentStatus=' + status)
          if (status == PlayerStatus.ERROR || status == PlayerStatus.STOP) {
            return
          }
          if (!this.playerManager?.isPrepared()) {

          } else {
            if (status == PlayerStatus.PLAY) {
              // 播放或缓冲时可以暂停视频
              this.playerManager.setStatus(PlayerStatus.PAUSE)
            }
          }
        })
        .onSeeking((e) => {
          // TODO seek时没有回调该函数？
          Logger.e('tips', 'onSeeking time=' + e.time)
        })
        .onSeeked((e) => {
          // TODO seek时没有回调该函数？
          Logger.e('tips', 'onSeeked time=' + e.time)
          this.playerManager?.notifySeekDone()
        })
        .onFinish(() => {
          Logger.e('tips', 'onFinish')
          this.playerManager?.setStatus(PlayerStatus.DONE)
        })
        .onUpdate((e) => {
          Logger.e('tips', 'onUpdate time=' + e.time + ' status=' + this.playerManager?.getStatus())
          this.checkPlayingStatus()
          this.playerManager?.notifyCurrentTime(e.time * 1000)
        })
      if (this.playerManager) {
        VideoPlayerController({ playerManager: this.playerManager })
          .width('100%')
          .height('100%')
      }
    }
    .height(this.isFullScreen || this.fillHeight ? '100%' : undefined)
    .backgroundColor(Color.Black)
    .aspectRatio(this.isFullScreen || this.fillHeight ? undefined : this.getOuterAspRatio())
    .width('100%')
  }

  /**
   * 视频区外框比例：横屏窗口（宽 > 高）时钳制到可用窗口比例，
   * 避免按视频比例计算出的高度超出屏幕（如手机 2.17 屏幕比 + 16:9 视频会上下溢出）
   */
  private getOuterAspRatio(): number {
    if (AnimeState.windowWidth <= AnimeState.windowHeight) {
      return this.aspRatio
    }
    const availableHeight = this.isFullScreen ? AnimeState.windowHeight : AnimeState.windowHeight - AnimeState.topRectHeight
    return Math.max(this.aspRatio, AnimeState.windowWidth / availableHeight)
  }

  /**
   * Video每隔一秒会更新播放进度，如果超过一秒（暂时设为1200ms）没有更新播放进度，则判断为此时可能是在缓冲视频
   */
  private checkPlayingStatus() {
    // 清除已存在的timer
    if (this.timer >= 0) {
      clearTimeout(this.timer)
      this.timer = -1
      this.playerManager?.notifyBuffering(media.BufferingInfoType.BUFFERING_END, 100)
    }

    this.timer = setTimeout(() => {
      if (this.timer < 0) {
        return
      }
      this.timer = -1
      if (this.playerManager?.isPlaying()) {
        this.playerManager.notifyBuffering(media.BufferingInfoType.BUFFERING_START, 0)
      }
    }, 1300)
  }


}