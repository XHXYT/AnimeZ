
import IPlayerManager, { PlayerListener, PlayerStatus, VideoFit } from '../model/IPlayerManager';
import media from '@ohos.multimedia.media';
import { VideoPlayerController } from '../VideoPlayerController';
import EpisodeInfo from '../../entity/EpisodeInfo';
import DisplayUtils from '../../utils/DisplayUtils';
import Logger from '../../utils/Logger';
import { DEFAULT_DURATION } from '../../utils/TransitionHelper';
import { BusinessError } from '@kit.BasicServicesKit';
import { ToastUtil } from '../../utils/ToastUtils';
import { AVPlayerWrapper } from './AVPlayerWrapper';
import { AnimeState } from '../../entryability/AnimeState';

const DEFAULT_ASPECT = 1.9



/**
 * 封装AVPlayer实现播放器控件
 */
@ComponentV2
export struct AVideoPlayer {

  @Local videoUrl: string = ''
  @Local isFullScreen: boolean = false

  @Local aspRatio: number = DEFAULT_ASPECT
  @Local videoAspRatio: number = DEFAULT_ASPECT
  @Local videoFit: VideoFit = VideoFit.Contain
  @Local videoSpeed: media.PlaybackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X

  private readonly componentController: XComponentController = new XComponentController()
  @Require @Param playerManager: IPlayerManager
  /** 播放器区域为全高（左右分栏等）时撑满容器，控制层可利用上下黑边空间 */
  @Param fillHeight: boolean = false
  /** 外层容器实测宽高比（onAreaChange 测量，0 表示未测量） */
  @Local containerRatio: number = 0
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
      this.videoFit = videoFit;
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
        id: 'xComponent',
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
}