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
import { APP_RESUME_PROGRESS_EVENT, PLAYER_SETTINGS_EVENT, PLAYER_SWITCH_EVENT } from '../utils/EventBus';
import emitter from '@ohos.events.emitter';
import { _AnimeState, AnimeState } from '../entryability/AnimeState';
import { CastListener, CastManager } from './CastManager';
import { PiPManager } from './PiPManager';
import { AVCastPicker, AVCastPickerState } from '@kit.AVSessionKit';
import { common } from '@kit.AbilityKit';
import { DanmakuLayer } from '../danmaku/DanmakuLayer';
import { DanmakuController } from '../danmaku/DanmakuController';
import { DanmakuLoadResult, DanmakuLoadStatus, DandanplayApi } from '../danmaku/DandanplayApi';
import { DandanplayAnime, DandanplayEpisode } from '../danmaku/DandanplayModels';
import { MenuOption, makeSeekSecondsOptions } from '../entity/CusItemInfo';
import { SHORTCUT_DEFS, ShortcutDef, PlayerShortcuts, findActionByKeyCode } from '../utils/PlayerShortcuts';

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

/** 快捷手势说明条目 */
class GestureGuideItem {
  name: string = ''
  desc: string = ''

  constructor(name: string, desc: string) {
    this.name = name
    this.desc = desc
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

/** 弹幕显示区域选项 */
const DANMAKU_AREA_LIST: KeyValue[] = [
  { name: '全部', value: 1.0 },
  { name: '3/4', value: 0.75 },
  { name: '半屏', value: 0.5 },
  { name: '1/4', value: 0.25 },
]

enum PanelType {

  NONE = 0,
  SPEED = 1,
  EPISODES = 2,
  PLAYER_SETTINGS = 3,
  GESTURE_HELP = 4,
  DANMAKU = 5

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
  /** @description 本次会话是否调整过窗口亮度（退出播放界面时据此恢复系统默认亮度） */
  private brightnessTouched: boolean = false
  /** @description 音量和亮度进度条面板是否可见 */
  @Local isVolumeAndBrightnessVisible: boolean = false
  /** @description 播放器控制器的高度和宽度 */
  @Local playerControllerArea: IArea = { width: 0, height: 0 }
  private audioVolumeManager: audio.AudioVolumeManager = audio.getAudioManager().getVolumeManager();

  /** @description 弹幕控制中枢 */
  private danmakuCtrl: DanmakuController = new DanmakuController()
  /** @description 当前剧集弹幕是否已成功加载（驱动弹幕层挂载） */
  @Local danmakuLoaded: boolean = false
  /** @description 切换弹幕对话框是否可见 */
  @Local danmakuSwitchDialogVisible: boolean = false
  /** @description 切换弹幕搜索关键词 */
  @Local danmakuSwitchKeyword: string = ''
  /** @description 切换弹幕搜索结果（动画列表） */
  @Local danmakuSwitchAnimes: DandanplayAnime[] = []
  /** @description 切换弹幕当前选中的动画（null 表示还在动画列表阶段） */
  @Local danmakuSwitchSelectedAnime: DandanplayAnime | null = null
  /** @description 切换弹幕搜索/加载中 */
  @Local danmakuSwitchSearching: boolean = false

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

  /** @description 键盘按住中的按键（防按住自动重复触发） */
  private heldKeyCodes: Set<number> = new Set<number>()

  private readonly playerListenerVC: PlayerListener = {
    onStatusChanged: (status: number) => {
      this.playerStatus = status
      this.initLoading()
      if (status == PlayerStatus.DONE || status == PlayerStatus.ERROR) {
        // 播放结束/出错时终止手势驱动的快退与倍速，防止计时器残留
        this.stopRewind()
        this.stopSpeedBoost()
        this.danmakuCtrl.onPause()
        // 同步停止状态到系统播控中心
        if (!this.isCasting) {
          this.castManager.updatePlaybackState(false, this.playerManager.getCurrentPosition(), this.currentSpeedValue())
        }
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
          this.closeController()
          return
        }
        // 播放开始后时长已知，刷新投播会话元数据
        this.refreshCastSession()
        // 同步播放状态到系统播控中心
        this.castManager.updatePlaybackState(true, this.playerManager.getCurrentPosition(), this.currentSpeedValue())
        // 弹幕时钟随播放启动
        this.danmakuCtrl.onPlay(this.playerManager.getCurrentPosition())
        // 播放视频后关闭控制面板
        this.closeController()
      }
      if (status === PlayerStatus.PAUSE) {
        // 弹幕时钟随播放暂停
        this.danmakuCtrl.onPause()
        if (!this.isCasting) {
          // 同步暂停状态到系统播控中心
          this.castManager.updatePlaybackState(false, this.playerManager.getCurrentPosition(), this.currentSpeedValue())
        }
        // 本端暂停时固定展示控制层与中部暂停标识（投播中远端仍在播放时除外）
        if (!(this.isCasting && this.isCastPlaying)) {
          if (this.showControllerTimer >= 0) {
            clearTimeout(this.showControllerTimer)
            this.showControllerTimer = -1
          }
          this.showController = true
        }
      }
      Logger.e('tips', 'PlayerController status=' + status + " playerStatus=" + this.playerStatus)
    },
    onEpisodeChanged: (episodeList: EpisodeInfo[], episodeIndex: number) => {
      this.episodeList = episodeList
      this.episodeIndex = episodeIndex
      this.title = episodeList[episodeIndex].desc
      // 切集后刷新投播会话元数据，保证系统投播面板展示最新剧集
      this.refreshCastSession()
      // 切集后重新匹配加载弹幕
      this.loadDanmaku()
    },
    onVideoSpeedChanged: (videoSpeed: number) => {
    },
    onVideoFitChanged: (videoFit: VideoFit) => {
      this.videoFit = videoFit
    },
    onFullScreenChanged: (isFullScreen: boolean) => {
      console.log('VideoPlayerController #onFullScreenChanged isFullScreen：', isFullScreen)
      this.isFullScreen = isFullScreen
      // 全屏切换后重新持有焦点，保证键盘快捷键可用
      this.requestPlayerFocus()
    },
    onVideoSizeChange: (w: number, h: number) => {
    },
    onProgressChange: (totalTime: number, currentTime: number) => {
      if (this.isCasting) {
        // 投播中进度以远端回传为准
        return
      }
      // 持续刷新远端起播位置，发起投播时远端从当前进度开播；并节流同步播控中心进度
      this.castManager.updateProgress(currentTime, this.currentSpeedValue())
      this.setProgress(totalTime, currentTime)
      // 弹幕进度漂移校正（内部节流）
      this.danmakuCtrl.onProgress(currentTime)
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
        // 解析期间到达的缓冲结束不熄灭加载圈（解析态由 notifyParseState 收口）
        this.isLoading = this.isParsing
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
      // 状态回调可能随进度上报重复触发，仅处理真实的状态切换
      if (this.isCastPlaying === isPlaying) {
        return
      }
      this.isCastPlaying = isPlaying
      if (isPlaying) {
        // 远端继续播放：恢复控制层 5 秒自动隐藏
        this.closeController()
      } else {
        // 远端暂停：固定展示控制层与中部暂停标识
        if (this.showControllerTimer >= 0) {
          clearTimeout(this.showControllerTimer)
          this.showControllerTimer = -1
        }
        this.showController = true
      }
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
    },
    onControlPlay: () => {
      if (this.isCasting) {
        this.castManager.play()
        return
      }
      if (this.playerStatus == PlayerStatus.PAUSE) {
        this.playerManager.start()
      }
    },
    onControlPause: () => {
      if (this.isCasting) {
        this.castManager.pause()
        return
      }
      if (this.playerStatus == PlayerStatus.PLAY) {
        this.playerManager.pause()
      }
    },
    onControlSeek: (position: number) => {
      if (this.isCasting) {
        this.castLastPos = position
        this.castManager.seek(position)
        return
      }
      this.playerManager.seekTo(position)
    },
    onControlNext: () => {
      if (this.episodeIndex < this.episodeList.length - 1) {
        this.playerManager.selectEpisode(this.episodeIndex + 1)
      }
    },
    onControlPrevious: () => {
      if (this.episodeIndex > 0) {
        this.playerManager.selectEpisode(this.episodeIndex - 1)
      }
    }
  }

  aboutToAppear() {
    this.playerStatus = PlayerStatus.IDLE
    this.isLoading = true;
    if (this.playerManager) {
      this.playerStatus = this.playerManager.getStatus()
      // 页面挂载可能晚于解析开始（详情加载期间 state=LOADING 不构建播放区，控制器会错过
      // notifyParseState(true)）：主动补同步解析态，保证解析期间加载圈立即可见
      this.isParsing = this.playerManager.isParsing()
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
    this.danmakuCtrl.release()
    if (this.seekOverlayTimer >= 0) {
      clearTimeout(this.seekOverlayTimer)
      this.seekOverlayTimer = -1
    }
    // 退出播放界面恢复系统默认亮度（-1 表示窗口亮度跟随系统）
    if (this.brightnessTouched) {
      this.setScreenBrightness(-1)
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
      // 弹幕层（视频之上、控制层之下，触摸穿透）
      if (appSettings.danmaku_enabled && this.danmakuLoaded) {
        DanmakuLayer({ controller: this.danmakuCtrl })
      }

      // 音量和亮度面板
      this.VolumeAndBrightnessBuilder()

      // 拖动进度 / 长按快退快进提示浮层
      this.GestureIndicatorBuilder()

      if (this.showController || this.isLoading) {
        // 控制面板
        this.VideoController()
      }

      // 暂停时中部暂停标识（点击恢复播放）
      this.CenterPauseMarkBuilder()

      this.RightPanel()

      // 切换弹幕对话框：遮罩 + 居中卡片
      if (this.danmakuSwitchDialogVisible) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#99000000')
          .onClick(() => {
            this.closeDanmakuSwitchDialog()
          })
      }
      if (this.danmakuSwitchDialogVisible) {
        this.DanmakuSwitchDialogCard()
      }
    }
    .width('100%')
    .height('100%')
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        TapGesture({ count: 2 })
          .onAction((event: GestureEvent) => {
            // 双击快进/快退/播放暂停：锁定或右侧面板打开时禁用
            if (this.isLocked || this.showPanel) {
              return
            }
            // 播放出错/结束时禁用
            if (this.isGestureDisabledByStatus()) {
              return
            }
            const x = event.fingerList[0]?.localX ?? 0
            const y = event.fingerList[0]?.localY ?? 0
            // 控制层可见时，上/下控制栏区域内不触发（留 10px 容差）
            if (this.isInControlBarArea(y)) {
              return
            }
            // 屏幕三等分：左1/3双击快退，右1/3双击快进（秒数可在播放设置与全局设置中调整），中间双击切换播放/暂停
            const third = this.playerControllerArea.width / 3
            if (x < third) {
              this.seekByDoubleTap(true)
            } else if (x > third * 2) {
              this.seekByDoubleTap(false)
            } else {
              this.togglePlayPause()
            }
          }),
        TapGesture({ count: 1 })
          .onAction(() => {
            if (this.showPanel) {
              return
            }
            this.toggleControllerVisibility()
          })
      )
    )
    .onTouch((event: TouchEvent) => {
      // 触摸播放区（含子组件）时确保控制层根节点持有焦点，键盘快捷键可用
      if (event.type === TouchType.Down) {
        this.requestPlayerFocus()
      }
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
    .id('playerControllerRoot')
    .focusable(true)
    .focusOnTouch(true)
    .onAppear(() => {
      // 首次挂载即持有焦点，外接键盘可直接使用快捷键
      this.requestPlayerFocus()
    })
    .onKeyEventDispatch((event: KeyEvent): boolean => this.handlePlayerKeyEvent(event))
    .gesture(
      PanGesture({ direction: PanDirection.All })
        .onActionStart((event: GestureEvent) => {
          // 控制面板锁定/右侧面板打开/播放出错结束时禁用手势
          if (this.isLocked || this.showPanel || this.isGestureDisabledByStatus()) {
            return
          }
          this.panAxis = 0
          this.panStartX = event.fingerList[0]?.localX ?? 0;
          this.panStartY = event.fingerList[0]?.localY ?? 0;
          // 控制层可见时，起点落在上/下控制栏区域内则屏蔽本次手势（留 10px 容差）
          this.gestureBlocked = this.isInControlBarArea(this.panStartY)
        })
        .onActionUpdate((event: GestureEvent) => {
          if (this.isLocked || this.showPanel || this.gestureBlocked || this.isGestureDisabledByStatus()) {
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
              this.danmakuCtrl.onSeek(this.seekPreviewPos, this.isPlayingNow())
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
          // 控制面板锁定/右侧面板打开/播放出错结束时禁用手势
          if (this.isLocked || this.showPanel || this.isGestureDisabledByStatus()) {
            return
          }
          const x = event.fingerList[0]?.localX ?? 0
          const y = event.fingerList[0]?.localY ?? 0
          // 控制层可见时，上/下控制栏区域内不触发长按手势（留 10px 容差）
          if (this.isInControlBarArea(y)) {
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

  /** 双击左/右半区：快退/快进指定秒数（秒数可在播放设置与全局设置中调整） */
  private seekByDoubleTap(isRewind: boolean): void {
    const duration = this.effectiveDuration()
    if (duration <= 0) {
      return
    }
    const deltaSec = isRewind ? appSettings.double_tap_seek_rewind : appSettings.double_tap_seek_forward
    if (deltaSec <= 0) {
      return
    }
    const basePos = this.isCasting ? this.castLastPos : this.playerManager.getCurrentPosition()
    const target = this.getValidValue(basePos + (isRewind ? -deltaSec : deltaSec) * 1000, 0, duration)
    if (target == basePos) {
      return
    }
    if (this.isCasting) {
      this.castLastPos = target
      this.castManager.seek(target)
    } else {
      this.playerManager.seekTo(target)
      this.danmakuCtrl.onSeek(target, this.isPlayingNow())
    }
    // 立即刷新进度显示，并短暂显示快进/快退提示浮层
    this.seekDragStartPos = basePos
    this.seekPreviewPos = target
    this.progress = target / duration * 100
    this.currentTime = VideoTimeUtils.stringForTime(target)
    this.isSeekDragging = true
    if (this.seekOverlayTimer >= 0) {
      clearTimeout(this.seekOverlayTimer)
    }
    this.seekOverlayTimer = setTimeout(() => {
      this.isSeekDragging = false
      this.seekOverlayTimer = -1
    }, 600)
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
    // 弹幕随快退连续校正（内部按漂移阈值节流）
    this.danmakuCtrl.onSeek(this.rewindTargetPos, true)
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
    // 倍速变化同步到系统播控中心
    this.castManager.updatePlaybackState(true, this.playerManager.getCurrentPosition(), 3.0)
  }

  private stopSpeedBoost() {
    if (!this.isSpeedBoosting) {
      return
    }
    this.isSpeedBoosting = false
    this.playerManager.setSpeed(this.speedBeforeBoost)
    if (!this.isCasting) {
      this.castManager.updatePlaybackState(this.playerStatus == PlayerStatus.PLAY,
        this.playerManager.getCurrentPosition(), this.speedBeforeBoost)
    }
  }

  /** 当前是否处于播放中（投播时取远端状态） */
  private isPlayingNow(): boolean {
    return this.isCasting ? this.isCastPlaying : this.playerStatus == PlayerStatus.PLAY
  }

  /** 当前倍速数值（解析自 currentSpeed 文本） */
  private currentSpeedValue(): number {
    const found = VIDEO_SPEED_LIST.find((item: KeyValue) => item.name == this.currentSpeed)
    return found ? found.value : 1.0
  }

  /** 控制层可见时，判断 y 坐标是否落在上/下控制栏手势屏蔽区（留 10px 容差） */
  private isInControlBarArea(y: number): boolean {
    return this.showController
      && (y < this.topBarHeight + 10
        || y > this.playerControllerArea.height - this.bottomBarHeight - 10)
  }

  /** 播放出错/结束时禁用进度、音量、亮度、长按手势 */
  private isGestureDisabledByStatus(): boolean {
    return this.playerStatus == PlayerStatus.ERROR || this.playerStatus == PlayerStatus.DONE
  }

  /** 双击/点击暂停标识：切换播放/暂停（投播时切换远端，本端仅接受 PLAY/PAUSE 状态） */
  private togglePlayPause(): void {
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
    } else if (this.playerStatus == PlayerStatus.PAUSE) {
      this.playerManager.start()
    }
  }

  /** 切换到指定剧集（越界或重复点击不处理） */
  private selectEpisodeByIndex(index: number): void {
    if (index < 0 || index >= this.episodeList.length || index == this.episodeIndex) {
      return
    }
    this.playerManager.selectEpisode(index)
  }

  /** 单击/快捷键：切换控制层显示隐藏（暂停态保持常显） */
  private toggleControllerVisibility(): void {
    // 暂停态不隐藏控制层，保持常显
    if (this.isCenterPauseMarkVisible()) {
      this.showController = true
      this.closeController()
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
  }

  /** 请求播放器控制层根节点获得焦点（键盘快捷键依赖焦点接收按键） */
  private requestPlayerFocus(): void {
    try {
      this.getUIContext().getFocusController().requestFocus('playerControllerRoot')
    } catch (e) {
      Logger.e('fail', 'requestFocus playerControllerRoot', e)
    }
  }

  /** 键盘快捷键分发：锁定/右侧面板打开时不拦截；绑定键返回 true 消费事件 */
  private handlePlayerKeyEvent(event: KeyEvent): boolean {
    if (this.isLocked || this.showPanel) {
      return false
    }
    const action: string = findActionByKeyCode(event.keyCode)
    if (action === '') {
      return false
    }
    // 播放出错/结束时与手势保持一致：仅保留控制层与全屏切换
    if (this.isGestureDisabledByStatus()
      && action !== 'toggle_controller' && action !== 'toggle_fullscreen') {
      return false
    }
    if (event.type === KeyType.Down) {
      // 按住产生的重复 Down 事件只处理一次
      if (this.heldKeyCodes.has(event.keyCode)) {
        return true
      }
      this.heldKeyCodes.add(event.keyCode)
      this.executeShortcut(action)
    } else {
      this.heldKeyCodes.delete(event.keyCode)
      if (action === 'rewind_hold') {
        this.stopRewind()
      } else if (action === 'speed_boost') {
        this.stopSpeedBoost()
      }
    }
    return true
  }

  /** 执行快捷键动作 */
  private executeShortcut(action: string): void {
    if (action === 'play_pause') {
      this.togglePlayPause()
    } else if (action === 'seek_forward') {
      this.seekByDoubleTap(false)
    } else if (action === 'seek_rewind') {
      this.seekByDoubleTap(true)
    } else if (action === 'rewind_hold') {
      this.startRewind()
    } else if (action === 'speed_boost') {
      this.startSpeedBoost()
    } else if (action === 'volume_up') {
      this.adjustVolumeByStep(1)
    } else if (action === 'volume_down') {
      this.adjustVolumeByStep(-1)
    } else if (action === 'brightness_up') {
      this.adjustBrightnessByStep(0.05)
    } else if (action === 'brightness_down') {
      this.adjustBrightnessByStep(-0.05)
    } else if (action === 'toggle_controller') {
      this.toggleControllerVisibility()
    } else if (action === 'toggle_fullscreen') {
      this.toggleFullScreenByKey()
    }
  }

  /** 键盘步进调节音量（0-15，联动音量面板） */
  private adjustVolumeByStep(delta: number): void {
    this.isLeftSideGesture = false
    this.volume = this.getValidValue(this.volume + delta, 0, 15)
  }

  /** 键盘步进调节亮度（0-1，步进 0.05，联动亮度面板） */
  private adjustBrightnessByStep(delta: number): void {
    this.screenBrightness = this.getValidValue(this.screenBrightness + delta, 0.0, 1.0)
    this.setScreenBrightness(this.screenBrightness)
    this.isLeftSideGesture = true
    this.isVolumeAndBrightnessVisible = true
    this.setHidePanelTimer()
  }

  /** 快捷键切换全屏 */
  private toggleFullScreenByKey(): void {
    if (this.playerManager.isFullScreen()) {
      this.playerManager.exitFullScreen()
    } else {
      this.playerManager.enterFullScreen()
    }
  }

  /** 中部暂停标识是否可见：非锁定/非加载/非解析/无面板，且处于可恢复的暂停态 */
  private isCenterPauseMarkVisible(): boolean {
    if (this.isLocked || this.isLoading || this.isParsing || this.showPanel) {
      return false
    }
    if (this.playerStatus == PlayerStatus.IDLE || this.playerStatus == PlayerStatus.INITIALIZED
      || this.playerStatus == PlayerStatus.PREPARED || this.playerStatus == PlayerStatus.STOP
      || this.playerStatus == PlayerStatus.DONE || this.playerStatus == PlayerStatus.ERROR) {
      return false
    }
    return !this.isPlayingNow()
  }

  /** 暂停时中部播放标识（半透明圆形，点击恢复播放，图标与左下角按钮一致） */
  @Builder
  CenterPauseMarkBuilder() {
    if (this.isCenterPauseMarkVisible()) {
      Column() {
        Image($r('app.media.ic_play'))
          .width(36)
          .height(36)
          .fillColor(Color.White)
          .objectFit(ImageFit.Contain)
      }
      .width(72)
      .height(72)
      .borderRadius(36)
      .backgroundColor('#66000000')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.togglePlayPause()
      })
    }
  }

  /** 当前媒体时长（投播时优先取远端回传时长） */
  private effectiveDuration(): number {
    if (this.isCasting && this.castLastDuration > 0) {
      return this.castLastDuration
    }
    return this.playerManager.getDuration() as number
  }

  /** 为当前剧集匹配并加载弹幕（弹弹play，按番剧标题 + 剧集标题） */
  private loadDanmaku(): void {
    if (!appSettings.danmaku_enabled) {
      this.danmakuLoaded = false
      return
    }
    const animeTitle = AnimeState.playingTitle
    const episodeTitle = this.title
    // 加载期间先卸载旧弹幕，避免上一集弹幕错时显示
    this.danmakuLoaded = false
    this.danmakuCtrl.load(animeTitle, episodeTitle).then((result: DanmakuLoadResult) => {
      if (result.status === DanmakuLoadStatus.LOADED) {
        this.danmakuLoaded = true
        // load() 会重置弹幕播放态，播放中开启需按播放器实际状态恢复，否则弹幕定格
        this.syncDanmakuPlayback()
        ToastUtil.showToast({ message: `弹幕已加载 ${result.comments.length} 条` })
      } else if (result.status === DanmakuLoadStatus.EMPTY) {
        ToastUtil.showToast({ message: '该集暂无弹幕' })
      } else if (result.status === DanmakuLoadStatus.NOT_FOUND) {
        ToastUtil.showToast({ message: '未查询到该番剧的弹幕资源' })
      } else if (result.status === DanmakuLoadStatus.NO_MATCH) {
        ToastUtil.showToast({ message: '未匹配到对应剧集，可在弹幕设置中手动切换弹幕' })
      } else {
        ToastUtil.showToast({ message: '弹幕加载失败，请稍后重试' })
      }
    })
  }

  /** 按播放器当前状态恢复弹幕时钟（prepare 完成后由回调按 playing 决定启动/定帧） */
  private syncDanmakuPlayback(): void {
    if (this.isPlayingNow()) {
      this.danmakuCtrl.onPlay(this.playerManager.getCurrentPosition())
    } else {
      this.danmakuCtrl.onPause()
    }
  }

  /** 打开切换弹幕对话框（预填当前番剧名并自动搜索） */
  private openDanmakuSwitchDialog(): void {
    this.danmakuSwitchKeyword = AnimeState.playingTitle
    this.danmakuSwitchAnimes = []
    this.danmakuSwitchSelectedAnime = null
    this.danmakuSwitchSearching = false
    this.danmakuSwitchDialogVisible = true
    this.hideRightPanel()
    this.searchDanmakuSwitchAnimes()
  }

  /** 关闭切换弹幕对话框 */
  private closeDanmakuSwitchDialog(): void {
    this.danmakuSwitchDialogVisible = false
    this.danmakuSwitchSelectedAnime = null
    this.danmakuSwitchAnimes = []
  }

  /** 按关键词搜索动画列表（切换弹幕第一步） */
  private async searchDanmakuSwitchAnimes(): Promise<void> {
    const keyword = this.danmakuSwitchKeyword.trim()
    if (keyword.length === 0 || this.danmakuSwitchSearching) {
      return
    }
    this.danmakuSwitchSearching = true
    this.danmakuSwitchAnimes = []
    this.danmakuSwitchSelectedAnime = null
    try {
      this.danmakuSwitchAnimes = await DandanplayApi.searchAnimes(keyword)
    } finally {
      this.danmakuSwitchSearching = false
    }
  }

  /** 手动选集加载弹幕（切换弹幕第二步） */
  private async selectDanmakuSwitchEpisode(episode: DandanplayEpisode): Promise<void> {
    if (this.danmakuSwitchSearching) {
      return
    }
    const anime = this.danmakuSwitchSelectedAnime
    const matchedTitle = anime !== null
      ? `${anime.animeTitle} ${episode.episodeTitle}` : episode.episodeTitle
    this.danmakuSwitchSearching = true
    try {
      const result = await this.danmakuCtrl.loadByEpisodeId(episode.episodeId, matchedTitle)
      if (result.status === DanmakuLoadStatus.LOADED) {
        this.danmakuLoaded = true
        // loadByEpisodeId 会重置弹幕播放态，按播放器实际状态恢复
        this.syncDanmakuPlayback()
        ToastUtil.showToast({ message: `弹幕已加载 ${result.comments.length} 条` })
        this.closeDanmakuSwitchDialog()
      } else if (result.status === DanmakuLoadStatus.EMPTY) {
        ToastUtil.showToast({ message: '该集暂无弹幕' })
      } else {
        ToastUtil.showToast({ message: '弹幕加载失败，请稍后重试' })
      }
    } finally {
      this.danmakuSwitchSearching = false
    }
  }

  /** 切换弹幕开关 */
  private toggleDanmaku(): void {
    appSettings.danmaku_enabled = !appSettings.danmaku_enabled
    if (appSettings.danmaku_enabled) {
      // 已有弹幕数据直接挂载展示，否则重新匹配加载
      if (this.danmakuCtrl.loadedCount > 0) {
        this.danmakuLoaded = true
        // 重新挂载后按播放器实际进度/播放态恢复，避免从旧位置起播
        this.syncDanmakuPlayback()
      } else {
        this.loadDanmaku()
      }
    } else {
      this.danmakuLoaded = false
    }
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
        // 快捷手势说明（仅全屏，点击查看手势区域示意并可直接调整双击快进/快退秒数）
        if (this.isFullScreen) {
          SymbolGlyph($r('sys.symbol.questionmark_circle'))
            .fontSize(24)
            .fontColor([Color.White])
            .margin({ left: 24 })
            .onClick(() => {
              this.showRightPanel(PanelType.GESTURE_HELP)
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
            if (this.isFullScreen) {
              // 全屏：播放区内右侧设置面板
              this.showRightPanel(PanelType.PLAYER_SETTINGS)
            } else {
              // 非全屏：详情页用简介同款半模态面板展示播放设置（含更多设置项）
              PLAYER_SETTINGS_EVENT.emit()
            }
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
          middle: { anchor: '__container__', align: HorizontalAlign.Center },
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
        Row({ space: 12 }) {
          // 上一集（第一集时隐藏）
          if (this.episodeIndex > 0) {
            Image($r("app.media.ic_episode_prev"))
              .width(22)
              .height(22)
              .fillColor(Color.White)
              .objectFit(ImageFit.Contain)
              .onClick(() => {
                this.selectEpisodeByIndex(this.episodeIndex - 1)
              })
          }
          Image(this.isPlayingNow() ? $r("app.media.ic_pause") : $r("app.media.ic_play"))
            .width(24)
            .height(24)
            .fillColor(Color.White)
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
          // 下一集（最后一集时隐藏）
          if (this.episodeIndex < this.episodeList.length - 1) {
            Image($r("app.media.ic_episode_next"))
              .width(22)
              .height(22)
              .fillColor(Color.White)
              .objectFit(ImageFit.Contain)
              .onClick(() => {
                this.selectEpisodeByIndex(this.episodeIndex + 1)
              })
          }
        }
        .margin({ left: this.isFullScreen ? 16 : 12 })
        .alignItems(VerticalAlign.Center)

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
                this.danmakuCtrl.onSeek(seekValue, this.isPlayingNow())
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

        Text(AnimeState.widthBp <= 2 && !this.isFullScreen ? '弹' : '弹幕')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderWidth(1)
          .borderColor(appSettings.danmaku_enabled ? $r('app.color.primary_color_accent') : Color.White)
          .borderRadius(4)
          .margin({ right: 12 })
          .fontSize(12)
          .fontColor(appSettings.danmaku_enabled ? $r('app.color.primary_color_accent') : Color.White)
          .onClick(() => {
            this.toggleDanmaku()
          })
        if (this.isFullScreen || AnimeState.widthBp > 2) {
          Text('弹幕设置')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderWidth(1)
            .borderColor(Color.White)
            .borderRadius(4)
            .margin({ right: 12 })
            .fontSize(12)
            .fontColor(Color.White)
            .onClick(() => {
              this.showRightPanel(PanelType.DANMAKU)
            })
        }

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
        } else if (this.rightPanelType == PanelType.GESTURE_HELP) {
          this.GestureHelpPanel()
        } else if (this.rightPanelType == PanelType.DANMAKU) {
          this.DanmakuSettingsPanel()
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
                // 倍速变化同步到系统播控中心（播控中心进度按倍速推算）
                this.castManager.updatePlaybackState(this.isPlayingNow(),
                  this.playerManager.getCurrentPosition(), item.value)
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
                // 同步持久化到全局设置，下次进入播放页沿用
                appSettings.video_fit = item.value
                this.playerManager.setVideoFit(item.value)
              })
          })
        }
        .width('100%')

        Row() {
          Column() {
            Text('弹幕开关')
              .fontSize(this.isFullScreen ? 16 : 13)
              .fontColor(Color.White)
            Text('通过弹弹play按标题自动匹配')
              .fontSize(this.isFullScreen ? 12 : 10)
              .fontColor('#99ffffff')
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)

          Blank()

          Toggle({ type: ToggleType.Switch, isOn: appSettings.danmaku_enabled })
            .onChange((isOn: boolean) => {
              if (appSettings.danmaku_enabled !== isOn) {
                this.toggleDanmaku()
              }
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

  /** 弹幕设置面板：样式（不透明度/字号/速度/区域）+ 屏蔽设置（类型/重复/屏蔽词） */
  @Builder DanmakuSettingsPanel() {
    Scroll() {
      Column({ space: this.isFullScreen ? 16 : 8 }) {
        Text('弹幕设置')
          .alignSelf(ItemAlign.Start)
          .fontSize(this.isFullScreen ? 16 : 13)
          .fontColor(Color.White)

        Row() {
          Text('不透明度')
            .fontSize(this.isFullScreen ? 16 : 13)
            .fontColor(Color.White)
          Slider({
            value: appSettings.danmaku_opacity * 100,
            min: 25,
            max: 100,
            step: 5,
            style: SliderStyle.InSet
          })
            .layoutWeight(1)
            .margin({ left: 12 })
            .blockColor($r('app.color.primary_color_accent'))
            .trackColor('#4dffffff')
            .selectedColor($r('app.color.primary_color'))
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode == SliderChangeMode.End || mode == SliderChangeMode.Click) {
                appSettings.danmaku_opacity = value / 100
                this.danmakuCtrl.applyStyle()
              }
            })
          Text(`${Math.round(appSettings.danmaku_opacity * 100)}%`)
            .fontSize(this.isFullScreen ? 12 : 10)
            .fontColor('#99ffffff')
            .margin({ left: 8 })
        }
        .width('100%')

        Row() {
          Text('字体大小')
            .fontSize(this.isFullScreen ? 16 : 13)
            .fontColor(Color.White)
          Slider({
            value: appSettings.danmaku_font_scale * 100,
            min: 50,
            max: 150,
            step: 5,
            style: SliderStyle.InSet
          })
            .layoutWeight(1)
            .margin({ left: 12 })
            .blockColor($r('app.color.primary_color_accent'))
            .trackColor('#4dffffff')
            .selectedColor($r('app.color.primary_color'))
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode == SliderChangeMode.End || mode == SliderChangeMode.Click) {
                appSettings.danmaku_font_scale = value / 100
                this.danmakuCtrl.applyStyle()
              }
            })
          Text(`${Math.round(appSettings.danmaku_font_scale * 100)}%`)
            .fontSize(this.isFullScreen ? 12 : 10)
            .fontColor('#99ffffff')
            .margin({ left: 8 })
        }
        .width('100%')

        Row() {
          Text('滚动速度')
            .fontSize(this.isFullScreen ? 16 : 13)
            .fontColor(Color.White)
          Slider({
            value: appSettings.danmaku_speed * 100,
            min: 100,
            max: 200,
            step: 10,
            style: SliderStyle.InSet
          })
            .layoutWeight(1)
            .margin({ left: 12 })
            .blockColor($r('app.color.primary_color_accent'))
            .trackColor('#4dffffff')
            .selectedColor($r('app.color.primary_color'))
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode == SliderChangeMode.End || mode == SliderChangeMode.Click) {
                appSettings.danmaku_speed = value / 100
                this.danmakuCtrl.applyStyle()
              }
            })
          Text(`${Math.round(appSettings.danmaku_speed * 100)}%`)
            .fontSize(this.isFullScreen ? 12 : 10)
            .fontColor('#99ffffff')
            .margin({ left: 8 })
        }
        .width('100%')

        Row() {
          Text('弹幕加粗')
            .fontSize(this.isFullScreen ? 16 : 13)
            .fontColor(Color.White)
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: appSettings.danmaku_bold })
            .onChange((isOn: boolean) => {
              appSettings.danmaku_bold = isOn
              this.danmakuCtrl.applyStyle()
            })
        }
        .width('100%')

        Text('显示区域')
          .alignSelf(ItemAlign.Start)
          .fontSize(this.isFullScreen ? 16 : 13)
          .fontColor(Color.White)

        Flex({ alignItems: ItemAlign.Start, justifyContent: FlexAlign.SpaceAround, wrap: FlexWrap.Wrap }) {
          ForEach(DANMAKU_AREA_LIST, (item: KeyValue) => {
            Text(item.name)
              .textAlign(TextAlign.Center)
              .fontColor(Color.White)
              .fontSize(this.isFullScreen ? 14 : 11)
              .padding(6)
              .backgroundColor((appSettings.danmaku_area == item.value) ? $r('app.color.primary_color_accent') : Color.Transparent)
              .borderRadius(4)
              .margin({ bottom: 8 })
              .width('33%')
              .maxLines(1)
              .onClick(() => {
                appSettings.danmaku_area = item.value
                this.danmakuCtrl.applyStyle()
              })
          })
        }
        .width('100%')

        Divider().color('#33ffffff').margin({ top: 4, bottom: 4 })

        Row() {
          Text('屏蔽滚动弹幕')
            .fontSize(this.isFullScreen ? 16 : 13)
            .fontColor(Color.White)
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: appSettings.danmaku_block_scroll })
            .onChange((isOn: boolean) => {
              appSettings.danmaku_block_scroll = isOn
              this.danmakuCtrl.applyStyle()
            })
        }
        .width('100%')

        Row() {
          Text('屏蔽固定弹幕')
            .fontSize(this.isFullScreen ? 16 : 13)
            .fontColor(Color.White)
          Text('顶部/底部')
            .fontSize(this.isFullScreen ? 12 : 10)
            .fontColor('#99ffffff')
            .margin({ left: 6 })
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: appSettings.danmaku_block_fixed })
            .onChange((isOn: boolean) => {
              appSettings.danmaku_block_fixed = isOn
              this.danmakuCtrl.applyStyle()
            })
        }
        .width('100%')

        Row() {
          Text('屏蔽彩色弹幕')
            .fontSize(this.isFullScreen ? 16 : 13)
            .fontColor(Color.White)
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: appSettings.danmaku_block_color })
            .onChange((isOn: boolean) => {
              appSettings.danmaku_block_color = isOn
              this.danmakuCtrl.applyStyle()
            })
        }
        .width('100%')

        Row() {
          Column() {
            Text('隐藏重复弹幕')
              .fontSize(this.isFullScreen ? 16 : 13)
              .fontColor(Color.White)
            Text('相同内容短时间内仅显示首条')
              .fontSize(this.isFullScreen ? 12 : 10)
              .fontColor('#99ffffff')
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: appSettings.danmaku_hide_duplicate })
            .onChange((isOn: boolean) => {
              appSettings.danmaku_hide_duplicate = isOn
              this.danmakuCtrl.applyStyle()
            })
        }
        .width('100%')

        Column() {
          Text('弹幕屏蔽词')
            .fontSize(this.isFullScreen ? 16 : 13)
            .fontColor(Color.White)
            .alignSelf(ItemAlign.Start)
          Text('多个屏蔽词用逗号或空格分隔，实时生效')
            .fontSize(this.isFullScreen ? 12 : 10)
            .fontColor('#99ffffff')
            .margin({ top: 2, bottom: 6 })
            .alignSelf(ItemAlign.Start)
          TextInput({ text: appSettings.danmaku_block_words, placeholder: '输入屏蔽词，逗号分隔' })
            .type(InputType.Normal)
            .width('100%')
            .height(40)
            .fontSize(this.isFullScreen ? 14 : 12)
            .fontColor(Color.White)
            .placeholderColor('#99ffffff')
            .backgroundColor('#33ffffff')
            .borderRadius(6)
            .onChange((value: string) => {
              appSettings.danmaku_block_words = value
              this.danmakuCtrl.applyStyle()
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Button('切换弹幕')
          .width('100%')
          .height(this.isFullScreen ? 40 : 36)
          .fontSize(this.isFullScreen ? 15 : 13)
          .fontColor(Color.White)
          .backgroundColor('#33ffffff')
          .borderRadius(6)
          .margin({ top: 12 })
          .onClick(() => {
            this.openDanmakuSwitchDialog()
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

  /** 切换弹幕对话框卡片（搜索动画 -> 选集 -> 加载） */
  @Builder DanmakuSwitchDialogCard() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        if (this.danmakuSwitchSelectedAnime !== null) {
          Button('返回')
            .height(32)
            .fontSize(13)
            .fontColor(Color.White)
            .backgroundColor('#33ffffff')
            .borderRadius(6)
            .onClick(() => {
              this.danmakuSwitchSelectedAnime = null
            })
        }
        Text(this.danmakuSwitchSelectedAnime !== null
          ? this.danmakuSwitchSelectedAnime.animeTitle : '切换弹幕')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')

      if (this.danmakuSwitchSelectedAnime === null) {
        Row({ space: 8 }) {
          TextInput({ text: this.danmakuSwitchKeyword, placeholder: '输入番剧名称或别名' })
            .type(InputType.Normal)
            .layoutWeight(1)
            .height(38)
            .fontSize(13)
            .fontColor(Color.White)
            .placeholderColor('#99ffffff')
            .backgroundColor('#33ffffff')
            .borderRadius(6)
            .onChange((value: string) => {
              this.danmakuSwitchKeyword = value
            })
          Button('搜索')
            .height(38)
            .fontSize(13)
            .fontColor(Color.White)
            .backgroundColor('#33ffffff')
            .borderRadius(6)
            .enabled(!this.danmakuSwitchSearching)
            .onClick(() => {
              this.searchDanmakuSwitchAnimes()
            })
        }
        .width('100%')

        if (this.danmakuSwitchSearching) {
          LoadingProgress()
            .size(28)
            .color(Color.White)
            .margin({ top: 12 })
        } else if (this.danmakuSwitchAnimes.length === 0) {
          Text('暂无搜索结果，换个名称试试')
            .fontSize(12)
            .fontColor('#99ffffff')
            .margin({ top: 12 })
        } else {
          Scroll() {
            Column() {
              ForEach(this.danmakuSwitchAnimes, (anime: DandanplayAnime) => {
                Column({ space: 2 }) {
                  Text(anime.animeTitle)
                    .fontSize(14)
                    .fontColor(Color.White)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(`共 ${anime.episodes.length} 集`)
                    .fontSize(11)
                    .fontColor('#99ffffff')
                    .width('100%')
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .padding(8)
                .borderRadius(6)
                .backgroundColor('#1affffff')
                .margin({ bottom: 6 })
                .onClick(() => {
                  this.danmakuSwitchSelectedAnime = anime
                })
              }, (anime: DandanplayAnime) => `anime-${anime.animeId}`)
            }
          }
          .width('100%')
          .constraintSize({ maxHeight: 360 })
          .edgeEffect(EdgeEffect.Spring)
        }
      } else {
        Scroll() {
          Column() {
            ForEach(this.danmakuSwitchSelectedAnime.episodes,
              (episode: DandanplayEpisode) => {
                Text(episode.episodeTitle)
                  .fontSize(14)
                  .fontColor(Color.White)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .padding(10)
                  .borderRadius(6)
                  .backgroundColor('#1affffff')
                  .margin({ bottom: 6 })
                  .onClick(() => {
                    this.selectDanmakuSwitchEpisode(episode)
                  })
              }, (episode: DandanplayEpisode) => `episode-${episode.episodeId}`)
          }
        }
        .width('100%')
        .constraintSize({ maxHeight: 380 })
        .edgeEffect(EdgeEffect.Spring)
        if (this.danmakuSwitchSearching) {
          LoadingProgress()
            .size(28)
            .color(Color.White)
        }
      }
    }
    .padding(14)
    .width('86%')
    .constraintSize({ maxHeight: '80%' })
    .backgroundColor('#ee1c1c1e')
    .borderRadius(12)
  }

  /** 快捷手势说明条目（实时读取双击快进/快退秒数设置） */
  private get gestureGuides(): GestureGuideItem[] {
    return [
      new GestureGuideItem('单击', '显示 / 隐藏控制层'),
      new GestureGuideItem('双击左侧 1/3', `快退 ${appSettings.double_tap_seek_rewind} 秒`),
      new GestureGuideItem('双击中间 1/3', '播放 / 暂停'),
      new GestureGuideItem('双击右侧 1/3', `快进 ${appSettings.double_tap_seek_forward} 秒`),
      new GestureGuideItem('长按左半屏', '2X 连续快退'),
      new GestureGuideItem('长按右半屏', '3X 临时倍速'),
      new GestureGuideItem('横向拖动', '调节播放进度'),
      new GestureGuideItem('左半屏上下拖动', '调节亮度'),
      new GestureGuideItem('右半屏上下拖动', '调节音量')
    ]
  }

  /** 键盘快捷键说明条目（实时读取快捷键配置，可在 设置-播放控制 中修改） */
  private get shortcutGuides(): GestureGuideItem[] {
    return SHORTCUT_DEFS.map((def: ShortcutDef): GestureGuideItem =>
      new GestureGuideItem(def.label, PlayerShortcuts.getShortcutLabel(def.action)))
  }

  /** 快捷手势说明面板：展示手势区域示意，并可直接调整双击快进/快退秒数 */
  @Builder GestureHelpPanel() {
    Scroll() {
      Column({ space: this.isFullScreen ? 16 : 8 }) {
        Text('快捷手势')
          .alignSelf(ItemAlign.Start)
          .fontSize(this.isFullScreen ? 16 : 13)
          .fontColor(Color.White)

        ForEach(this.gestureGuides, (item: GestureGuideItem) => {
          Row() {
            Text(item.name)
              .fontColor(Color.White)
              .fontSize(this.isFullScreen ? 14 : 11)
              .maxLines(1)
            Blank()
            Text(item.desc)
              .fontColor('#99ffffff')
              .fontSize(this.isFullScreen ? 12 : 10)
              .maxLines(1)
              .margin({ left: 12 })
          }
          .width('100%')
        }, (item: GestureGuideItem) => `${item.name}_${item.desc}`)

        Divider()
          .strokeWidth(1)
          .color('#33ffffff')
          .margin({ top: 4, bottom: 4 })

        Text('双击快进秒数')
          .alignSelf(ItemAlign.Start)
          .fontSize(this.isFullScreen ? 16 : 13)
          .fontColor(Color.White)

        Flex({ alignItems: ItemAlign.Start, justifyContent: FlexAlign.SpaceAround, wrap: FlexWrap.Wrap }) {
          ForEach(makeSeekSecondsOptions(), (item: MenuOption) => {
            Text(item.title ?? item.value)
              .textAlign(TextAlign.Center)
              .fontColor(Color.White)
              .fontSize(this.isFullScreen ? 14 : 11)
              .padding(6)
              .backgroundColor((appSettings.double_tap_seek_forward == Number(item.value))
                ? $r('app.color.primary_color_accent') : Color.Transparent)
              .borderRadius(4)
              .margin({ bottom: 8 })
              .width('33%')
              .maxLines(1)
              .onClick(() => {
                appSettings.double_tap_seek_forward = Number(item.value)
              })
          }, (item: MenuOption) => item.value)
        }
        .width('100%')

        Text('双击快退秒数')
          .alignSelf(ItemAlign.Start)
          .fontSize(this.isFullScreen ? 16 : 13)
          .fontColor(Color.White)

        Flex({ alignItems: ItemAlign.Start, justifyContent: FlexAlign.SpaceAround, wrap: FlexWrap.Wrap }) {
          ForEach(makeSeekSecondsOptions(), (item: MenuOption) => {
            Text(item.title ?? item.value)
              .textAlign(TextAlign.Center)
              .fontColor(Color.White)
              .fontSize(this.isFullScreen ? 14 : 11)
              .padding(6)
              .backgroundColor((appSettings.double_tap_seek_rewind == Number(item.value))
                ? $r('app.color.primary_color_accent') : Color.Transparent)
              .borderRadius(4)
              .margin({ bottom: 8 })
              .width('33%')
              .maxLines(1)
              .onClick(() => {
                appSettings.double_tap_seek_rewind = Number(item.value)
              })
          }, (item: MenuOption) => item.value)
        }
        .width('100%')

        Divider()
          .strokeWidth(1)
          .color('#33ffffff')
          .margin({ top: 4, bottom: 4 })

        Text('键盘快捷键')
          .alignSelf(ItemAlign.Start)
          .fontSize(this.isFullScreen ? 16 : 13)
          .fontColor(Color.White)

        ForEach(this.shortcutGuides, (item: GestureGuideItem) => {
          Row() {
            Text(item.name)
              .fontColor(Color.White)
              .fontSize(this.isFullScreen ? 14 : 11)
              .maxLines(1)
            Blank()
            Text(item.desc)
              .fontColor('#99ffffff')
              .fontSize(this.isFullScreen ? 12 : 10)
              .maxLines(1)
              .margin({ left: 12 })
          }
          .width('100%')
        }, (item: GestureGuideItem) => `${item.name}_${item.desc}`)

        Text('快捷键可在 设置 - 播放控制 中修改')
          .fontSize(this.isFullScreen ? 10 : 9)
          .fontColor('#66ffffff')
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
    // 暂停态控制层保持常显，不启动自动隐藏
    if (this.isCenterPauseMarkVisible()) {
      this.showController = true
      this.showControllerTimer = -1
      return
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
          // 面板关闭后重新持有焦点，键盘快捷键继续可用
          this.requestPlayerFocus()
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
      this.danmakuCtrl.onSeek(seekValue, this.isPlayingNow());
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
      if (brightness >= 0) {
        this.brightnessTouched = true;
      }
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