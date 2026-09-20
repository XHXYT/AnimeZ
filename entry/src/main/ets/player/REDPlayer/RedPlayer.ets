import media from '@ohos.multimedia.media';
import { IPlayer } from '../model/IPlayer';
import { VideoPlayerController } from '../VideoPlayerController';
import IPlayerManager, { PlayerListener, PlayerStatus, VideoFit } from '../model/IPlayerManager';
import EpisodeInfo from '../../entity/EpisodeInfo';
import DisplayUtils from '../../utils/DisplayUtils';
import Logger from '../../utils/Logger';
import { DEFAULT_DURATION } from '../../utils/TransitionHelper';
import { _AnimeState, AnimeState } from '../../entryability/AnimeState';

// --- 导入 RedPlayer 相关模块 ---
import {
  RedPlayerFactory,
  RedPlayerDataSource,
  RedPlayerXComponentController,
  IMediaPlayer,
  IMediaPlayerStateListener,
  PlayerState,
  RedPlayerConfigBuilder,
  RedPlayerInitManager
} from '@rte-xhs/redplayer';

const DEFAULT_ASPECT = 1.9;

/**
 * 视频播放器，封装 RedPlayer (严格遵循官方文档)
 */
@ComponentV2
export struct RedVideoPlayer {
  // RedPlayer 播放器实例，初始为 null
  private player: IMediaPlayer | null = null;
  @Local videoAspRatio: number = DEFAULT_ASPECT;
  @Local aspRatio: number = DEFAULT_ASPECT;
  @Local videoFit: VideoFit = VideoFit.Contain;
  @Local playStatus: number = PlayerStatus.IDLE;
  @Local playerStatus: number = PlayerStatus.IDLE;
  @Local isFullScreen: boolean = false;
  // XComponent 控制器
  private readonly xComponentController: RedPlayerXComponentController = new RedPlayerXComponentController();
  @Require @Param playerManager: IPlayerManager

  private readonly playerInterface: IPlayer = {
    setDataSource: async (url: string) => {
      if (!this.player) {
        Logger.e('tips', 'RedVideoPlayer is not initialized.');
        return;
      }
      try {
        // Setup RedVideoPlayer source and config
        const DeviceProductModel = _AnimeState.DeviceProductModel
        Logger.i('RedVideoPlayer', `DeviceProductModel: ${DeviceProductModel}, 如果为模拟器运行，则只能软解码`);
        await this.player.setDataSource({
          url: url,
          // ⚠️ 注意：在模拟器上必须强制使用软解码
          useSoftDecoder: DeviceProductModel === 'emulator'
        });
        this.playerManager?.setStatus(PlayerStatus.INITIALIZED);
        Logger.i('RedVideoPlayer', 'DataSource set.');
      } catch (error) {
        Logger.e('fail', `RedVideoPlayer.setDataSource`, error);
      }
    },

    prepare: async () => {
      if (!this.player) return;
      try {
        // Prepare RedVideoPlayer
        await this.player.prepare();
        Logger.i('RedVideoPlayer', 'Player prepared.');
      } catch (error) {
        Logger.e('fail', `RedVideoPlayer.prepare`, error);
      }
    },

    start: async (): Promise<void> => {
      if (!this.player) return;
      try {
        await this.player.start();
        Logger.i('RedVideoPlayer', 'Player started.');
      } catch (error) {
        Logger.e('fail', `RedVideoPlayer.start`, error);
      }
    },

    stop: async (): Promise<void> => {
      if (!this.player) return;
      try {
        await this.player.stop();
        Logger.i('RedVideoPlayer', 'Player stopped.');
      } catch (error) {
        Logger.e('fail', `RedVideoPlayer.stop failed`, error);
      }
    },

    pause: async () => {
      if (!this.player) return;
      try {
        await this.player.pause();
        Logger.i('RedVideoPlayer', 'Player paused.');
      } catch (error) {
        Logger.e('fail', `pause`, error);
      }
    },

    reset: async () => {
      // RedPlayer 没有 reset 方法，需要上层逻辑处理 release 和 recreate
      Logger.w('RedVideoPlayer', 'RedPlayer does not have a reset method.');
      this.playerManager?.setStatus(PlayerStatus.IDLE);
    },

    release: async () => {
      if (this.player) {
        await this.player.release();
        this.player = null;
        Logger.i('RedVideoPlayer', 'Player released.');
      }
    },

    seekTo: async (msec: number) => {
      if (!this.player) return;
      try {
        this.player.seek(msec);
      } catch (error) {
        Logger.e('fail', `seekTo`, error);
      }
    },

    setSpeed: async (speed: media.PlaybackSpeed) => {
      if (!this.player) return;
      try {
        let speedValue: number = 1.0;
        switch (speed) {
          case media.PlaybackSpeed.SPEED_FORWARD_0_75_X: speedValue = 0.75; break;
          case media.PlaybackSpeed.SPEED_FORWARD_1_00_X: speedValue = 1.00; break;
          case media.PlaybackSpeed.SPEED_FORWARD_1_25_X: speedValue = 1.25; break;
          case media.PlaybackSpeed.SPEED_FORWARD_1_75_X: speedValue = 1.75; break;
          case media.PlaybackSpeed.SPEED_FORWARD_2_00_X: speedValue = 2.00; break;
        }
        await this.player.setSpeed(speedValue);
      } catch (error) {
        Logger.e('tips', `setSpeed failed: ${error}`);
      }
    },
  };

