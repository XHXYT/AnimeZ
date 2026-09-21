import media from '@ohos.multimedia.media';
import { IPlayer } from '../model/IPlayer';
import { VideoPlayerController } from '../VideoPlayerController';
import IPlayerManager, { PlayerListener, PlayerStatus, VideoFit } from '../model/IPlayerManager';
import EpisodeInfo from '../../entity/EpisodeInfo';
import DisplayUtils from '../../utils/DisplayUtils';
import Logger from '../../utils/Logger';
import { DEFAULT_DURATION } from '../../utils/TransitionHelper';
import { _AnimeState, AnimeState } from '../../entryability/AnimeState';

// --- 导入 mpv-arkts 相关模块 ---
import { Player, PlayerSurface, Media } from '@mpv-ohos/mpv-arkts';

const DEFAULT_ASPECT = 1.9;

/**
 * 视频播放器，封装 @mpv-ohos/mpv-arkts
 */
@ComponentV2
export struct MpvVideoPlayer {
  private mpvPlayer: Player = new Player();
  private destroyed: boolean = false;
  @Local videoAspRatio: number = DEFAULT_ASPECT;
  @Local aspRatio: number = DEFAULT_ASPECT;
  @Local videoFit: VideoFit = VideoFit.Contain;
  @Local isFullScreen: boolean = false;
  @Require @Param playerManager: IPlayerManager
  /** 播放器区域为全高（左右分栏等）时撑满容器，控制层可利用上下黑边空间 */
  @Param fillHeight: boolean = false;
  /** 外层容器实测宽高比（onAreaChange 测量，0 表示未测量） */
  @Local containerRatio: number = 0;

  private readonly playerInterface: IPlayer = {
    setDataSource: async (url: string): Promise<void> => {
      if (this.destroyed) {
        return;
      }
      try {
        // 加载媒体但不立即播放，交给上层状态机驱动
        this.mpvPlayer.open(new Media(url), false);
        this.playerManager?.setStatus(PlayerStatus.INITIALIZED);
        Logger.i('MpvVideoPlayer', 'DataSource set.');
      } catch (error) {
        Logger.e('fail', `MpvVideoPlayer.setDataSource`, error);
        this.playerManager?.setStatus(PlayerStatus.ERROR);
      }
    },

    prepare: async (): Promise<void> => {
      // mpv 没有独立的 prepare 阶段，加载后直接进入 PREPARED
      this.playerManager?.setStatus(PlayerStatus.PREPARED);
    },

    start: async (): Promise<void> => {
      if (this.destroyed) {
        return;
      }
      try {
        this.mpvPlayer.play();
      } catch (error) {
        Logger.e('fail', `MpvVideoPlayer.start`, error);
      }
    },

    stop: async (): Promise<void> => {
      if (this.destroyed) {
        return;
      }
      try {
        this.mpvPlayer.stop();
        Logger.i('MpvVideoPlayer', 'Player stopped.');
      } catch (error) {
        Logger.e('fail', `MpvVideoPlayer.stop`, error);
      }
    },

    pause: async (): Promise<void> => {
      if (this.destroyed) {
        return;
      }
      try {
        this.mpvPlayer.pause();
      } catch (error) {
        Logger.e('fail', `MpvVideoPlayer.pause`, error);
      }
    },

    reset: async (): Promise<void> => {
      // mpv 没有 reset 方法，stop 会清空当前播放列表，重新 open 即可
      if (this.destroyed) {
        return;
      }
      try {
        this.mpvPlayer.stop();
      } catch (error) {
        Logger.e('fail', `MpvVideoPlayer.reset`, error);
      }
      this.playerManager?.setStatus(PlayerStatus.IDLE);
    },

    release: async (): Promise<void> => {
      if (this.destroyed) {
        return;
      }
      this.destroyed = true;
      try {
        this.mpvPlayer.stream.destroy();
        this.mpvPlayer.destroy();
        Logger.i('MpvVideoPlayer', 'Player released.');
      } catch (error) {
        Logger.e('fail', `MpvVideoPlayer.release`, error);
      }
    },

    seekTo: async (msec: number): Promise<void> => {
      if (this.destroyed) {
        return;
      }
      try {
        // mpv 的 seek 单位是秒
        this.mpvPlayer.seek(msec / 1000);
      } catch (error) {
        Logger.e('fail', `MpvVideoPlayer.seekTo`, error);
      }
    },

    setSpeed: async (speed: media.PlaybackSpeed): Promise<void> => {
      if (this.destroyed) {
        return;
      }
      let speedValue: number = 1.0;
      switch (speed) {
        case media.PlaybackSpeed.SPEED_FORWARD_0_75_X: speedValue = 0.75; break;
        case media.PlaybackSpeed.SPEED_FORWARD_1_00_X: speedValue = 1.00; break;
        case media.PlaybackSpeed.SPEED_FORWARD_1_25_X: speedValue = 1.25; break;
        case media.PlaybackSpeed.SPEED_FORWARD_1_75_X: speedValue = 1.75; break;
        case media.PlaybackSpeed.SPEED_FORWARD_2_00_X: speedValue = 2.00; break;
      }
      try {
        this.mpvPlayer.setSpeed(speedValue);
      } catch (error) {
        Logger.e('fail', `MpvVideoPlayer.setSpeed`, error);
      }
    },
  };

