import media from '@ohos.multimedia.media';
import IPlayerManager, { PlayerListener, PlayerStatus, VideoFit } from './model/IPlayerManager';
import EpisodeInfo from '../entity/EpisodeInfo';
import VideoTimeUtils from '../utils/VideoTimeUtils';
import Logger from '../utils/Logger';
import { ToastUtil } from '../utils/ToastUtils';
import { sortEpisodesByNumber } from '../utils/SortUtils';
import { appSettings } from '../entryability/Settings';
import { AVVolumePanel } from '@kit.AudioKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit'
import { VolumeAndBrightnessProgress } from '../components/VolumeAndBrightnessProgress';
import { appContinueModel } from '../viewmodel/AppContinueModel';
import { audio } from '@kit.AudioKit';
import { APP_RESUME_PROGRESS_EVENT, PLAYER_SWITCH_EVENT } from '../utils/EventBus';
import emitter from '@ohos.events.emitter';
import { _AnimeState, AnimeState } from '../entryability/AnimeState';
import { CastListener, CastManager } from './CastManager';
import { PiPManager } from './PiPManager';
import { AVCastPicker, AVCastPickerState } from '@kit.AVSessionKit';
import { common } from '@kit.AbilityKit';

interface KeyValue {
  name: string,
  value: number
}

/** 播放设置面板的播放器切换选项（与 SettingsPage 默认播放器保持一致） */
class PlayerOption {
  name: string = ''
  value: string = ''

  constructor(name: string, value: string) {
    this.name = name
    this.value = value
  }
}

const PLAYER_OPTIONS: PlayerOption[] = [
  new PlayerOption('AVPlayer', 'av'),
  new PlayerOption('MPVPlayer', 'mpv'),
  new PlayerOption('IjkPlayer', 'ijk'),
  new PlayerOption('VideoPlayer', 'video'),
  new PlayerOption('RedPlayer', 'red'),
]

interface IArea {
  width: number,
  height: number
}

const VIDEO_SPEED_LIST: KeyValue[] = [
  { name: '0.75', value: 0.75 },
  { name: '1.00', value: 1.00 },
  { name: '1.25', value: 1.25 },
  { name: '1.75', value: 1.75 },
  { name: '2.00', value: 2.00 },
]

const VIDEO_FIT_LIST: KeyValue[] = [
  { name: '适应', value: VideoFit.Contain }, { name: '填充', value: VideoFit.Cover },
  { name: '拉伸', value: VideoFit.Fill }, { name: '16:9', value: VideoFit.Fit_16_9 },
  { name: '4:3', value: VideoFit.Fit_4_3 }, { name: '1:1', value: VideoFit.Fit_1_1 },
]

enum PanelType {

  NONE = 0,
  SPEED = 1,
  EPISODES = 2,
  PLAYER_SETTINGS = 3

}

/**
 * 播放器控制界面
 */
@ComponentV2
export struct VideoPlayerController {

  @Local currentTime: string = "00:00";
  @Local totalTime: string = "00:00";
  @Local progress: number = 0;
  @Local slideEnable: boolean = true;

  @Local sliderAreaWidth: number = 0;
  @Local playerStatus: number = PlayerStatus.IDLE;
  @Local showController: boolean = true;
  @Local title: string = ''
  @Local isFullScreen: boolean = false
  @Local showPanel: boolean = false
  @Local rightPanelScale: number = 0
  @Local rightPanelType: number = PanelType.NONE
  @Local currentSpeed: string = '1.00'
  @Local isLocked: boolean = false
  @Local videoFit: number = VideoFit.Contain
  @Local isLoading: boolean = false
  /** @description 链接解析中（数据源/WebView 解析阶段，驱动加载圈与文案） */
  @Local isParsing: boolean = false
  @Local episodeList: EpisodeInfo[] = []
  @Local episodeIndex: number = 0
  @Require @Param playerManager: IPlayerManager
  private showControllerTimer: number = -1;
  /** @description 默认系统音量 */
  @Local volume: number = 5
  /** @description 是否在屏幕左侧触发手势 */
  private isLeftSideGesture: boolean = false
  /** @description 上一次手势的Y坐标 */
  private lastGestureY: number = 0
  private hidePanelTimer: number = -1;
  /** @description 屏幕亮度 */
  @Local screenBrightness: number = 0
  /** @description 音量和亮度进度条面板是否可见 */
  @Local isVolumeAndBrightnessVisible: boolean = false
  /** @description 播放器控制器的高度和宽度 */
  @Local playerControllerArea: IArea = { width: 0, height: 0 }
  private audioVolumeManager: audio.AudioVolumeManager = audio.getAudioManager().getVolumeManager();

  /** @description 拖动轴向：0未判定 1纵向(音量/亮度) 2横向(进度) */
  private panAxis: number = 0
  /** @description 手势起始坐标 */
  private panStartX: number = 0
  private panStartY: number = 0
  /** @description 横向拖动起始时的播放位置(ms) */
  private seekDragStartPos: number = 0
  /** @description 横向拖动进度预览中（抑制播放器进度回写） */
  @Local isSeekDragging: boolean = false
  /** @description 拖动/长按快退的预览位置(ms) */
  @Local seekPreviewPos: number = 0
  /** @description 拖动进度浮层延迟隐藏计时 */
  private seekOverlayTimer: number = -1
  /** @description 长按左半屏：2x 速率连续快退中 */
  @Local isRewinding: boolean = false
  /** @description 快退目标位置(ms) */
  private rewindTargetPos: number = 0
  /** @description 快退循环计时（每 500ms 后退 1000ms，即 2x 速率） */
  private rewindTimer: number = -1
  /** @description 长按右半屏：3x 倍速播放中 */
  @Local isSpeedBoosting: boolean = false
  /** @description 长按倍速前的原倍率 */
  private speedBeforeBoost: number = 1.0

  /** @description 系统投播中（远端设备播放） */
  @Local isCasting: boolean = false
  /** @description 投播设备名称 */
  @Local castDeviceName: string = ''
  /** @description 投播端播放中 */
  @Local isCastPlaying: boolean = false
  /** @description 投播端最近进度(ms)，断开投播时本端从此处续播 */
  private castLastPos: number = 0
  /** @description 投播端最近媒体时长(ms) */
  private castLastDuration: number = 0
  private castManager: CastManager = new CastManager()