  /** RedPlayer 状态监听器，驱动所有状态和UI更新的核心 */
  private readonly redPlayerStateListener: IMediaPlayerStateListener = {
    onPlayerCreated: () => {
      Logger.i('RedVideoPlayer', 'Listener: onPlayerCreated');
      // 播放器实例创建成功，此时 player 对象已可用
    },

    onInitialized: () => {
      Logger.i('RedVideoPlayer', 'Listener: onInitialized');
      this.playerManager?.setStatus(PlayerStatus.INITIALIZED);
    },

    onPrepared: () => {
      Logger.i('RedVideoPlayer', 'Listener: onPrepared');
      this.playerManager?.setStatus(PlayerStatus.PREPARED);
    },

    onStarted: () => {
      Logger.i('RedVideoPlayer', 'Listener: onStarted');
      this.playerManager?.setStatus(PlayerStatus.PLAY);
    },

    onFirstFrameRendered: () => {
      Logger.i('RedVideoPlayer', 'Listener: onFirstFrameRendered');
      // 可以在这里隐藏加载动画等UI操作
    },

    onPositionUpdated: (time: number) => {
      // 更新播放进度
      if (this.player) {
        const totalDuration = this.player.getVideoDuration();
        this.playerManager?.notifyTime(totalDuration, time);
      }
    },

    onPaused: () => {
      Logger.i('RedVideoPlayer', 'Listener: onPaused');
      this.playerManager?.setStatus(PlayerStatus.PAUSE);
    },

    onStopped: () => {
      Logger.i('RedVideoPlayer', 'Listener: onStopped');
      this.playerManager?.setStatus(PlayerStatus.STOP);
    },

    onCompleted: () => {
      Logger.i('RedVideoPlayer', 'Listener: onCompleted');
      this.playerManager?.setStatus(PlayerStatus.DONE);
    },

    onReleased: () => {
      Logger.i('RedVideoPlayer', 'Listener: onReleased');
      // 播放器资源已释放
    },

    onError: (reason: string) => {
      Logger.e('tips', `Listener: onError: ${reason}`);
      this.playerManager?.setStatus(PlayerStatus.ERROR);
    },

    onSeekDone: () => {
      Logger.i('RedVideoPlayer', 'Listener.onSeekDone 拖拽进度条完成');
      // 拖拽进度条完成
    },

    onBufferingStart: () => {
      Logger.i('RedVideoPlayer', 'Listener: onBufferingStart');
      this.playerManager?.notifyBuffering(media.BufferingInfoType.BUFFERING_START, 0);
    },

    onBufferingEnd: () => {
      Logger.i('RedVideoPlayer', 'RedVideoPlayer.Listener: onBufferingEnd');
      this.playerManager?.notifyBuffering(media.BufferingInfoType.BUFFERING_END, 0);
    }
  };


