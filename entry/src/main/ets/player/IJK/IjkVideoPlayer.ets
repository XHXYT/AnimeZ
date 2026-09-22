import media from '@ohos.multimedia.media';
import { IPlayer } from '../model/IPlayer';
import { IJKMediaInfo } from './IjkMediaInfo';
import { VideoPlayerController } from '../VideoPlayerController';
import IPlayerManager, { PlayerListener, PlayerStatus, VideoFit } from '../model/IPlayerManager';
import EpisodeInfo from '../../entity/EpisodeInfo';
import DisplayUtils from '../../utils/DisplayUtils';
import Logger from '../../utils/Logger';
import { IjkPlayerNapi } from '@ohos/ijkplayer/src/main/ets/ijkplayer/utils/IjkPlayerNapi';
import { IjkMediaPlayer } from '@ohos/ijkplayer';
import { DEFAULT_DURATION } from '../../utils/TransitionHelper';
import { AnimeState } from '../../entryability/AnimeState';

const DEFAULT_ASPECT = 1.9

/**
 * 视频播放器，封装IjkPlayer
 * TODO 网络视频还存在加载缓慢的问题
 */
@ComponentV2
export struct IjkVideoPlayer {
  private readonly ijkPlayer = IjkMediaPlayer.getInstance()
  /** 组件卸载后拒绝所有操作，防止迟到的异步回调污染管理器状态 */
  private destroyed: boolean = false
  @Local videoAspRatio: number = DEFAULT_ASPECT
  @Local aspRatio: number = DEFAULT_ASPECT
  @Local videoFit: VideoFit = VideoFit.Contain
  @Local playStatus: number = PlayerStatus.IDLE
  @Local playerStatus: PlayerStatus = PlayerStatus.IDLE
  @Local isFullScreen: boolean = false
  private readonly componentController: XComponentController = new XComponentController()
  @Require @Param playerManager: IPlayerManager
  /** 播放器区域为全高（左右分栏等）时撑满容器，控制层可利用上下黑边空间 */
  @Param fillHeight: boolean = false
  /** 外层容器实测宽高比（onAreaChange 测量，0 表示未测量） */
  @Local containerRatio: number = 0
  private updateProgressTimer: number = -1
  private lastTime: number = 0
  /**播放器*/
  private readonly player: IPlayer = {
    setDataSource: async (url: string) => {
      if (this.destroyed) {
        return
      }
      this.ijkPlayer.setDataSource(url);
      this.playerManager?.setStatus(PlayerStatus.INITIALIZED);
    },

    prepare: async () => {
      if (this.destroyed) {
        return
      }
      this.ijkPlayer.prepareAsync()
    },

    start: async (): Promise<void> => {
      if (this.destroyed) {
        return
      }
      this.ijkPlayer.start()
      this.playerManager?.setStatus(PlayerStatus.PLAY)
    },

    stop: async (): Promise<void> => {
      if (this.destroyed) {
        return
      }
      this.ijkPlayer.stop()
      this.playerManager?.setStatus(PlayerStatus.STOP)
    },

    pause:async () => {
      if (this.destroyed) {
        return
      }
      this.ijkPlayer.pause();
      this.playerManager?.setStatus(PlayerStatus.PAUSE);
    },

    reset: async () => {
      if (this.destroyed) {
        return
      }
      this.ijkPlayer.reset()
      this.playerManager?.setStatus(PlayerStatus.IDLE)
    },

    release: async () => {
      if (this.destroyed) {
        return
      }
      try {
        this.ijkPlayer.release()
      } catch (error) {
        Logger.e('fail', 'IjkVideoPlayer.release', error)
      }
    },

    seekTo: async (msec: number) => {
      if (this.destroyed) {
        return
      }
      this.ijkPlayer.seekTo(String(msec));
    },

    setSpeed: async (speed: number) => {
      if (this.destroyed) {
        return
      }
      const speedValue = speed.toFixed(2);
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
    onVideoSpeedChanged: (videoSpeed: number) => {
    },
    onVideoFitChanged: (videoFit: VideoFit) => {
      this.videoFit = videoFit;
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
    this.destroyed = true
    this.playerManager?.removeListener(this.playerListener)
    this.stopProgress()
    // 组件卸载即释放底层播放器：切换播放器后端或退出页面时，
    // 防止 IJK 在 Surface 已销毁的情况下继续出声（与 MPV 行为对齐）
    try {
      this.ijkPlayer.release()
    } catch (error) {
      Logger.e('fail', 'IjkVideoPlayer aboutToDisappear release', error)
    }
  }

  build() {
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
        .width(this.isSurfaceHeightDriven() ? undefined : '100%')
        .aspectRatio(this.getSurfaceRatio())
        .height(this.isSurfaceHeightDriven() ? '100%' : undefined)

      VideoPlayerController({ playerManager: this.playerManager })
        .width('100%')
        .height('100%')
    }
    .height(this.isFullScreen || this.fillHeight ? '100%' : undefined)
    .backgroundColor(Color.Black)
    .clip(true)
    .aspectRatio(this.isFullScreen || this.fillHeight ? undefined : this.getOuterAspRatio())
    .width('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const w: number = Number(newArea.width)
      const h: number = Number(newArea.height)
      if (w > 0 && h > 0) {
        this.containerRatio = w / h
      }
    })
  }