  /** @description 上控制栏高度（控制层可见时为手势屏蔽区） */
  private topBarHeight: number = 0
  /** @description 下控制栏高度（控制层可见时为手势屏蔽区） */
  private bottomBarHeight: number = 0
  /** @description 本次手势起点落在控制栏区域内，屏蔽手势 */
  private gestureBlocked: boolean = false

  private readonly playerListenerVC: PlayerListener = {
    onStatusChanged: (status: number) => {
      this.playerStatus = status
      this.initLoading()
      if (status == PlayerStatus.DONE || status == PlayerStatus.ERROR) {
        // 播放结束/出错时终止手势驱动的快退与倍速，防止计时器残留
        this.stopRewind()
        this.stopSpeedBoost()
        // 出错/结束时自动展示控制层，便于查看状态或切换选集（不自动隐藏）
        if (this.showControllerTimer >= 0) {
          clearTimeout(this.showControllerTimer)
          this.showControllerTimer = -1
        }
        this.showController = true
      }
      if (status === PlayerStatus.PLAY) {
        if (this.isCasting) {
          // 投播中本端因切集解析后自动开播：推送新资源到远端并暂停本端
          this.pushCurrentEpisodeToCast()
          return
        }
        // 播放开始后时长已知，刷新投播会话元数据
        this.refreshCastSession()
        // 播放视频后关闭控制面板
        this.closeController()
      }
      Logger.e('tips', 'PlayerController status=' + status + " playerStatus=" + this.playerStatus)
    },
    onEpisodeChanged: (episodeList: EpisodeInfo[], episodeIndex: number) => {
      this.episodeList = episodeList
      this.episodeIndex = episodeIndex
      this.title = episodeList[episodeIndex].desc
      // 切集后刷新投播会话元数据，保证系统投播面板展示最新剧集
      this.refreshCastSession()
    },
    onVideoSpeedChanged: (videoSpeed: number) => {
    },
    onVideoFitChanged: (videoFit: VideoFit) => {
      this.videoFit = videoFit
    },
    onFullScreenChanged: (isFullScreen: boolean) => {
      console.log('VideoPlayerController #onFullScreenChanged isFullScreen：', isFullScreen)
      this.isFullScreen = isFullScreen
    },
    onVideoSizeChange: (w: number, h: number) => {
    },
    onProgressChange: (totalTime: number, currentTime: number) => {
      if (this.isCasting) {
        // 投播中进度以远端回传为准
        return
      }
      // 持续刷新远端起播位置，发起投播时远端从当前进度开播
      this.castManager.updateProgress(currentTime)
      this.setProgress(totalTime, currentTime)
    },
    onBuffering: (type: media.BufferingInfoType, value: number) => {
      if (this.playerStatus != PlayerStatus.PLAY) {
        this.initLoading()
        return
      }
      if (type == media.BufferingInfoType.BUFFERING_PERCENT) {
        if (value == 100) {
          this.isLoading = false
        } else {
          this.isLoading = true
        }
      } else if (type == media.BufferingInfoType.BUFFERING_START) {
        this.isLoading = true
      } else if (type == media.BufferingInfoType.BUFFERING_END) {
        this.isLoading = false
      }
      Logger.e('tips', 'onBuffering isLoading=' + this.isLoading)
    },
    onParseStateChanged: (parsing: boolean) => {
      // 链接解析阶段（含 WebView 内解析/手动辅助）：显示加载圈，避免界面看似卡死
      this.isParsing = parsing
      this.initLoading()
    }
  }

  private readonly castListener: CastListener = {
    onCastConnected: (deviceName: string) => {
      this.isCasting = true
      this.castDeviceName = deviceName
      this.isCastPlaying = true
      this.castLastPos = 0
      this.castLastDuration = 0
      this.stopRewind()
      this.stopSpeedBoost()
      // 本端暂停，由远端接管播放
      this.playerManager.pause()
      this.closeController()
      ToastUtil.showToast({ message: `已投屏至 ${deviceName}` })
    },
    onCastDisconnected: () => {
      this.isCasting = false
      this.castDeviceName = ''
      this.isCastPlaying = false
      // 本端从投播进度续播
      const resumePos = this.castLastPos
      this.castLastPos = 0
      this.castLastDuration = 0
      if (resumePos > 0) {
        this.playerManager.seekTo(resumePos)
      }
      this.playerManager.start()
    },
    onCastStateChanged: (isPlaying: boolean) => {
      this.isCastPlaying = isPlaying
    },
    onCastProgressChange: (duration: number, position: number) => {
      if (duration > 0) {
        this.castLastDuration = duration
      }
      this.castLastPos = position
      this.setProgress(duration, position)
    },
    onCastEndOfStream: () => {
      // 远端播放结束：自动投播下一集
      if (this.episodeIndex < this.episodeList.length - 1) {
        this.playerManager.selectEpisode(this.episodeIndex + 1)
      }
    }
  }

  aboutToAppear() {
    this.playerStatus = PlayerStatus.IDLE
    this.isLoading = true;
    if (this.playerManager) {
      this.playerStatus = this.playerManager.getStatus()
      this.initLoading()
      this.playerManager.addListener(this.playerListenerVC)
    } else {
      throw new Error('You must set playerManager firstly!')
    }

    this.castManager.setListener(this.castListener)
    // 预创建投播 AVSession（AVCastPicker 组件点击时要求会话已存在）
    this.refreshCastSession()

    // TODO API20 监听系统音频变化
    this.audioVolumeManager.on('streamVolumeChange', audio.StreamUsage.STREAM_USAGE_MUSIC, (streamVolumeEvent: audio.StreamVolumeEvent) => {
      console.info(`audioVolumeManager - StreamUsage of stream: ${streamVolumeEvent.streamUsage} `);
      console.info(`audioVolumeManager - Volume level: ${streamVolumeEvent.volume} `);
      console.info(`audioVolumeManager - Whether to updateUI: ${streamVolumeEvent.updateUi} `);
    });

    // 初始控制层可见，启动 5 秒无操作自动隐藏
    this.closeController()
  }

