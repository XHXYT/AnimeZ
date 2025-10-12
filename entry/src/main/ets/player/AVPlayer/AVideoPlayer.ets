import { IPlayer } from '../../entity/VideoPlayer/IPlayer';
import IPlayerManager, { PlayerListener, PlayerStatus, VideoFit } from '../../entity/VideoPlayer/IPlayerManager';
import media from '@ohos.multimedia.media';
import { VideoPlayerController } from '../VideoPlayerController';
import EpisodeInfo from '../../entity/EpisodeInfo';
import DisplayUtils from '../../utils/DisplayUtils';
import Logger from '../../utils/Logger';
import { DEFAULT_DURATION } from '../../utils/TransitionHelper';
import { BusinessError } from '@kit.BasicServicesKit';
import { ToastUtil } from '../../utils/ToastUtils';

const DEFAULT_ASPECT = 1.9

/**
 * 封装media.AVPlayer
 */
class AVPlayerWrapper {
  private readonly avPlayer: media.AVPlayer
  private surfaceId: string = ''

  constructor(avPlayer: media.AVPlayer) {
    this.avPlayer = avPlayer
  }

  async init(manager: IPlayerManager, surfaceId: string): Promise<void> {
    this.surfaceId = surfaceId
    this.bindState(this.avPlayer, manager)
    manager.init(this.getPlayer())
  }

  private getPlayer(): IPlayer {
    const thePlayer: IPlayer = {
      setDataSource: async (urlOrFd: string | media.AVFileDescriptor) => {
        try {
          // 处理本地文件描述符
          if (typeof urlOrFd !== 'string') {
            const fdUrl = `fd://${urlOrFd.fd}?offset=${urlOrFd.offset}&size=${urlOrFd.length}`;
            this.avPlayer.url = fdUrl;
            Logger.e('tips', 'setDataSource from FD: ' + fdUrl);
            return;
          }
          // 网络视频，统一使用 avPlayer.url
          if (urlOrFd.toLowerCase().includes('.m3u8')) {
            // M3U8，使用 MediaSource，
            Logger.e('tips', 'Detected M3U8 stream, using MediaSource.');
            const mediaSource = media.createMediaSourceWithUrl(urlOrFd);
            mediaSource.setMimeType(media.AVMimeTypes.APPLICATION_M3U8);
            await this.avPlayer.setMediaSource(mediaSource);
            // 设置播放策略
            await this.avPlayer.setPlaybackStrategy({
              preferredBufferDurationForPlaying: 0.3,
              preferredBufferDuration: 20,
              showFirstFrameOnPrepare: true
            });
            console.log('PlaybackStrategy set successfully BEFORE prepare.');
            Logger.e('tips', 'M3U8 MediaSource set successfully.');
          } else {
            // 其他网络视频（MP4, 无后缀等）
            Logger.d('setDataSource from URL (Official Way): ' + urlOrFd);
            this.avPlayer.url = urlOrFd;
          }
        } catch (error) {
          Logger.e('fail', 'set data source with MediaSource ', error);
          // 抛出 MediaSource 的错误
          throw error as Error;
        }
      },
      start: async () => {
        Logger.e('tips', 'setDataSource start')
        return this.avPlayer.play().catch(() => {
          console.log(`AVPlayer 视频播放失败`)
        })
      },
      prepare: async () => {
        // this.controller.prepareAsync()
        Logger.e('tips', 'setDataSource prepare')
        try {
          // 调用 prepare
          await this.avPlayer.prepare();
          Logger.w('tips', 'AVPlayer prepare succeeded.');
        } catch (err) {
          Logger.e('fail', `AVPlayer 视频准备失败: ${err.message}`)
        }
      },
      pause: async () => {
        Logger.e('tips', 'setDataSource pause')
        return this.avPlayer.pause().catch(() => {
          console.log(`AVPlayer 视频暂停失败`)
        })
      },
      stop: async () => {
        Logger.e('tips', 'setDataSource stop')
        return this.avPlayer.stop().catch(() => {
          console.log(`AVPlayer 视频停止失败`)
        })
      },
      reset: async () => {
        Logger.e('tips', 'setDataSource reset')
        return this.avPlayer.reset().catch(() => {
          console.log(`AVPlayer 视频重置失败`)
        })
      },
      release: async () => {
        Logger.e('tips', 'setDataSource release')
        return this.avPlayer.release().catch(() => {
          console.log(`AVPlayer 资源释放失败`)
        })
      },
      seekTo: async (value: number) => {
        Logger.e('tips', 'setDataSource seekTo value=' + value)
        return this.avPlayer.seek(value as number)
      },
      setSpeed: (speed: media.PlaybackSpeed): Promise<void> => {
        return this.setSpeed(speed);
      }
    }
    return thePlayer
  }

