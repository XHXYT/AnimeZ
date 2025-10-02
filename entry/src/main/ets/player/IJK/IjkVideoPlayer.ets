import media from '@ohos.multimedia.media';
import { IPlayer } from '../../entity/VideoPlayer/IPlayer';
import { IJKMediaInfo } from './IjkMediaInfo';
import { VideoPlayerController } from '../VideoPlayerController';
import IPlayerManager, { PlayerListener, PlayerStatus, VideoFit } from '../../entity/VideoPlayer/IPlayerManager';
import EpisodeInfo from '../../entity/EpisodeInfo';
import DisplayUtils from '../../utils/DisplayUtils';
import Logger from '../../utils/Logger';
import { IjkPlayerNapi } from '@ohos/ijkplayer/src/main/ets/ijkplayer/utils/IjkPlayerNapi';
import { IjkMediaPlayer } from '@ohos/ijkplayer';
import { DEFAULT_DURATION } from '../../utils/TransitionHelper';

const DEFAULT_ASPECT = 1.9

/**
 * 视频播放器，封装IjkPlayer
 * TODO 网络视频还存在加载缓慢的问题
 */
@Component
export struct IjkVideoPlayer {
  private readonly ijkPlayer = IjkMediaPlayer.getInstance()
  @State videoAspRatio: number = DEFAULT_ASPECT
  @State aspRatio: number = DEFAULT_ASPECT
  @State playStatus: number = PlayerStatus.IDLE
  @State playerStatus: PlayerStatus = PlayerStatus.IDLE
  @State isFullScreen: boolean = false
  private readonly componentController: XComponentController = new XComponentController()
  @Link playerManager: IPlayerManager
  private updateProgressTimer: number = -1
  private lastTime: number = 0
  /**播放器*/
  private readonly player: IPlayer = {
    setDataSource: async (url: string) => {
      this.ijkPlayer.setDataSource(url);
      this.playerManager?.setStatus(PlayerStatus.INITIALIZED);
    },

    prepare: async () => {
      this.ijkPlayer.prepareAsync()
    },

    start: async (): Promise<void>  => {
      this.ijkPlayer.start()
      this.playerManager?.setStatus(PlayerStatus.PLAY)
    },

    stop: async (): Promise<void> => {
      this.ijkPlayer.stop()
      this.playerManager?.setStatus(PlayerStatus.STOP)
    },

    pause:async () => {
      this.ijkPlayer.pause();
      this.playerManager?.setStatus(PlayerStatus.PAUSE);
    },

    reset: async () => {
      this.ijkPlayer.reset()
      this.playerManager?.setStatus(PlayerStatus.IDLE)
    },

    release: async () => {
      this.ijkPlayer.release()
    },

    seekTo: async (msec: number) => {
      this.ijkPlayer.seekTo(String(msec));
    },

    setSpeed: async (speed: media.PlaybackSpeed) => {
      let speedValue: string;
      switch (speed) {
        case media.PlaybackSpeed.SPEED_FORWARD_0_75_X:
          speedValue = '0.75';
          break;
        case media.PlaybackSpeed.SPEED_FORWARD_1_00_X:
          speedValue = '1.00';
          break;
        case media.PlaybackSpeed.SPEED_FORWARD_1_25_X:
          speedValue = '1.25';
          break;
        case media.PlaybackSpeed.SPEED_FORWARD_1_75_X:
          speedValue = '1.75';
          break;
        case media.PlaybackSpeed.SPEED_FORWARD_2_00_X:
          speedValue = '2.00';
          break;
        default:
          speedValue = '1.00'; // 默认速度
          break;
      }
      this.ijkPlayer.setSpeed(speedValue);
    },
  }
  /**播放器监听回调*/
  private readonly playerListener: PlayerListener = {
    onStatusChanged: (status: number) => {
      this.playerStatus = status

      if (status == PlayerStatus.PLAY) {
        this.startProgress()
      } else {
        this.stopProgress()
      }
    },
    onEpisodeChanged: (episodeList: EpisodeInfo[], episodeIndex: number) => {
    },
    onVideoSpeedChanged: (videoSpeed: media.PlaybackSpeed) => {
    },
    onVideoFitChanged: (videoFit: VideoFit) => {
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
      this.playerManager.addListener(this.playerListener)
    } else {
      throw new Error('You must set playerManager firstly!')
    }
  }

