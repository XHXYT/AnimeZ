
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

const DEFAULT_ASPECT = 1.9



/**
 * 封装AVPlayer实现播放器控件
 */
@Component
export struct AVideoPlayer {
  private avPlayer?: AVPlayerWrapper;

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
              this.avPlayer = new AVPlayerWrapper(player)
              this.avPlayer.init(this.playerManager as IPlayerManager, surfaceId)

            })
            .catch(() => {
              console.error(`AVPlayer XComponent 加载失败`)
            })
        })
        .onDestroy(() => {
          Logger.e('tips', 'AVPlayer XComponent onDestroy')
          this.avPlayer?.destroy()
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