  async setSpeed(speed: media.PlaybackSpeed) {
    let avSpeed: media.PlaybackSpeed
    switch (speed) {
      case media.PlaybackSpeed.SPEED_FORWARD_0_75_X:
        avSpeed = media.PlaybackSpeed.SPEED_FORWARD_0_75_X
        break
      case media.PlaybackSpeed.SPEED_FORWARD_1_25_X:
        avSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_25_X
        break
      case media.PlaybackSpeed.SPEED_FORWARD_1_75_X:
        avSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_75_X
        break
      case media.PlaybackSpeed.SPEED_FORWARD_2_00_X:
        avSpeed = media.PlaybackSpeed.SPEED_FORWARD_2_00_X
        break
      case media.PlaybackSpeed.SPEED_FORWARD_1_00_X:
      default:
        avSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X
        break
    }
    return this.avPlayer.setSpeed(avSpeed)
  }

  private bindState(avPlayer: media.AVPlayer, manager: IPlayerManager) {
    avPlayer.on('stateChange', async (state: media.AVPlayerState) => {
      Logger.e('tips', 'AVPlayer stateChange state = ' + state)
      switch (state) {
        case 'idle':
          break;
        case 'initialized':
          if (!avPlayer.surfaceId) {
            avPlayer.surfaceId = this.surfaceId;
          }
          manager.setStatus(PlayerStatus.INITIALIZED)
          break;
        case 'prepared':
          avPlayer.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_FIT;
          manager.setStatus(PlayerStatus.PREPARED)
          break;
        case 'playing':
          manager.setStatus(PlayerStatus.PLAY)
          break;
        case 'paused':
          manager.setStatus(PlayerStatus.PAUSE)
          break;
        case 'completed':
          manager.setStatus(PlayerStatus.DONE)
          break;
        case 'stopped':
          manager.setStatus(PlayerStatus.STOP)
          break;
        case 'released':
          manager.setStatus(PlayerStatus.IDLE)
          break;
        case 'error':
          manager.setStatus(PlayerStatus.ERROR)
          break;
        default:
          break;
      }
    });
    avPlayer.on('timeUpdate', (time: number) => {
      Logger.e('tips', 'AVPlayer timeUpdate time = ' + time)
      manager.notifyCurrentTime(time)
    });
    avPlayer.on('durationUpdate', (time: number) => {
      Logger.e('tips', 'AVPlayer durationUpdate time = ' + time)
      manager.notifyDuration(time)
    });
    avPlayer.on('seekDone', (value: number) => {
      Logger.e('tips', 'v seekDone value = ' + value)
    })
    avPlayer.on('videoSizeChange', (w: number, h: number) => {
      Logger.e('tips', 'AVPlayer videoSizeChange w = ' + w + ' h=' + h)
      manager.onVideoSizeChanged(w, h)
    })
    avPlayer.on('error', (error) => {
      Logger.e('fail', 'AVPlayer onError err = ', error)
      manager.setStatus(PlayerStatus.ERROR)
    })
    avPlayer.on('bufferingUpdate', (infoType: media.BufferingInfoType, value: number) => {
      Logger.e('tips', 'AVPlayer bufferingUpdate infoType = ' + infoType + ' value = ' + value)
      manager.notifyBuffering(infoType, value)
    })
  }

}