  aboutToDisappear() {
    this.playerManager?.removeListener(this.playerListener)
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        XComponent({
          type: XComponentType.SURFACE,
          controller: this.componentController,
          id: '' + new Date().getTime(),
          libraryname: 'ijkplayer_napi'
        })
          .onLoad((context: IjkPlayerNapi) => {
            Logger.e('tips', 'XComponent onLoad')

            this.initIjk(context)
            this.playerManager?.init(this.player)
          })
          .onDestroy(() => {
            Logger.e('tips', 'XComponent onDestroy')
          })
          .width('100%')
          .aspectRatio(this.videoAspRatio)

        VideoPlayerController({ playerManager: this.playerManager })
          .width('100%')
          .height('100%')
      }
      .backgroundColor(Color.Black)
      .width('100%')
      .aspectRatio(this.aspRatio)
    }
    .width('100%')
  }

  initIjk(context: IjkPlayerNapi) {
    Logger.e('tips', 'init context=' + context)
    //设置XComponent回调的context
    this.ijkPlayer.setContext(context);
    this.ijkPlayer.reset();

    //设置debug模式
    this.ijkPlayer.setDebug(false);
    //初始化配置
    this.ijkPlayer.native_setup();
    // 屏幕常亮
    this.ijkPlayer.setScreenOnWhilePlaying(true);

    this.initPlayer()
    this.initOptions()
  }

  private initPlayer() {
    this.ijkPlayer.setOnVideoSizeChangedListener({
      onVideoSizeChanged: (width: number, height: number, sar_num: number, sar_den: number) => {
        if (typeof width == 'string') {
          width = parseInt(width)
        }
        if (typeof height == 'string') {
          height = parseInt(height)
        }
        this.playerManager?.onVideoSizeChanged(width, height)
      }
    })

    this.ijkPlayer.setOnBufferingUpdateListener({
      onBufferingUpdate: (percent: number) => {
        Logger.e('tips', 'onBufferingUpdate p=' + percent)
      }
    })

    this.ijkPlayer.setOnCompletionListener({
      onCompletion: () => {
        Logger.e('tips', 'onCompletion')
        this.playerManager?.setStatus(PlayerStatus.DONE)
      }
    })

    this.ijkPlayer.setOnSeekCompleteListener({
      onSeekComplete: () => {
        Logger.e('tips', 'onSeekComplete')
      }
    })


    this.ijkPlayer.setOnErrorListener({
      onError: (what: number, extra: number) => {
        Logger.e('tips', 'onError what=' + what + " extra=" + extra)
        this.playerManager?.setStatus(PlayerStatus.ERROR)
      }
    })

    this.ijkPlayer.setOnPreparedListener({
      onPrepared: () => {
        Logger.e('tips', 'onPrepared')
        this.playerManager?.setStatus(PlayerStatus.PREPARED)
      }
    })

    this.ijkPlayer.setOnInfoListener({
      onInfo: (what: number, extra: number) => {
        this.onInfo(what, extra)
      }
    })

    this.ijkPlayer.setMessageListener()
  }

  private initOptions() {
    // 不用MediaCodec编解码
    this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec", '1');
    // 不用opensles编解码
    this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "opensles", '0');
    this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "overlay-format", '842225234');
    this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "framedrop", '1');
    this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "start-on-prepared", '0');
    this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "http-detect-range-support", '0');
    this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "timeout", '10000000');
    this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "reconnect", '1');
    this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_CODEC, "skip_loop_filter", '48');
    this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "enable-accurate-seek", '0');
    this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "dns_cache_clear", '1');
  }

  protected onInfo(what: number, extra: number) {
    Logger.e('tips', "OnInfoListener-->go:" + what + "===" + extra);
    if (what == IJKMediaInfo.MEDIA_INFO_BUFFERING_START) {
      this.playerManager?.notifyBuffering(media.BufferingInfoType.BUFFERING_START, 0)
    } else if (what == IJKMediaInfo.MEDIA_INFO_BUFFERING_END) {
      this.playerManager?.notifyBuffering(media.BufferingInfoType.BUFFERING_END, 0)
    } else if (what == IJKMediaInfo.MEDIA_INFO_VIDEO_RENDERING_START) {
      this.ijkPlayer.start()
      this.playerManager?.setStatus(PlayerStatus.PLAY)
    }
  }

  /**
   * 每隔1000ms通知播放进度
   */
  private startProgress() {
    this.stopProgress()
    this.updateProgressTimer = setInterval(() => {
      if (this.updateProgressTimer < 0) {
        return
      }
      let totalTime = this.ijkPlayer.getDuration()
      let currentTime = this.ijkPlayer.getCurrentPosition()
      if (this.lastTime == currentTime) {
        return
      }
      this.lastTime = currentTime
      this.playerManager?.notifyTime(totalTime, currentTime)
    }, 1000);
    Logger.e('tips', 'startProgress updateProgressTimer=' + this.updateProgressTimer)
  }

  private stopProgress() {
    if (this.updateProgressTimer < 0) {
      return
    }
    let timer = this.updateProgressTimer;
    this.updateProgressTimer = -1
    clearInterval(timer)
  }
}