  aboutToAppear() {
    if (!this.playerManager) {
      throw new Error('You must set playerManager firstly!');
    }

    // 创建RedVideoPlayer
    RedPlayerFactory.createMediaPlayer(this.redPlayerStateListener).then((p) => {
      this.player = p;
      Logger.i('RedVideoPlayer', 'RedPlayer instance created.');
      // 实例创建成功后，将接口传递给 playerManager
      this.playerManager.init(this.playerInterface);
      // 添加你自己的业务监听器
      this.playerManager.addListener(this.playerListener);
    }).catch(() => {
      Logger.e('tips', `Failed to create RedPlayer`);
    });
  }

  aboutToDisappear() {
    this.playerManager?.removeListener(this.playerListener);
    this.playerInterface.release();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // STEP-2: Add and config player render view
      XComponent({
        id: this.xComponentController.getSurfaceId(),
        type: this.xComponentController.getSurfaceType(),
        libraryname: this.xComponentController.getLibraryName(),
        controller: this.xComponentController
      })
        .onLoad(() => {
          Logger.i('RedVideoPlayer', 'XComponent 加载中');
          // setSurfaceId to player after XComponent onLoad
          if (this.player) {
            this.player.setSurfaceId(this.xComponentController.getSurfaceId());
          }
        })
        .onDestroy(() => {
          Logger.i('RedVideoPlayer', 'XComponent onDestroy');
        })
        .width(this.isSurfaceHeightDriven() ? undefined : '100%')
        .aspectRatio(this.getSurfaceRatio())
        .height(this.isSurfaceHeightDriven() ? '100%' : undefined)

      VideoPlayerController({ playerManager: this.playerManager })
        .width('100%')
        .height('100%')
    }
    .height(this.isFullScreen ? '100%' : undefined)
    .backgroundColor(Color.Black)
    .clip(true)
    .aspectRatio(this.getOuterAspRatio())
    .width('100%')
  }

  /** 当前画面尺寸模式对应的渲染表面宽高比 */
  private getSurfaceRatio(): number {
    switch (this.videoFit) {
      case VideoFit.Fill:
        return this.getOuterAspRatio();
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
    const outerRatio = this.getOuterAspRatio();
    if (this.videoFit === VideoFit.Cover) {
      return surfaceRatio > outerRatio;
    }
    return surfaceRatio < outerRatio;
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

  /** 业务监听器 */
  private readonly playerListener: PlayerListener = {
    onStatusChanged: (status: number) => {
      this.playerStatus = status;
    },
    onEpisodeChanged: (episodeList: EpisodeInfo[], episodeIndex: number) => {
    },
    onVideoSpeedChanged: (videoSpeed: media.PlaybackSpeed) => {
    },
    onVideoFitChanged: (videoFit: VideoFit) => {
      this.videoFit = videoFit;
    },
    onFullScreenChanged: (isFullScreen: boolean) => {
      this.isFullScreen = isFullScreen;
      animateTo({ duration: DEFAULT_DURATION, curve: Curve.Smooth }, () => {
        this.aspRatio =
          isFullScreen ? DisplayUtils.getRealScreenHWRatio() : Math.min(DEFAULT_ASPECT, this.videoAspRatio);
      });
    },
    onProgressChange: (totalTime: number, currentTime: number) => {
    },
    onBuffering: (type: media.BufferingInfoType, value: number) => {
    },
    onVideoSizeChange: (w: number, h: number): void => {
      // RedPlayer 暂无视频尺寸回调，保持默认比例
    }
  };
}
