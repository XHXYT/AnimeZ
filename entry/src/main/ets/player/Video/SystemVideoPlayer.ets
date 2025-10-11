import IPlayerManager, { PlayerListener, PlayerStatus, VideoFit } from '../../entity/VideoPlayer/IPlayerManager';
import media from '@ohos.multimedia.media';
import { IPlayer } from '../../entity/VideoPlayer/IPlayer';
import { VideoPlayerController } from '../VideoPlayerController';
import EpisodeInfo from '../../entity/EpisodeInfo';
import DisplayUtils from '../../utils/DisplayUtils';
import Logger from '../../utils/Logger';
import { DEFAULT_DURATION } from '../../utils/TransitionHelper';

const DEFAULT_ASPECT = 1.9


/**
 * 视频播放器，封装系统Video TODO 已损坏
 */
@Component
export struct SystemVideoPlayer {

  @State videoAspRatio: number = DEFAULT_ASPECT
  @State aspRatio: number = DEFAULT_ASPECT
  @State playerStatus: number = PlayerStatus.IDLE
  @State isFullScreen: boolean = false
  @State videoUrl: string = ''
  @State videoSpeed: media.PlaybackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X
  @State videoFit: ImageFit = ImageFit.Contain
  @Link  playerManager: IPlayerManager
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

    setSpeed: (speed: media.PlaybackSpeed) => {
      return new Promise<void>((resolve, reject) => {
        try {
          this.videoSpeed = speed
          resolve()
        } catch (error) {
          reject(error)
        }
      })
    },
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
        .aspectRatio(this.videoAspRatio)
        .height(this.isFullScreen ? '100%' : undefined)
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
    .height(this.isFullScreen ? '100%' : undefined)
    .backgroundColor(Color.Black)
    .aspectRatio(this.aspRatio)
    .width('100%')
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