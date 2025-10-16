
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
import { AVVolumePanel } from '@kit.AudioKit';

const DEFAULT_ASPECT = 1.9



/**
 * 封装AVPlayer实现播放器控件
 */
@Component
export struct AVideoPlayer {
  private volumeTimer: number = -1;

  @State videoUrl: string = ''
  @State isFullScreen: boolean = false

  @State aspRatio: number = DEFAULT_ASPECT
  @State videoAspRatio: number = DEFAULT_ASPECT
  private originalVideoAspRatio: number = DEFAULT_ASPECT
  @State videoSpeed: media.PlaybackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X

  private readonly componentController: XComponentController = new XComponentController()
  @Link playerManager: IPlayerManager
  private timer: number = -1;
  @StorageProp('windowHeight') windowHeight: number = 0
  @StorageProp('windowWidth') windowWidth: number = 0
  /** @description 默认系统音量 */
  @State volume: number = 5
  /** @description 音量面板是否可见 */
  @State volumeVisible: boolean = false
  /** @description 音量面板高度 */
  @State VolumePanelHeight: number = 0
  /** @description 是否在屏幕左侧触发手势 */
  private isLeftSideGesture: boolean = false
  /** @description 上一次手势的Y坐标 */
  private lastGestureY: number = 0

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
      // 系统音量面板
      AVVolumePanel({
        volumeLevel: this.volume,
        volumeParameter: {
          position: {
            x: 50,
            y: (this.windowHeight + this.VolumePanelHeight) / 2,
          }
        }
      })
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.VolumePanelHeight = newValue.height as number
        })

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
    .gesture(
      PanGesture({ direction: PanDirection.Vertical })
        .onActionStart((event: GestureEvent) => {
          // 判断手势是否在屏幕左侧（左半部分）
          const gestureX = event.fingerList[0]?.localX ?? 0;
          this.isLeftSideGesture = gestureX < this.windowWidth / 2;
          
          if (this.isLeftSideGesture) {
            this.lastGestureY = event.fingerList[0]?.localY ?? 0;
            this.volumeVisible = true;
          }
        })
        .onActionUpdate((event: GestureEvent) => {
          // 只在左侧才处理音量调节
          if (!this.isLeftSideGesture) {
            return;
          }
          
          this.volumeVisible = true;
          
          // 获取当前手指的Y坐标
          const currentY = event.fingerList[0]?.localY ?? 0;
          // 计算Y坐标的变化量（向上滑动为负，向下滑动为正）
          const deltaY = currentY - this.lastGestureY;
          
          // 根据滑动距离调节音量，每滑动30px改变1级音量
          // 向上滑动增加音量，向下滑动降低音量
          const volumeChange = -deltaY / 30;
          let curVolume = this.volume + volumeChange;
          
          // 限制音量范围在 0-15 之间
          curVolume = curVolume >= 15.0 ? 15.0 : curVolume;
          curVolume = curVolume <= 0.0 ? 0.0 : curVolume;
          this.volume = curVolume;
          
          // 更新上一次的Y坐标
          this.lastGestureY = currentY;
        })
        .onActionEnd(() => {
          // 只在左侧手势时设置定时器隐藏音量面板
          if (this.isLeftSideGesture) {
            this.setVolumeTimer();
          }
          this.isLeftSideGesture = false;
        })
    )
  }

  /**
   * @description 设置定时器隐藏音量面板
   */
  setVolumeTimer(): void {
    // 清除之前的定时器
    if (this.volumeTimer >= 0) {
      clearTimeout(this.volumeTimer);
    }
    // 5秒后隐藏音量面板
    this.volumeTimer = setTimeout(() => {
      this.volumeVisible = false;
    }, 5000);
  }
}