/**
 * 封装AVPlayer实现播放器控件
 */
@Component
export struct AVideoPlayer {

  @State videoUrl: string = ''
  @State isFullScreen: boolean = false

  @State aspRatio: number = DEFAULT_ASPECT
  @State videoAspRatio: number = DEFAULT_ASPECT
  private originalVideoAspRatio: number = DEFAULT_ASPECT
  @State videoSpeed: media.PlaybackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X

  private readonly componentController: XComponentController = new XComponentController()
  @Link playerManager: IPlayerManager
  private timer: number = -1;

  /**
   * AVPlayer播放器监听回调
   */
  private readonly playerListenerAV: PlayerListener = {
    onStatusChanged: (status: number) => {

    },
    onEpisodeChanged: (episodeList: EpisodeInfo[], episodeIndex: number) => {
      this.videoUrl = episodeList[episodeIndex].videoUrl as string
    },
    onVideoSpeedChanged: (videoSpeed: number) => {
      this.videoSpeed = videoSpeed;
    },
    onVideoFitChanged: (videoFit: VideoFit) => {
      switch (videoFit) {
        case VideoFit.Contain:
          this.videoAspRatio = this.originalVideoAspRatio;
          break;
        case VideoFit.Cover:
          this.videoAspRatio = this.aspRatio;
          break;
        case VideoFit.Fill:
          this.videoAspRatio = this.originalVideoAspRatio;
          break;
        case VideoFit.Fit_16_9:
          this.videoAspRatio = 16 / 9;
          break;
        case VideoFit.Fit_4_3:
          this.videoAspRatio = 4 / 3;
          break;
        case VideoFit.Fit_1_1:
          this.videoAspRatio = 1;
          break;
        default:
          this.videoAspRatio = 16 / 9; // DEFAULT_ASPECT
          break;
      }
    },
    onFullScreenChanged: (isFullScreen: boolean) => {
      console.log('AVideoPlayer #onFullScreenChanged isFullScreen：', isFullScreen)
      this.isFullScreen = isFullScreen;
      ToastUtil.animateTo({
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
      Logger.e('tips', `onVideoSizeChange w=${w} h=${h}`);
      this.originalVideoAspRatio = w / h;
      ToastUtil.animateTo({
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
      this.playerManager.addListener(this.playerListenerAV)
    } else {
      throw new Error('You must set playerManager firstly!')
    }
  }

  aboutToDisappear() {
    this.playerManager?.removeListener(this.playerListenerAV)
    if (this.timer >= 0) {
      clearTimeout(this.timer)
      this.timer = -1
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({
        type: XComponentType.SURFACE,
        controller: this.componentController,
        id: 'xComponentID',
        libraryname: ''
      })
        .onLoad((context) => {
          if (!this.playerManager) {
            Logger.e('fail', 'XComponent onLoad failed: playerManager is null.');
            return;
          }
          const surfaceId = this.componentController.getXComponentSurfaceId()
          Logger.e('tips', `'AVPlayer XComponent onLoad surfaceId = ${surfaceId}`)
          media.createAVPlayer()
            .then((player) => {
              const avPlayer: AVPlayerWrapper = new AVPlayerWrapper(player)
              avPlayer.init(this.playerManager as IPlayerManager, surfaceId)
            })
            .catch(() => {
              console.error(`AVPlayer XComponent 加载失败`)
            })
        })
        .onDestroy(() => {
          Logger.e('tips', 'AVPlayer XComponent onDestroy')
        })
        .width('100%')
        .aspectRatio(this.videoAspRatio)
        .height(this.isFullScreen ? '100%' : undefined)

      VideoPlayerController({ playerManager: this.playerManager })
        .width('100%')
        .height('100%')
    }
    .height(this.isFullScreen ? '100%' : undefined)
    .backgroundColor(Color.Black)
    .aspectRatio(this.aspRatio)
    .width('100%')
  }
}