  /** 订阅 mpv 事件流，驱动状态机和 UI 更新 */
  private initMpvListeners(): void {
    // 播放/暂停（播放结束时的暂停不回传，避免覆盖 DONE 状态；
    // 仅在管理器处于 PLAY 时上报 PAUSE，防止换集 stop 产生的迟到事件污染状态）
    this.mpvPlayer.stream.playing.listen((playing: boolean) => {
      if (this.destroyed) {
        return;
      }
      if (playing) {
        this.playerManager?.setStatus(PlayerStatus.PLAY);
      } else if (this.playerManager?.getStatus() === PlayerStatus.PLAY && !this.mpvPlayer.state.eof) {
        this.playerManager?.setStatus(PlayerStatus.PAUSE);
      }
    });

    // 播放完成
    this.mpvPlayer.stream.eof.listen((eof: boolean) => {
      if (this.destroyed) {
        return;
      }
      if (eof) {
        this.playerManager?.setStatus(PlayerStatus.DONE);
      }
    });

    // mpv 内部错误
    this.mpvPlayer.stream.error.listen((msg: string) => {
      if (this.destroyed) {
        return;
      }
      Logger.e('fail', `mpv error: ${msg}`);
      this.playerManager?.setStatus(PlayerStatus.ERROR);
    });

    // 进度（mpv 单位为秒，管理器使用毫秒）
    this.mpvPlayer.stream.position.listen((position: number) => {
      if (this.destroyed) {
        return;
      }
      const durationMs = Math.round(this.mpvPlayer.state.duration * 1000);
      this.playerManager?.notifyTime(durationMs, Math.round(position * 1000));
    });

    // 缓冲开始/结束
    this.mpvPlayer.stream.buffering.listen((buffering: boolean) => {
      if (this.destroyed) {
        return;
      }
      const type = buffering ? media.BufferingInfoType.BUFFERING_START : media.BufferingInfoType.BUFFERING_END;
      this.playerManager?.notifyBuffering(type, 0);
    });

    // 缓冲百分比
    this.mpvPlayer.stream.bufferingPercentage.listen((value: number) => {
      if (this.destroyed) {
        return;
      }
      this.playerManager?.notifyBuffering(media.BufferingInfoType.BUFFERING_PERCENT, value);
    });

    // 视频尺寸（dw/dh 为宽高比修正后的尺寸）
    this.mpvPlayer.stream.videoParams.listen((params) => {
      if (this.destroyed) {
        return;
      }
      if (params.dw > 0 && params.dh > 0) {
        this.videoAspRatio = params.dw / params.dh;
        this.playerManager?.onVideoSizeChanged(params.w, params.h);
      }
    });
  }

  aboutToAppear() {
    if (!this.playerManager) {
      throw new Error('You must set playerManager firstly!');
    }
    Logger.i('MpvVideoPlayer', `DeviceProductModel: ${_AnimeState.DeviceProductModel}`);
    this.initMpvListeners();
    this.playerManager.init(this.playerInterface);
    this.playerManager.addListener(this.playerListener);
  }

  aboutToDisappear() {
    this.playerManager?.removeListener(this.playerListener);
    this.playerInterface.release();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      PlayerSurface({ player: this.mpvPlayer })
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

  /** 业务监听器 */
  private readonly playerListener: PlayerListener = {
    onStatusChanged: (status: number) => {
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
      if (w > 0 && h > 0 && !this.isFullScreen) {
        animateTo({ duration: DEFAULT_DURATION, curve: Curve.Smooth }, () => {
          this.aspRatio = Math.min(DEFAULT_ASPECT, this.videoAspRatio);
        });
      }
    }
  };
}