  aboutToDisappear() {
    this.playerManager.removeListener(this.playerListenerVC)
    if (this.showControllerTimer >= 0) {
      clearTimeout(this.showControllerTimer)
      this.showControllerTimer = -1;
    }

    this.audioVolumeManager.off('streamVolumeChange')
    this.stopRewind()
    this.stopSpeedBoost()
    if (this.seekOverlayTimer >= 0) {
      clearTimeout(this.seekOverlayTimer)
      this.seekOverlayTimer = -1
    }
    this.castManager.destroy()
  }

  onDidBuild(): void {
    // 应用接续 -> 恢复播放
    APP_RESUME_PROGRESS_EVENT.on(() => {
      setTimeout(() => {
        const currentTime = appContinueModel.getCurrentVideoDuration()
        if (currentTime > 0) {
          this.setProgress(this.playerManager.getDuration() as number, currentTime)
        }
      })
    })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 音量和亮度面板
      this.VolumeAndBrightnessBuilder()

      // 拖动进度 / 长按快退快进提示浮层
      this.GestureIndicatorBuilder()

      if (this.showController || this.isLoading) {
        // 控制面板
        this.VideoController()
      }

      this.RightPanel()
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      if (this.showPanel) {
        return
      }
      this.showController = !this.showController;
      if (this.showController) {
        // 控制层出现后启动 5 秒无操作自动隐藏
        this.closeController()
      } else if (this.showControllerTimer >= 0) {
        clearTimeout(this.showControllerTimer)
        this.showControllerTimer = -1
      }
    })
    .onTouch(() => {
      // 控制层可见期间的任意触摸（含子组件）都重置自动隐藏计时
      if (this.showController && !this.showPanel) {
        this.closeController()
      }
    })
    .onAreaChange((oldValue: Area, newValue: Area) => {
      // 记录播放器控制器的大小
      this.playerControllerArea = {
        width: newValue.width as number,
        height: newValue.height as number
      }
    })
    .gesture(
      PanGesture({ direction: PanDirection.All })
        .onActionStart((event: GestureEvent) => {
          // 控制面板锁定/右侧面板打开时禁用手势
          if (this.isLocked || this.showPanel) {
            return
          }
          this.panAxis = 0
          this.panStartX = event.fingerList[0]?.localX ?? 0;
          this.panStartY = event.fingerList[0]?.localY ?? 0;
          // 控制层可见时，起点落在上/下控制栏区域内则屏蔽本次手势（留 10px 容差）
          this.gestureBlocked = this.showController
            && (this.panStartY < this.topBarHeight + 10
              || this.panStartY > this.playerControllerArea.height - this.bottomBarHeight - 10)
        })
        .onActionUpdate((event: GestureEvent) => {
          if (this.isLocked || this.showPanel || this.gestureBlocked) {
            return
          }
          const currentX = event.fingerList[0]?.localX ?? 0;
          const currentY = event.fingerList[0]?.localY ?? 0;

          // 首次有效位移时判定轴向：横向 -> 进度拖动，纵向 -> 音量/亮度
          if (this.panAxis == 0) {
            const deltaX = currentX - this.panStartX
            const deltaY = currentY - this.panStartY
            if (Math.abs(deltaX) < 10 && Math.abs(deltaY) < 10) {
              return
            }
            const duration = this.effectiveDuration()
            if (Math.abs(deltaX) > Math.abs(deltaY) && duration > 0) {
              this.panAxis = 2
              this.isSeekDragging = true
              this.seekDragStartPos = this.isCasting ? this.castLastPos : this.playerManager.getCurrentPosition()
              this.seekPreviewPos = this.seekDragStartPos
              if (this.seekOverlayTimer >= 0) {
                clearTimeout(this.seekOverlayTimer)
                this.seekOverlayTimer = -1
              }
            } else {
              this.panAxis = 1
              // 纵向：判定侧边（左亮度/右音量），以当前Y为基线
              this.isLeftSideGesture = this.panStartX < this.playerControllerArea.width / 2;
              this.lastGestureY = currentY;
              return
            }
          }

          if (this.panAxis == 2) {
            // 横向拖动：滑过整个播放区宽度对应总时长，实时预览目标位置
            const width = this.playerControllerArea.width
            const duration = this.effectiveDuration()
            if (width <= 0 || duration <= 0) {
              return
            }
            let target = this.seekDragStartPos + (currentX - this.panStartX) / width * duration
            target = this.getValidValue(target, 0, duration)
            this.seekPreviewPos = target
            this.progress = target / duration * 100
            this.currentTime = VideoTimeUtils.stringForTime(target)
          } else {
            // 纵向：左半区亮度 / 右半区音量
            this.isVolumeAndBrightnessVisible = true;
            const deltaY = currentY - this.lastGestureY;
            if (this.isLeftSideGesture) {
              // 每滑动100px改变0.1亮度，向上滑动增加亮度
              const brightnessChange = -deltaY / 100;
              let curBrightness = this.screenBrightness + brightnessChange;
              curBrightness = this.getValidValue(curBrightness, 0.0, 1.0);
              this.screenBrightness = curBrightness;
              this.setScreenBrightness(this.screenBrightness);
            } else {
              // 每滑动30px改变1级音量，向上滑动增加音量
              const volumeChange = -deltaY / 30;
              let curVolume = this.volume + volumeChange;
              curVolume = curVolume >= 15.0 ? 15.0 : curVolume;
              curVolume = curVolume <= 0.0 ? 0.0 : curVolume;
              this.volume = curVolume;
            }
            this.lastGestureY = currentY;
          }
        })
        .onActionEnd(() => {
          this.gestureBlocked = false
          if (this.panAxis == 2) {
            // 松手才执行真正的跳转；浮层短暂停留后消失
            if (this.isCasting) {
              this.castLastPos = this.seekPreviewPos
              this.castManager.seek(this.seekPreviewPos)
            } else {
              this.playerManager.seekTo(this.seekPreviewPos)
            }
            if (this.seekOverlayTimer >= 0) {
              clearTimeout(this.seekOverlayTimer)
            }
            this.seekOverlayTimer = setTimeout(() => {
              this.isSeekDragging = false
              this.seekOverlayTimer = -1
            }, 600)
          } else if (this.panAxis == 1) {
            this.setHidePanelTimer();
          }
          this.panAxis = 0
        })
    )
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction((event: GestureEvent) => {
          // 控制面板锁定/右侧面板打开时禁用手势
          if (this.isLocked || this.showPanel) {
            return
          }
          const x = event.fingerList[0]?.localX ?? 0
          const y = event.fingerList[0]?.localY ?? 0
          // 控制层可见时，上/下控制栏区域内不触发长按手势（留 10px 容差）
          if (this.showController
            && (y < this.topBarHeight + 10
              || y > this.playerControllerArea.height - this.bottomBarHeight - 10)) {
            return
          }
          if (x < this.playerControllerArea.width / 2) {
            // 左半屏长按：2x 速率连续快退
            this.startRewind()
          } else {
            // 右半屏长按：临时 3x 倍速播放
            this.startSpeedBoost()
          }
        })
        .onActionEnd(() => {
          this.stopRewind()
          this.stopSpeedBoost()
        })
    )
  }

  @Builder
  VolumeAndBrightnessBuilder() {
    if (this.isVolumeAndBrightnessVisible) {
      VolumeAndBrightnessProgress({
        isVolume: !this.isLeftSideGesture,
        volumeProgress: (this.volume / 15) * 100, // 将音量 0-15 转换为 0-100
        brightnessProgress: this.screenBrightness * 100 // 将亮度 0-1 转换为 0-100
      })
    }

    // 系统音量面板（左侧，基于屏幕全局定位）
    AVVolumePanel({
      volumeLevel: this.volume,
      volumeParameter: {
        // position: {
        //   x: -100,
        //   y: -200
        // }
      }
    })
  }

  @Builder
  GestureIndicatorBuilder() {
    if (this.isSeekDragging || this.isRewinding || this.isSpeedBoosting) {
      Column({ space: 8 }) {
        if (this.isSpeedBoosting) {
          Text('>> 3X 倍速中')
            .fontColor(Color.White)
            .fontSize(16)
        } else {
          if (this.isRewinding) {
            Text('<< 2X 快退中')
              .fontColor(Color.White)
              .fontSize(16)
          } else {
            Text(this.seekDeltaText())
              .fontColor(Color.White)
              .fontSize(16)
          }
          Text(`${VideoTimeUtils.stringForTime(this.seekPreviewPos)} / ${this.totalTime}`)
            .fontColor(Color.White)
            .fontSize(14)
        }
      }
      .padding({ left: 32, right: 32, top: 16, bottom: 16 })
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#80000000')
      .borderRadius(16)
    }
  }

  /** 拖动进度时的偏移描述文本 */
  private seekDeltaText(): string {
    const deltaSec = Math.round((this.seekPreviewPos - this.seekDragStartPos) / 1000)
    if (deltaSec >= 0) {
      return `快进 ${deltaSec} 秒`
    }
    return `快退 ${-deltaSec} 秒`
  }

  /** 长按左半屏：以 2x 速率连续快退（播放器不支持倒放，用循环后退跳转实现） */
  private startRewind() {
    if (this.isCasting) {
      return
    }
    const duration = this.playerManager.getDuration() as number
    if (duration <= 0) {
      return
    }
    this.isRewinding = true
    this.rewindTargetPos = this.playerManager.getCurrentPosition()
    this.rewindTick()
    this.rewindTimer = setInterval((): void => {
      this.rewindTick()
    }, 500)
  }

  private rewindTick() {
    const duration = this.playerManager.getDuration() as number
    this.rewindTargetPos = Math.max(0, this.rewindTargetPos - 1000)
    this.seekPreviewPos = this.rewindTargetPos
    this.currentTime = VideoTimeUtils.stringForTime(this.rewindTargetPos)
    this.progress = duration > 0 ? this.rewindTargetPos / duration * 100 : 0
    this.playerManager.seekTo(this.rewindTargetPos)
  }

  private stopRewind() {
    if (this.rewindTimer >= 0) {
      clearInterval(this.rewindTimer)
      this.rewindTimer = -1
    }
    this.isRewinding = false
  }

  /** 长按右半屏：临时 3x 倍速播放，松手恢复原倍速 */
  private startSpeedBoost() {
    if (this.isCasting || this.playerStatus != PlayerStatus.PLAY) {
      return
    }
    const prev = VIDEO_SPEED_LIST.find((item: KeyValue) => item.name == this.currentSpeed)
    this.speedBeforeBoost = prev ? prev.value : 1.0
    this.isSpeedBoosting = true
    this.playerManager.setSpeed(3.0)
  }

  private stopSpeedBoost() {
    if (!this.isSpeedBoosting) {
      return
    }
    this.isSpeedBoosting = false
    this.playerManager.setSpeed(this.speedBeforeBoost)
  }

  /** 当前是否处于播放中（投播时取远端状态） */
  private isPlayingNow(): boolean {
    return this.isCasting ? this.isCastPlaying : this.playerStatus == PlayerStatus.PLAY
  }

  /** 当前媒体时长（投播时优先取远端回传时长） */
  private effectiveDuration(): number {
    if (this.isCasting && this.castLastDuration > 0) {
      return this.castLastDuration
    }
    return this.playerManager.getDuration() as number
  }

  /** 创建/刷新投播 AVSession 与元数据（AVCastPicker 组件依赖已存在的会话拉起设备面板） */
  private refreshCastSession() {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    this.castManager.prepare(context, this.episodeList, this.episodeIndex, this.effectiveDuration(),
      AnimeState.playingTitle, AnimeState.playingCoverUrl)
  }

  /** AVCastPicker 组件自定义图标（投播中高亮） */
  @Builder
  CastPickerIconBuilder() {
    Image($r('app.media.ic_airplay'))
      .width('100%')
      .height('100%')
      .fillColor(this.isCasting ? $r('app.color.primary_color_accent') : Color.White)
      .objectFit(ImageFit.Contain)
  }

  /** 投播中切集：本端已解析出直链并自动开播，将新资源推送到远端并暂停本端 */
  private pushCurrentEpisodeToCast() {
    this.playerManager.pause()
    this.castLastPos = 0
    this.castLastDuration = 0
    this.castManager.updateEpisodes(this.episodeList, this.episodeIndex)
    this.castManager.castEpisode(this.episodeIndex, 0)
  }

  @Builder VideoController() {
    // 使用 RelativeContainer 绘制控制面板
    RelativeContainer() {
      // 上控制栏区
      Row() {
        // 返回按钮
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(28)
          .fontColor([Color.White])
          .margin({ left: this.isFullScreen ? 20 : 14 })
          .onClick(() => {
            if (this.playerManager.isFullScreen()) {
              this.playerManager.exitFullScreen()
              return
            }
            AnimeState.pageStack.pop(true)
          })
        Text(this.title)
          .fontColor(Color.White)
          .fontSize(14)
          .fontWeight(500)
          .layoutWeight(1)
          .margin({ left: 16 })
          .align(Alignment.Start)
        Blank()
        if (this.isCasting) {
          Text(`投屏中·${this.castDeviceName}`)
            .fontColor($r('app.color.primary_color_accent'))
            .fontSize(12)
            .maxLines(1)
            .margin({ right: 8 })
        }
        // 投屏（投播中点击可切换设备/切回本机）
        AVCastPicker({
          sessionType: 'video',
          customPicker: (): void => {
            this.CastPickerIconBuilder()
          },
          onStateChange: (state: AVCastPickerState): void => {
            if (state == AVCastPickerState.STATE_APPEARING) {
              // 设备选择面板展示期间保持控制层可见：AVCastPicker 组件被移除会导致系统面板关闭
              if (this.showControllerTimer >= 0) {
                clearTimeout(this.showControllerTimer)
                this.showControllerTimer = -1
              }
            } else if (state == AVCastPickerState.STATE_DISAPPEARING) {
              // 面板关闭后恢复 5 秒自动隐藏
              this.closeController()
            }
          }
        })
          .width(24)
          .height(24)
          .margin({ left: this.isFullScreen ? 24 : 16 })
        // 小窗播放（画中画，仅支持的播放器后端显示）
        if (PiPManager.isPlayerSupported(appSettings.default_player)) {
          Image($r("app.media.ic_float_window"))
            .width(28)
            .height(28)
            .fillColor(Color.White)
            .margin({ left: this.isFullScreen ? 24 : 16 })
            .objectFit(ImageFit.Contain)
            .onClick(() => {
              if (this.isCasting) {
                ToastUtil.showToast({ message: '投播中不支持小窗播放' })
                return
              }
              PiPManager.requestPiP()
            })
        }
        // 播放设置
        Image($r("app.media.ic_setting"))
          .width(24)
          .height(24)
          .fillColor(Color.White)
          .margin({ left: this.isFullScreen ? 24 : 16, right: this.isFullScreen ? 24 : 16 })
          .objectFit(ImageFit.Contain)
          .onClick(() => {
            this.showRightPanel(PanelType.PLAYER_SETTINGS)
          })
      }
      .width('100%')
      .padding({ top: this.isFullScreen ? 16 : 4 })
      .visibility(this.isLocked ? Visibility.Hidden : Visibility.Visible)
      .linearGradient({
        angle: 180,
        colors: [['#000000', 0.0], ['#80000000', 0.5], ['#00000000', 1.0]]
      })
      .id('topBar') // 上控制栏ID
      .alignRules({
        top: { anchor: '__container__', align: VerticalAlign.Top } // 顶部与父容器顶部对齐
      })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        // 记录上控制栏高度，控制层可见时作为手势屏蔽区
        this.topBarHeight = newArea.height as number
      })

      // 中部左侧控制区域
      if (this.isFullScreen) {
        // 锁定控制按钮
        Image(this.isLocked ? $r('app.media.ic_lock') : $r('app.media.ic_unlock'))
          .width(44)
          .height(44)
          .padding(12)
          .margin({ left: 16 })
          .backgroundColor('#80000000')
          .fillColor(Color.White)
          .borderRadius(28)
          .onClick(() => {
            this.isLocked = !this.isLocked
          })
          .alignRules({
            left: { anchor: '__container__', align: HorizontalAlign.Start },
            center: { anchor: '__container__', align: VerticalAlign.Center}
          })
      }

      // 中部指示区域
      if (this.isLoading) {
        // 加载圆圈（播放前为线路解析，播放中为缓冲）
        Column({ space: 8 }) {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(Color.White)
          Text(this.isParsing || this.playerStatus !== PlayerStatus.PLAY ? '线路解析中...' : '缓冲中...')
            .fontColor(Color.White)
            .fontSize(14)
        }
        .padding({ left: 32, right: 32, top: 16, bottom: 16 })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#80000000')
        .borderRadius(16)
        .alignRules({
          middle: { anchor: '__container__', align: HorizontalAlign.Center },
          center: { anchor: '__container__', align: VerticalAlign.Center}
        })
      }
      if (!this.isParsing && (this.playerStatus === PlayerStatus.ERROR || this.playerStatus === PlayerStatus.DONE)) {
        // 播放错误 & 重新播放
        Column({space: 8}) {
          Image($r('app.media.ic_refresh'))
            .width(32)
            .height(32)
            .fillColor(Color.White)
            .objectFit(ImageFit.Contain)
          Text(this.playerStatus === PlayerStatus.DONE ? '重新播放' : '出错了...')
            .fontColor(Color.White)
            .fontSize(14)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .alignRules({
          left: { anchor: '__container__', align: HorizontalAlign.Center },
          center: { anchor: '__container__', align: VerticalAlign.Center}
        })
        .onClick(() => {
          this.playerManager.start()
        })
      }

      // 中部右侧控制区域
      if (AnimeState.widthBp > 2) {
        // 退出全屏按钮（大于md时显示）
        Column() {
          SymbolGlyph(this.isFullScreen ? $r('sys.symbol.chevron_left') : $r('sys.symbol.chevron_right'))
            .fontSize(28)
            .fontColor([Color.White])
        }
        .width(39)
        .height(129)
        .borderRadius({
          topLeft: 20,
          bottomLeft: 20
        })
        .linearGradient({
          angle: 180,
          direction: GradientDirection.Right,
          colors: [['#85000000', 0.0], ['#73000000', 0.5]]
        })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .alignRules({
          right: { anchor: '__container__', align: HorizontalAlign.End },
          center: { anchor: '__container__', align: VerticalAlign.Center}
        })
        .onClick(() => {
          if (this.isFullScreen) {
            this.playerManager.exitFullScreen()
          } else {
            this.playerManager.enterFullScreen()
            //  全屏后关闭控制面板
            this.closeController()
          }
        })
      }

      // 下控制栏区域
      Row() {
        Image(this.isPlayingNow() ? $r("app.media.ic_pause") : $r("app.media.ic_play"))
          .width(24)
          .height(24)
          .fillColor(Color.White)
          .margin({ left: this.isFullScreen ? 16 : 12 })
          .objectFit(ImageFit.Contain)
          .onClick(() => {
            if (this.isCasting) {
              if (this.isCastPlaying) {
                this.castManager.pause()
              } else {
                this.castManager.play()
              }
              return
            }
            if (this.playerStatus == PlayerStatus.PLAY) {
              this.playerManager.pause()
            } else {
              this.playerManager.start()
            }
          })

        Text(this.currentTime).fontSize(12).margin({ left: 12, right: 6 }).fontColor(Color.White)
        Slider({
          value: this.progress,
          min: 0,
          max: 100,
          step: 1,
          style: SliderStyle.OutSet
        })
          .layoutWeight(1)
          .blockColor($r('app.color.primary_color_accent'))
          .trackColor(Color.White)
          .trackThickness(2)
          .selectedColor($r('app.color.primary_color'))
          .enabled(this.slideEnable)
          .onChange((value: number, mode: SliderChangeMode) => {
            Logger.e('tips', 'Slider onChange mode=' + mode + ' value=' + value)
            if (mode == SliderChangeMode.End || mode == SliderChangeMode.Click) {
              this.progress = value
              const duration = this.effectiveDuration()
              const seekValue = value / 100 * duration;
              this.setProgress(duration, seekValue)
              if (this.isCasting) {
                this.castLastPos = seekValue
                this.castManager.seek(seekValue)
              } else {
                this.playerManager.seekTo(seekValue);
              }
            }
          })
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            const w = Number(newArea.width);
            if (w > 0) {
              this.sliderAreaWidth = w;
            }
          })
          .onClick((event: ClickEvent) => {
            // 兜底：部分设备点击轨道不触发 onChange 的 Click 模式，按点击位置直接跳转
            this.seekBySliderTap(event.x)
          })
        Text(this.totalTime).fontSize(12).margin({ left: 6, right: 12 }).fontColor(Color.White)

        Text(`${this.currentSpeed}X`)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderWidth(1)
          .borderColor(Color.White)
          .borderRadius(4)
          .margin({ right: 12 })
          .fontSize(12)
          .fontColor(Color.White)
          .onClick(() => {
            this.showRightPanel(PanelType.SPEED)
          })

        if (this.isFullScreen) {
          Text('选集')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderWidth(1)
            .borderColor(Color.White)
            .borderRadius(4)
            .margin({ right: 12 })
            .fontSize(12)
            .fontColor(Color.White)
            .onClick(() => {
              this.showRightPanel(PanelType.EPISODES)
            })
        }
        if (AnimeState.widthBp <= 2) {
          // 全屏按钮（小于等于md时显示）
          Image(!this.isFullScreen ? $r("app.media.ic_fullscreen_enter") : $r("app.media.not_fullscreen"))
            .width(!this.isFullScreen ? 24 : 20)
            .height(!this.isFullScreen ? 24 : 20)
            .fillColor(Color.White)
            .margin({ right: 12 })
            .objectFit(ImageFit.Contain)
            .onClick(() => {
              if (this.isFullScreen) {
                this.playerManager.exitFullScreen()
              } else {
                this.playerManager.enterFullScreen()
              }
            })
        }
      }
      .padding({ top: this.isFullScreen ? 10 : 4, bottom: this.isFullScreen ? 10 : 4 })
      .width('100%')
      .visibility(this.isLocked ? Visibility.Hidden : Visibility.Visible)
      .linearGradient({
        angle: 180,
        colors: [['#00000000', 0.0], ['#80000000', 0.5], ['#ff000000', 1.0]]
      })
      .alignRules({
        bottom: { anchor: '__container__', align: VerticalAlign.Bottom } // 底部对齐父容器底部
      })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        // 记录下控制栏高度，控制层可见时作为手势屏蔽区
        this.bottomBarHeight = newArea.height as number
      })
    }
    .width('100%')
    .height('100%')
    .onAppear(() => {
    })
    .onDisAppear(() => {
      if (this.showControllerTimer >= 0) {
        clearTimeout(this.showControllerTimer)
        this.showControllerTimer = -1
      }
    })

  }

  @Builder RightPanel() {
    Row() {
      if (this.showPanel) {
        if (this.rightPanelType == PanelType.SPEED) {
          this.ChangeSpeedPanel()
        } else if (this.rightPanelType == PanelType.EPISODES) {
          this.EpisodeList()
        } else if (this.rightPanelType == PanelType.PLAYER_SETTINGS) {
          this.PlayerSettings()
        }
      }
    }
    .justifyContent(FlexAlign.End)
    .hitTestBehavior(this.showPanel ? HitTestMode.Default : HitTestMode.None)
    .width('100%')
    .height('100%')
    .onClick(() => {
      this.hideRightPanel()
    })
  }

  @Builder ChangeSpeedPanel() {
    Scroll() {
      Column({ space: this.isFullScreen ? 16 : 8 }) {
        Text('倍速')
          .alignSelf(ItemAlign.Start)
          .fontSize(this.isFullScreen ? 16 : 13)
          .fontColor(Color.White)
        ForEach(VIDEO_SPEED_LIST, (item: KeyValue) => {
          Text(`${item.name}X`)
            .padding(8)
            .fontSize(this.isFullScreen ? 12 : 10)
            .fontColor(Color.White)
            .width('100%')
            .backgroundColor(this.currentSpeed == item.name ? $r('app.color.primary_color_accent') : Color.Transparent)
            .borderRadius(6)
            .borderColor(Color.White)
            .borderWidth(this.currentSpeed == item.name ? 0 : 1)
            .onClick(() => {
              this.currentSpeed = item.name
              if (this.isCasting) {
                this.castManager.setSpeed(item.value)
              } else {
                this.playerManager.setSpeed(item.value)
              }
            })
        })

      }
      .padding(this.isFullScreen ? 16 : 8)
      .width('100%')
      .constraintSize({
        minHeight: '100%'
      })
    }
    .edgeEffect(EdgeEffect.Spring)
    .height('100%')
    .width(this.isFullScreen ? '30%' : '45%')
    .scale({ x: this.rightPanelScale, centerX: '100%' })
    .backgroundColor('#80000000')
  }

  @Builder EpisodeList() {
    Scroll() {
      Column({ space: this.isFullScreen ? 16 : 8 }) {
        Row() {
          Text('选集')
            .fontSize(this.isFullScreen ? 16 : 14)
            .fontColor(Color.White)
          Text(appSettings.episodes_order === 'desc' ? '倒序' : '正序')
            .margin({ left: 24 })
            .fontSize(this.isFullScreen ? 12 : 10)
            .fontColor(Color.White)
            .onClick(() => {
              if (appSettings.episodes_order === 'desc') {
                appSettings.episodes_order = 'asc'
              } else {
                appSettings.episodes_order = 'desc'
              }
            })
        }
        .width('100%')
        Flex({ alignItems: ItemAlign.Start, justifyContent: FlexAlign.Start, wrap: FlexWrap.Wrap }) {
          ForEach(sortEpisodesByNumber(this.episodeList, appSettings.episodes_order), (episode: EpisodeInfo) => {
            Text(episode.title)
              .padding(8)
              .fontSize(this.isFullScreen ? 14 : 12)
              .fontColor(Color.White)
              .maxLines(1)
              .constraintSize({
                minWidth: '50%'
              })
              .backgroundColor(this.episodeList[this.episodeIndex] === episode
                ? $r('app.color.primary_color_accent') : Color.Transparent)
              .borderRadius(6)
              .borderColor(Color.White)
              .borderWidth(0)
              .onClick(() => {
                // 显示顺序可能被排序打乱，按剧集对象映射回规范索引
                const canonicalIdx = this.episodeList.indexOf(episode)
                if (canonicalIdx < 0 || canonicalIdx == this.episodeIndex) {
                  return
                }
                this.playerManager.selectEpisode(canonicalIdx)
                this.hideRightPanel()
              })
          })
        }
        .width('100%')
      }
      .padding(this.isFullScreen ? 16 : 8)
      .width('100%')
      .constraintSize({
        minHeight: '100%'
      })
    }
    .edgeEffect(EdgeEffect.Spring)
    .height('100%')
    .width(this.isFullScreen ? '30%' : '45%')
    .scale({ x: this.rightPanelScale, centerX: '100%' })
    .backgroundColor('#80000000')
  }

  @Builder PlayerSettings() {
    Scroll() {
      Column({ space: this.isFullScreen ? 16 : 8 }) {

        Text('播放器')
          .alignSelf(ItemAlign.Start)
          .fontSize(this.isFullScreen ? 16 : 13)
          .fontColor(Color.White)

        Flex({ alignItems: ItemAlign.Start, justifyContent: FlexAlign.SpaceAround, wrap: FlexWrap.Wrap }) {
          ForEach(PLAYER_OPTIONS, (item: PlayerOption) => {
            Text(item.name)
              .textAlign(TextAlign.Center)
              .fontColor(Color.White)
              .fontSize(this.isFullScreen ? 14 : 11)
              .padding(6)
              .backgroundColor((appSettings.default_player == item.value)
                ? $r('app.color.primary_color_accent') : Color.Transparent)
              .borderRadius(4)
              .margin({ bottom: 8 })
              .width('33%')
              .maxLines(1)
              .onClick(() => {
                if (appSettings.default_player == item.value) {
                  return
                }
                // 记录当前进度，切换后从该处续播
                const resumePos = this.playerManager.getCurrentPosition()
                appSettings.default_player = item.value
                const eventData: emitter.EventData = { data: { 'resumePos': resumePos } }
                PLAYER_SWITCH_EVENT.emit(emitter.EventPriority.LOW, eventData)
                // 关闭面板展示加载状态
                this.hideRightPanel()
              })
          })
        }
        .width('100%')

        Text('画面尺寸')
          .alignSelf(ItemAlign.Start)
          .fontSize(this.isFullScreen ? 16 : 13)
          .fontColor(Color.White)

        Flex({ alignItems: ItemAlign.Start, justifyContent: FlexAlign.SpaceAround, wrap: FlexWrap.Wrap }) {
          ForEach(VIDEO_FIT_LIST, (item: KeyValue) => {
            Text(item.name)
              .textAlign(TextAlign.Center)
              .fontColor(Color.White)
              .fontSize(this.isFullScreen ? 14 : 11)
              .padding(6)
              .backgroundColor((this.videoFit == item.value) ? $r('app.color.primary_color_accent') : Color.Transparent)
              .borderRadius(4)
              .margin({ bottom: 8 })
              .width('33%')
                //              .constraintSize({
                //                minWidth: '33%'
                //              })
              .maxLines(1)
              .onClick(() => {
                this.playerManager.setVideoFit(item.value)
              })
          })
        }
        .width('100%')

        Row() {
          Column() {
            Text('自动全屏')
              .fontSize(this.isFullScreen ? 16 : 13)
              .fontColor(Color.White)
            Text('手机横屏时自动进入全屏')
              .fontSize(this.isFullScreen ? 12 : 10)
              .fontColor('#99ffffff')
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)

          Blank()

          Toggle({ type: ToggleType.Switch, isOn: appSettings.auto_sensor_rotate })
            .onChange((isOn: boolean) => {
              appSettings.auto_sensor_rotate = isOn
              this.applyAutoRotateOrientation(isOn)
            })
        }
        .width('100%')

        if (PiPManager.isPlayerSupported(appSettings.default_player)) {
          Row() {
            Column() {
              Text('退出播放页自动小窗')
                .fontSize(this.isFullScreen ? 16 : 13)
                .fontColor(Color.White)
              Text('返回、导航、后台时自动进入画中画')
                .fontSize(this.isFullScreen ? 12 : 10)
                .fontColor('#99ffffff')
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)

            Blank()

            Toggle({ type: ToggleType.Switch, isOn: appSettings.auto_pip_on_exit })
              .onChange((isOn: boolean) => {
                appSettings.auto_pip_on_exit = isOn
              })
          }
          .width('100%')
        }

      }
      .padding(this.isFullScreen ? 16 : 8)
      .width('100%')
      .constraintSize({
        minHeight: '100%'
      })
    }
    .edgeEffect(EdgeEffect.Spring)
    .height('100%')
    .width(this.isFullScreen ? '30%' : '45%')
    .scale({ x: this.rightPanelScale, centerX: '100%' })
    .backgroundColor('#80000000')
  }

  /**
   * 自动全屏开关联动窗口方向：
   * 开启 → 跟随传感器旋转（横屏时由媒体查询自动触发全屏）；
   * 关闭 → 视频页锁定竖屏，旋转手机不再改变布局
   */
  private applyAutoRotateOrientation(isOn: boolean): void {
    if (this.playerManager.isFullScreen()) {
      return
    }
    const windowClass = _AnimeState.window
    if (!windowClass) {
      return
    }
    const orientation: window.Orientation = isOn
      ? window.Orientation.AUTO_ROTATION_RESTRICTED
      : window.Orientation.PORTRAIT
    windowClass.setPreferredOrientation(orientation).catch((err: BusinessError) => {
      Logger.e('fail', `applyAutoRotateOrientation 设置窗口方向 code=${err.code}`, err)
    })
  }

  private closeController() {
    console.log(`视频已经播放，控制面板即将关闭`)
    // 先清掉旧计时，避免多个计时器并存导致提前隐藏
    if (this.showControllerTimer >= 0) {
      clearTimeout(this.showControllerTimer)
    }
    this.showControllerTimer = setTimeout(() => {
      // 5s内无操作后隐藏
      this.showController = false
      this.showControllerTimer = -1
    }, 5000)
  }

  private showRightPanel(type: number) {
    this.rightPanelType = type
    this.rightPanelScale = 0
    this.showPanel = true
    this.showController = false
    if (this.showControllerTimer >= 0) {
      clearTimeout(this.showControllerTimer)
      this.showControllerTimer = -1
    }
    ToastUtil.animateTo(
      {
        duration: 320, // 动画时长
        curve: Curve.Ease,
        iterations: 1, // 播放次数
        playMode: PlayMode.Normal, // 动画模式
        onFinish: () => {
        }
      },
      () => {
        this.rightPanelScale = 1
      }
    )
  }

  private hideRightPanel() {
    ToastUtil.animateTo(
      {
        duration: 320, // 动画时长
        curve: Curve.Ease, // 动画曲线
        iterations: 1, // 播放次数
        playMode: PlayMode.Normal, // 动画模式
        onFinish: () => {
          this.showPanel = false
          this.showController = true
          this.rightPanelType = PanelType.NONE
          // 控制层重新出现，启动 5 秒无操作自动隐藏
          this.closeController()
        }
      },
      () => {
        this.rightPanelScale = 0
      }
    )
  }

  private setProgress(duration: number, position: number) {
    // 拖动进度/长按快退预览期间不回写播放器进度，避免与预览位置互相跳动
    if (this.isSeekDragging || this.isRewinding) {
      return
    }
    let pos = 0;
    if (duration > 0) {
      this.slideEnable = true;
      let curPercent = position / duration;
      pos = curPercent * 100;
      this.progress = pos;
    }
    Logger.e('tips', "setProgress position:" + position + ",duration:" + duration + ",progressValue:" + pos);
    this.totalTime = VideoTimeUtils.stringForTime(duration);
    if (position > duration) {
      position = duration;
    }
    this.currentTime = VideoTimeUtils.stringForTime(position);
  }

  /** 点击进度条任意位置直接跳转（ClickEvent.x 为相对组件左边缘的局部坐标） */
  private seekBySliderTap(localX: number): void {
    const width = this.sliderAreaWidth;
    const duration = this.effectiveDuration();
    if (width <= 0 || duration <= 0) {
      return;
    }
    const ratio = Math.min(1, Math.max(0, localX / width));
    const seekValue = ratio * duration;
    Logger.e('tips', 'seekBySliderTap x=' + localX + ' width=' + width + ' seekValue=' + seekValue);
    this.progress = ratio * 100;
    this.setProgress(duration, seekValue);
    if (this.isCasting) {
      this.castLastPos = seekValue;
      this.castManager.seek(seekValue);
    } else {
      this.playerManager.seekTo(seekValue);
    }
  }

  private initLoading() {
    this.isLoading = this.isParsing
    || this.playerStatus == PlayerStatus.IDLE
    || this.playerStatus == PlayerStatus.INITIALIZED
    || this.playerStatus == PlayerStatus.PREPARED
  }

  /** @description 设置定时器隐藏面板 */
  private setHidePanelTimer(): void {
    // 清除之前的定时器
    if (this.hidePanelTimer >= 0) {
      clearTimeout(this.hidePanelTimer);
    }
    // 1秒后隐藏面板
    this.hidePanelTimer = setTimeout(() => {
      this.isVolumeAndBrightnessVisible = false;
    }, 1000);
  }

  /**
   * @description 获取有效的值
   * @param inputValue 输入值
   * @param minValue 最小值
   * @param maxValue 最大值
   * @returns 有效值
   */
  private getValidValue(inputValue: number, minValue: number, maxValue: number): number {
    inputValue = inputValue >= maxValue ? maxValue : inputValue;
    inputValue = inputValue <= minValue ? minValue : inputValue;
    return inputValue;
  }

  /**
   * @description 设置屏幕亮度
   * @param brightness 亮度值
   */
  private setScreenBrightness(brightness: number) {
    try {
      let mainWin: window.Window = _AnimeState.window!;
      mainWin.setWindowBrightness(brightness, (err: BusinessError) => {
        if (err.code) {
          Logger.e('fail', 'set the brightness', err);
          return;
        }
      });
    } catch (exception) {
      Logger.e('fail', 'getMainWindowSync', exception);
    }
  }

  /**
   * @description 监听显示音量面板
   */
  @Monitor('volume')
  private showVolume() {
    this.isVolumeAndBrightnessVisible = true;
    this.setHidePanelTimer()
  }
}