  /** 当前画面尺寸模式对应的渲染表面宽高比 */
  private getSurfaceRatio(): number {
    switch (this.videoFit) {
      case VideoFit.Fill:
        return this.getContainerRatio();
      case VideoFit.Fit_16_9:
        return 16 / 9;
      case VideoFit.Fit_4_3:
        return 4 / 3;
      case VideoFit.Fit_1_1:
        return 1;
      case VideoFit.Cover:
      case VideoFit.Contain:
      default:
        return this.videoAspRatio;
    }
  }

  /**
   * 渲染表面是否以高度为基准（高度撑满、宽度按比例收缩/溢出）：
   * 适应/拉伸/固定比例时在容器内适配（宽高比小于容器则两侧留黑边），
   * 铺满裁剪（Cover）时反向驱动，超出部分由外层裁剪
   */
  private isSurfaceHeightDriven(): boolean {
    const surfaceRatio = this.getSurfaceRatio();
    const outerRatio = this.getContainerRatio();
    if (this.videoFit === VideoFit.Cover) {
      return surfaceRatio > outerRatio;
    }
    return surfaceRatio < outerRatio;
  }

  /** 实测容器宽高比（onAreaChange 测量；未测量时回退到按窗口推算的值） */
  private getContainerRatio(): number {
    return this.containerRatio > 0 ? this.containerRatio : this.getOuterAspRatio()
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
        if (this.destroyed) {
          return
        }
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
        if (this.destroyed) {
          return
        }
        Logger.e('tips', 'onBufferingUpdate p=' + percent)
      }
    })

    this.ijkPlayer.setOnCompletionListener({
      onCompletion: () => {
        if (this.destroyed) {
          return
        }
        Logger.e('tips', 'onCompletion')
        this.playerManager?.setStatus(PlayerStatus.DONE)
      }
    })

    this.ijkPlayer.setOnSeekCompleteListener({
      onSeekComplete: () => {
        if (this.destroyed) {
          return
        }
        Logger.e('tips', 'onSeekComplete')
        this.playerManager?.notifySeekDone()
      }
    })


    this.ijkPlayer.setOnErrorListener({
      onError: (what: number, extra: number) => {
        if (this.destroyed) {
          return
        }
        Logger.e('tips', 'onError what=' + what + " extra=" + extra)
        this.playerManager?.setStatus(PlayerStatus.ERROR)
      }
    })

    this.ijkPlayer.setOnPreparedListener({
      onPrepared: () => {
        if (this.destroyed) {
          return
        }
        Logger.e('tips', 'onPrepared')
        this.playerManager?.setStatus(PlayerStatus.PREPARED)
      }
    })

    this.ijkPlayer.setOnInfoListener({
      onInfo: (what: number, extra: number) => {
        if (this.destroyed) {
          return
        }
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