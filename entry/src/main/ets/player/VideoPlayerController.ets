import media from '@ohos.multimedia.media';
import IPlayerManager, { PlayerListener, PlayerStatus, VideoFit } from '../entity/VideoPlayer/IPlayerManager';
import EpisodeInfo from '../entity/EpisodeInfo';
import VideoTimeUtils from '../utils/VideoTimeUtils';
import Logger from '../utils/Logger';
import promptAction from '@ohos.promptAction';
import { ToastUtil } from '../utils/ToastUtils';
import { sortEpisodesByNumber } from '../utils/SortUtils';
import { AppConfigs } from '../entryability/Settings';

interface KeyValue {
  name: string,
  value: number
}

const VIDEO_SPEED_LIST: KeyValue[] = [
  { name: '0.75', value: PlaybackSpeed.Speed_Forward_0_75_X },
  { name: '1.00', value: PlaybackSpeed.Speed_Forward_1_00_X },
  { name: '1.25', value: PlaybackSpeed.Speed_Forward_1_25_X },
  { name: '1.75', value: PlaybackSpeed.Speed_Forward_1_75_X },
  { name: '2.00', value: PlaybackSpeed.Speed_Forward_2_00_X },
]

const VIDEO_FIT_LIST: KeyValue[] = [
  { name: '适应', value: VideoFit.Contain }, { name: '拉伸', value: VideoFit.Cover },
  { name: '填充', value: VideoFit.Fill }, { name: '16:9', value: VideoFit.Fit_16_9 },
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
@Component
export struct VideoPlayerController {

  @State currentTime: string = "00:00";
  @State totalTime: string = "00:00";
  @State progress: number = 0;
  @State slideEnable: boolean = true;
  @State playerStatus: number = PlayerStatus.IDLE;
  @State showController: boolean = true;
  @State title: string = ''
  @State isFullScreen: boolean = false
  @State showPanel: boolean = false
  @State rightPanelScale: number = 0
  @State rightPanelType: number = PanelType.NONE
  @State currentSpeed: string = '1.00'
  @State isLocked: boolean = false
  @State videoFit: number = VideoFit.Contain
  @State isLoading: boolean = false
  @State bufferingPercent: number = 0
  @State episodeList: EpisodeInfo[] = []
  @State episodeIndex: number = 0
  @Link playerManager: IPlayerManager
  private showControllerTimer: number = -1;
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('currentWidthBreakpoint') widthBp: WidthBreakpoint = 1;
  @StorageLink('currentHeightBreakpoint') heightBp: HeightBreakpoint = 0;
  // 应用设置
  @StorageLink('AppSettings') appSettings: AppConfigs = new AppConfigs()
  private readonly playerListenerVC: PlayerListener = {
    onStatusChanged: (status: number) => {
      this.playerStatus = status
      this.initLoading()
      Logger.e('tips', 'PlayerController status=' + status + " playerStatus=" + this.playerStatus)
    },
    onEpisodeChanged: (episodeList: EpisodeInfo[], episodeIndex: number) => {
      this.episodeList = episodeList
      this.episodeIndex = episodeIndex
      this.title = episodeList[episodeIndex].desc
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
        this.bufferingPercent = value
      } else if (type == media.BufferingInfoType.BUFFERING_START) {
        this.isLoading = true
      } else if (type == media.BufferingInfoType.BUFFERING_END) {
        this.isLoading = false
      }
      Logger.e('tips', 'onBuffering isLoading=' + this.isLoading)
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
  }

  aboutToDisappear() {
    this.playerManager.removeListener(this.playerListenerVC)
    if (this.showControllerTimer >= 0) {
      clearTimeout(this.showControllerTimer)
      this.showControllerTimer = -1;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {

      if (this.showController) {
        // 控制面板
        this.VideoController()
      }

      this.RightPanel()
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      this.showController = !this.showController;
    })
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
            this.pageStack.pop(true)
          })
        Text(this.title)
          .fontColor(Color.White)
          .fontSize(14)
          .fontWeight(500)
          .layoutWeight(1)
          .margin({ left: 16 })
          .align(Alignment.Start)
        Blank()
        // TODO 投屏
        if (this.isFullScreen) {
          Image($r("app.media.ic_airplay"))
            .width(24)
            .height(24)
            .fillColor(Color.White)
            .margin({ left: 24 })
            .objectFit(ImageFit.Contain)
            .onClick(() => {
              ToastUtil.showToast({ message: 'TODO 投屏' })
            })
        }
        // TODO 小窗播放
        Image($r("app.media.ic_float_window"))
          .width(28)
          .height(28)
          .fillColor(Color.White)
          .margin({ left: this.isFullScreen ? 24 : 16 })
          .objectFit(ImageFit.Contain)
          .onClick(() => {
            ToastUtil.showToast({ message: 'TODO 小窗播放' })
          })
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
        // 加载圆圈
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(Color.White)
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
      if (this.playerStatus === PlayerStatus.ERROR || this.playerStatus === PlayerStatus.DONE) {
        // 播放错误 & 重新播放
        Column() {
          Image($r('app.media.ic_refresh'))
            .width(32)
            .height(32)
            .margin(8)
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
      if (this.widthBp > 2) {
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
          }
        })
      }

      // 下控制栏区域
      Row() {
        Image((this.playerStatus == PlayerStatus.PLAY) ? $r("app.media.ic_pause") : $r("app.media.ic_play"))
          .width(24)
          .height(24)
          .fillColor(Color.White)
          .margin({ left: this.isFullScreen ? 16 : 12 })
          .objectFit(ImageFit.Contain)
          .onClick(() => {
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
            Logger.e('tips', 'Slider onChange mode=' + mode + ' value=' + value + ' typeof mode=' + (typeof mode)
              + ' result=' + (mode == SliderChangeMode.End || mode == SliderChangeMode.Click)
              + ' result2=' + (mode == SliderChangeMode.Click) + ' click=' + SliderChangeMode.Click + ' result3=' + (mode === SliderChangeMode.Click))
            if (mode == SliderChangeMode.End || mode == 3) {
              this.progress = value
              let seekValue = value / 100 * (this.playerManager.getDuration() as number);
              Logger.e('tips', 'Slider onChange seekValue=' + seekValue + " duration=" + this.playerManager.getDuration())

              this.setProgress(this.playerManager.getDuration() as number, seekValue)

              this.playerManager.seekTo(seekValue);
            }
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
        if (this.widthBp <= 2) {
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
    }
    .width('100%')
    .height('100%')
    .onAppear(() => {
      if (this.showController) {
        this.showControllerTimer = setTimeout(() => {
          // 5s后隐藏
          this.showController = false
          this.showControllerTimer = -1
        }, 6000)
      }
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
              this.playerManager.setSpeed(item.value)
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
          Text(this.appSettings.episodes_order === 'desc' ? '倒序' : '正序')
            .margin({ left: 24 })
            .fontSize(this.isFullScreen ? 12 : 10)
            .fontColor(Color.White)
            .onClick(() => {
              if (this.appSettings.episodes_order === 'desc') {
                this.appSettings.episodes_order = 'asc'
              } else {
                this.appSettings.episodes_order = 'desc'
              }
            })
        }
        .width('100%')
        Flex({ alignItems: ItemAlign.Start, justifyContent: FlexAlign.Start, wrap: FlexWrap.Wrap }) {
          ForEach(sortEpisodesByNumber(this.episodeList, this.appSettings.episodes_order), (episode: EpisodeInfo, index: number) => {
            Text(episode.title)
              .padding(8)
              .fontSize(this.isFullScreen ? 14 : 12)
              .fontColor(Color.White)
              .maxLines(1)
              .constraintSize({
                minWidth: '50%'
              })
              .backgroundColor(this.episodeIndex == index ? $r('app.color.primary_color_accent') : Color.Transparent)
              .borderRadius(6)
              .borderColor(Color.White)
              .borderWidth(0)
              .onClick(() => {
                if (this.episodeIndex == index) {
                  return
                }
                this.playerManager.playEpisodeList(sortEpisodesByNumber(this.episodeList, this.appSettings.episodes_order), index)
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

        // TODO 切换播放器
//        Text('播放器')
//          .alignSelf(ItemAlign.Start)
//          .fontSize(this.isFullScreen ? 16 : 13)
//          .fontColor(Color.White)
//
//        Flex({ alignItems: ItemAlign.Start, justifyContent: FlexAlign.SpaceAround, wrap: FlexWrap.Wrap }) {
//          ForEach(['系统内置', 'IjkPlayer'], (item, i) => {
//            Text(item)
//              .textAlign(TextAlign.Center)
//              .fontColor(Color.White)
//              .fontSize(this.isFullScreen ? 14 : 11)
//              .padding(6)
//              .backgroundColor(i == 0 ? $r('app.color.primary_color_accent') : Color.Transparent)
//              .borderRadius(4)
//              .margin({ bottom: 8 })
//              .constraintSize({
//                minWidth: '40%'
//              })
//              .maxLines(1)
//              .onClick(() => {
//                promptAction.showToast({ message: 'TODO 播放器' })
//              })
//          })
//        }
//        .width('100%')

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

  private showRightPanel(type: number) {
    this.rightPanelType = type
    this.rightPanelScale = 0
    this.showPanel = true
    this.showController = false
    if (this.showControllerTimer >= 0) {
      clearTimeout(this.showControllerTimer)
    }
    animateTo(
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
        }
      },
      () => {
        this.rightPanelScale = 0
      }
    )
  }

  private setProgress(duration: number, position: number) {
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

  private initLoading() {
    this.isLoading = this.playerStatus == PlayerStatus.IDLE
    || this.playerStatus == PlayerStatus.INITIALIZED
    || this.playerStatus == PlayerStatus.PREPARED
  }

}