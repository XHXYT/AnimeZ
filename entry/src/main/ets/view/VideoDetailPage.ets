import { MultiVideoPlayer } from '../player/MultiVideoPlayer';
import IPlayerManager, { VideoFit } from '../player/model/IPlayerManager';
import CustomPanel, { PanelController } from '../components/CustomPanel';
import { CustomListItem } from '../components/CustomListItem';
import { CustomItemInfo, ItemActionType, MenuOption } from '../entity/CusItemInfo';
import { PLAYER_SETTINGS_EVENT, PLAYER_SWITCH_EVENT } from '../utils/EventBus';
import emitter from '@ohos.events.emitter';
import { PiPManager } from '../player/PiPManager';
import { window } from '@kit.ArkUI';
import StateView from '../components/StateView';
import { VideoList } from '../components/VideoList';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { VideoNavigateInfo } from '../entity/VideoNavigateInfo';
import { ToastUtil } from '../utils/ToastUtils';
import { appSettings } from '../entryability/Settings';
import {
  VideoDetailGridColHeight
} from '../utils/breakpoint/BreakPoint';
import PlayerManagerImpl from '../viewmodel/PlayerManagerImpl';
import { VideoDetailViewModel } from '../viewmodel/VideoDetailViewModel';
import SystemBarUtils from '../utils/SystemBarUtils';
import EpisodeList from '../entity/EpisodeList';
import EpisodeInfo from '../entity/EpisodeInfo';
import Logger from '../utils/Logger';
import { Header } from '../components/common/Header';
import { sortEpisodesByNumber } from '../utils/SortUtils';
import { VideoCacheList } from '../components/VideoCacheList';
import { _AnimeState, AnimeState } from '../entryability/AnimeState';

// 系统路由
@Builder
export function VideoDetailPageBuilder(name: string, param: Object) {
  VideoDetailPage()
}

@ComponentV2
struct VideoDetailPage {

  /** @description 全局状态单例（@Monitor 监听 isPhoneLandscape 路径） */
  @Local animeState: _AnimeState = AnimeState

  private playerManager: IPlayerManager = new PlayerManagerImpl()
  viewModel: VideoDetailViewModel = new VideoDetailViewModel(
    this.playerManager,
    this.getUIContext().getHostContext()!
  )
  private panelController: PanelController = new PanelController()
  private webviewController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear() {
    // 播放器控制层"设置"按钮（非全屏）：用简介同款半模态面板展示播放设置
    PLAYER_SETTINGS_EVENT.on(() => {
      this.viewModel.panelContentType = 2
      this.panelController.show()
    })
  }

  aboutToDisappear() {
    PLAYER_SETTINGS_EVENT.off()
    this.viewModel.onDestroy();
  }

  @Monitor('animeState.isPhoneLandscape')
  onPhoneLandscape() {
    this.viewModel.onPhoneLandscape(AnimeState.isPhoneLandscape);
  }

  build() {
    NavDestination() {
      Stack() {
        StateView({
          state: this.viewModel.state,
          errorMessage: this.viewModel.errorMessage,
          content: () => {
            this.Content()
          },
          onRetry: () => {
            this.viewModel.getDetailInfo();
            return true;
          }
        })
          .width('100%')
          .height('100%')
        // WebView
        if (AnimeState.showWebView) {
          this.WebViewContent()
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideToolBar(true)
    .hideTitleBar(true)
    .backgroundColor($r('app.color.background_color'))
    .onReady(async (ctx: NavDestinationContext) => {
      const params: VideoNavigateInfo = ctx?.pathInfo?.param as VideoNavigateInfo;
      await this.viewModel.initialize(params);
      // 进入页面时若手机已处于横屏，直接全屏（受"自动旋屏"设置控制）
      this.viewModel.onPhoneLandscape(AnimeState.isPhoneLandscape);
    })
    .onShown(() => {
      this.viewModel.onPageShow();
    })
    .onHidden(async () => {
      await this.viewModel.onPageHide();
    })
    .onBackPressed(() => {
      if (this.viewModel.handleBackPressed(this.panelController)) {
        return true;
      }
      if (!this.panelController.isShow() && !this.viewModel.isFullScreen) {
        SystemBarUtils.setWindowSystemBarTransparent(false);
        return false;
      }

      return true;
    })
  }

  @Builder WebViewContent() {
    Stack() {
      if (AnimeState.webviewManual) {
        // 半模态遮罩
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.45)')
          .transition(TransitionEffect.OPACITY.animation({ duration: 250 }))
        // 半模态卡片：状态头部 + 网页
        Column() {
          this.ManualHeader()
          this.CoreWeb()
        }
        .width('100%')
        .height('100%')
        .margin({
          left: 16,
          right: 16,
          top: AnimeState.topRectHeight + 24,
          bottom: 32
        })
        .borderRadius(20)
        .clip(true)
        .backgroundColor(Color.White)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ y: 60 }))
          .animation({ duration: 250, curve: Curve.Friction }))
      } else {
        // 自动模式：隐藏 1x1 WebView
        Stack() {
          this.CoreWeb()
        }
        .width(1)
        .height(1)
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 手动模式状态头部：当前状态 + 需要用户辅助的操作类型 + 取消 */
  @Builder ManualHeader() {
    Column() {
      Row() {
        Column() {
          Text('需要手动辅助播放')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF1F1F1F')
          Text(AnimeState.webviewManualReason)
            .fontSize(11)
            .fontColor('#FF888888')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        LoadingProgress()
          .width(20)
          .height(20)
          .color('#FF007DFF')
          .margin({ right: 10 })

        Button('取消')
          .fontSize(14)
          .height(32)
          .padding({ left: 14, right: 14 })
          .backgroundColor('rgba(0,0,0,0.05)')
          .fontColor('#FF1F1F1F')
          .onClick(() => {
            AnimeState.webJsVideoLink = 'ERR_MANUAL_CANCEL';
          })
      }
      .width('100%')
      .padding({ left: 16, right: 12, top: 12, bottom: 6 })

      Text('▶ 请在网页中点击播放按钮，应用将自动捕获播放地址并继续播放')
        .fontSize(12)
        .fontColor('#FF007DFF')
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
    }
    .width('100%')
    .backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Start)
  }

  /** WebView 主体（自动/手动模式共用，尺寸由父容器决定） */
  @Builder CoreWeb() {
    Web({ src: AnimeState.webviewUrl, controller: this.webviewController })
      .backgroundColor(AnimeState.webviewManual ? Color.White : Color.Transparent)
      .javaScriptAccess(true)
      .javaScriptProxy({
        object: {
          onLink: (link: string): void => {
            console.info(`animeBridge.onLink: ${link}`);
            AnimeState.webJsVideoLink = link;
          }
        },
        name: 'animeBridge',
        methodList: ['onLink'],
        controller: this.webviewController
      })
      .width('100%')
      .layoutWeight(1)
      .onPageBegin((event) => {
        console.log(`链接 ${event.url} 成功加载`)
      })
      .onPageEnd(e => {
        try {
          if (e) {
            Logger.e('tips', `URL ${e.url} 开始加载JavaScript`)
            // 手动模式下尽快安装钩子（避免错过用户点击触发的站点自身解析）；自动模式延迟等待页面就绪
            const injectDelay = AnimeState.webviewManual ? 800 : 3000;
            setTimeout(() => {
              // TODO 待修复 webviewController 未绑定上或者绑定了多个 Web 组件
              // 注意：页面销毁后 Web 组件解绑，runJavaScript 会同步抛 17100001，
              // .catch 捕获不到同步异常，必须在回调内部 try-catch
              try {
                this.webviewController.runJavaScript(AnimeState.runJs)
                  .then((result) => {
                    if (!AnimeState.webviewManual) {
                      console.info(`URL ${e.url} 执行 result: ${result}`)
                      // 兼容两种返回：runJavaScript 结果可能为原始字符串或 JSON 编码字符串
                      let link: string = result
                      try {
                        const parsed: string = JSON.parse(result)
                        if (parsed !== '') {
                          link = parsed
                        }
                      } catch (err) {
                        // result 非合法 JSON 时按原始字符串处理
                      }
                      AnimeState.webJsVideoLink = link
                      AnimeState.showWebView = false
                      console.info(`URL ${e.url} 显示状态: ${AnimeState.showWebView} 解析后链接：${AnimeState.webJsVideoLink}`)
                    } else {
                      // 手动模式：结果经 animeBridge 桥回传，此处仅确认钩子安装
                      console.info(`URL ${e.url} 手动模式钩子已安装: ${result}`)
                    }
                  })
                  .catch((error: BusinessError) => {
                    Logger.e('fail', '加载JavaScript', error)
                  })
              } catch (error) {
                Logger.e('fail', '页面已销毁，跳过JS注入', error)
              }
            }, injectDelay)
          }
        } catch (error) {
          Logger.e('fail', 'webviewController 加载JavaScript', error)
        }
      })
  }

  /**
   * 是否使用左右分栏布局
   * 1. 宽度不足 md 或手机横屏窗口（宽 > 高且高度不足）时不分栏；
   * 2. 平板/折叠屏横屏（矮宽窗口，宽度达到 lg）保持左右分栏；
   * 3. 平板竖屏/折叠屏展开（高窗口）按视频方向选择：
   *    竖向视频左右分栏可在非全屏时显示更多画面，横向视频上下布局更和谐
   */
  private isSideBySide(): boolean {
    if (this.viewModel.isFullScreen) {
      return false
    }
    if (AnimeState.widthBp < WidthBreakpoint.WIDTH_MD) {
      return false
    }
    // 手机横屏窗口：宽 > 高且高度过小，不分栏
    if (AnimeState.windowWidth > AnimeState.windowHeight && AnimeState.windowHeight <= 500) {
      return false
    }
    // 矮宽窗口（平板/折叠屏横屏）：宽度达到 lg 时保持左右分栏
    if (AnimeState.heightBp === HeightBreakpoint.HEIGHT_SM) {
      return AnimeState.widthBp >= WidthBreakpoint.WIDTH_LG
    }
    // 高窗口（平板竖屏/折叠屏展开）：竖向视频分栏，横向视频上下布局
    return this.viewModel.isVerticalVideo()
  }

  /** 播放器区域是否为全高（全屏/左右分栏/断点表为 100% 时），此时控制层可撑满整个播放器列 */
  private isPlayerAreaFullHeight(): boolean {
    if (this.viewModel.isFullScreen || this.isSideBySide()) {
      return true
    }
    return VideoDetailGridColHeight(AnimeState.widthBp, AnimeState.heightBp) === '100%'
  }

  @Builder Content() {
    GridRow({ columns: 12 }) {
      // 播放器区
      GridCol({
        span: this.viewModel.isFullScreen ? 12 : (this.isSideBySide() ? 8 : 12),
        order: 1
      }) {
        Stack() {
          MultiVideoPlayer({
            playerManager: this.playerManager,
            isFullScreen: this.viewModel.isFullScreen,
            fillHeight: this.isPlayerAreaFullHeight()
          })
        }
        .width('100%')
        .backgroundColor(Color.Black)
        .alignContent(Alignment.Center)
        .padding({ top: this.viewModel.isFullScreen ? 0 : AnimeState.topRectHeight })
        .height(this.isPlayerAreaFullHeight() ? '100%'
          : VideoDetailGridColHeight(AnimeState.widthBp, AnimeState.heightBp))
      }

      // 视频详情区
      GridCol({
        span: this.viewModel.isFullScreen ? 0 : (this.isSideBySide() ? 4 : 12),
        order: 2
      }) {
        if (this.viewModel.videoDetailInfo) {
          Stack() {
            this.RootContent()
            CustomPanel({
              controller: this.panelController,
              panelContent: () => {
                this.SecondaryContent()
              }
            })
              .hitTestBehavior(HitTestMode.None)
              .width('100%')
              .height('100%')
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ top: this.viewModel.isFullScreen ? 0 : 12 })
        }
      }.layoutWeight(1)

    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_color'))
  }

  /**
   * 视频详情整体框架
   */
  @Builder RootContent() {
    Column() {
      Scroll() {
        Column({ space: 16 }) {
          // 视频标题和封面
          Row() {
            Column() {
              Text(this.viewModel.videoDetailInfo.title)
                .alignSelf(ItemAlign.Start)
                .fontColor($r('app.color.color_text_major'))
                .fontWeight(FontWeight.Bold)
                .fontSize(18)

              Column() {
                if (this.viewModel.videoDetailInfo.updateTime) {
                  Text(this.viewModel.videoDetailInfo.updateTime)
                    .fontColor($r('app.color.color_text_normal'))
                    .fontSize(12)
                }
                if (this.viewModel.videoDetailInfo.category) {
                  Text(`分类：${this.viewModel.videoDetailInfo.category}`)
                    .fontColor($r('app.color.color_text_normal'))
                    .fontSize(12)
                }
                if (this.viewModel.videoDetailInfo.desc) {
                  Row() {
                    Text(this.viewModel.videoDetailInfo.desc)
                      .fontColor($r('app.color.color_text_normal'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .fontSize(12)
                      .layoutWeight(1)
                    Image($r('app.media.ic_enter'))
                      .width(18)
                      .height(24)
                      .objectFit(ImageFit.Contain)
                  }
                  .onClick(() => {
                    this.viewModel.panelContentType = 0;
                    this.panelController.show();
                  })
                }
              }
              .margin({ top: 8 })
              .alignItems(HorizontalAlign.Start)
            }
            .height('100%')
            .layoutWeight(1)
            .margin({ right: 16 })
            .justifyContent(FlexAlign.SpaceBetween)

            Image(this.viewModel.videoDetailInfo.coverUrl)
              .alt($r('app.media.pic_load_failed'))
              .objectFit(ImageFit.Cover)
              .aspectRatio(0.7)
              .height('100%')
              .borderRadius(8)
              .shadow({
                radius: 12,
                color: AnimeState.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#333333' : '#aaaaaa',
                offsetX: 6,
                offsetY: 6
              })
              .onClick(() => {
                this.viewModel.panelContentType = 0;
                this.panelController.show();
              })
          }
          .width('100%')
          .height(140)
          .padding(16)

          this.ButtonGroup()
          this.EpisodeList()
          this.GuessYouLike()

          Text("没有更多了")
            .fontSize(14)
            .textAlign(TextAlign.Center)
            .margin({ top: 16, bottom: 52 })
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minHeight: '100%' })
      }
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .height('100%')
    }
    .backgroundColor($r('app.color.background_color'))
    .width('100%')
    .height('100%')
  }

  /**
   * 视频详情二级界面根
   */
  @Builder SecondaryContent() {
    Column() {
      Row() {
        Text(this.viewModel.panelContentType == 0 ? '详情'
          : this.viewModel.panelContentType == 1 ? '缓存' : '播放设置')
          .fontColor($r('app.color.color_text_major'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
        Blank()
        Image($r('app.media.ic_close'))
          .width(32).height(32)
          .onClick(() => {
            this.panelController.close();
          })
      }
      .padding({ left: 16, top: 16, right: 16, bottom: 8 })
      .width('100%')
      if (this.viewModel.panelContentType == 0) {
        // 详情页
        Scroll() {
          Column() {
            this.VideoDetail()
          }
          .alignItems(HorizontalAlign.Start)
          .constraintSize({ minHeight: '100%' })
        }
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
        .height('100%')
      } else if (this.viewModel.panelContentType == 1) {
        // 缓存页
        VideoCacheList({ videoDetailInfo: this.viewModel.videoDetailInfo })
      } else {
        // 播放设置页
        this.PlayerSettingsPanel()
      }
    }
    .backgroundColor($r('app.color.background_color'))
    .width('100%')
    .height('100%')
  }

  /**
   * 视频详情二级界面
   */
  @Builder VideoDetail() {
    Column() {
      Row() {
        Image(this.viewModel.videoDetailInfo.coverUrl)
          .alt($r('app.media.pic_load_failed'))
          .objectFit(ImageFit.Cover)
          .height('100%')
          .aspectRatio(0.7)
          .borderRadius(8)
          .borderColor('#cccccc')
          .shadow({
            radius: 12,
            color: AnimeState.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#333333' : '#aaaaaa',
            offsetX: 6,
            offsetY: 6
          })

        Column() {
          Text(this.viewModel.videoDetailInfo.title)
            .alignSelf(ItemAlign.Start)
            .fontColor($r('app.color.color_text_major'))
            .fontSize(16)

          Column() {
            if (this.viewModel.videoDetailInfo.updateTime) {
              Text(this.viewModel.videoDetailInfo.updateTime).fontSize(12)
            }
            if (this.airDateText !== '') {
              Text(this.airDateText).fontSize(12)
            }
            if (this.viewModel.videoDetailInfo.category) {
              Text(`分类：${this.viewModel.videoDetailInfo.category}`).fontSize(12)
            }
          }
          .alignItems(HorizontalAlign.Start)
        }
        .height('100%')
        .layoutWeight(1)
        .margin(8)
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
      .height(160)
      .padding(16)

      if (this.viewModel.videoDetailInfo.desc) {
        Header('简介')
        Text(this.viewModel.videoDetailInfo.desc)
          .fontColor($r('app.color.color_text_normal'))
          .fontSize(12)
          .padding(16)
      }
      if (this.viewModel.videoDetailInfo.protagonist) {
        Header('角色声优')
        Text(this.viewModel.videoDetailInfo.protagonist)
          .fontColor($r('app.color.color_text_normal'))
          .fontSize(12)
          .padding(16)
      }
      if (this.viewModel.videoDetailInfo.director) {
        Header('制作信息')
        Text(this.viewModel.videoDetailInfo.director)
          .fontColor($r('app.color.color_text_normal'))
          .fontSize(12)
          .padding(16)
      }
      if (this.viewModel.videoDetailInfo.actors) {
        Header('主演')
        Text(this.viewModel.videoDetailInfo.actors)
          .fontColor($r('app.color.color_text_normal'))
          .fontSize(12)
          .padding(16)
      }
      if (this.viewModel.videoDetailInfo.tags) {
        Header('标签')
        Text(this.viewModel.videoDetailInfo.tags)
          .fontColor($r('app.color.color_text_normal'))
          .fontSize(12)
          .padding(16)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
  }

  /** 播出年月（详情扩展字段 year/month，任一存在即显示） */
  private get airDateText(): string {
    const info = this.viewModel.videoDetailInfo
    const year = (info.year ?? '').trim()
    const month = (info.month ?? '').trim()
    if (year !== '' && month !== '') {
      return `${year} · ${month}`
    }
    return year !== '' ? year : month
  }

  /** 播放设置面板数据（getter 每次求值，读 appSettings/viewModel 最新值保证选中态同步） */
  private get settingsItems(): CustomItemInfo[] {
    return [
      new CustomItemInfo({
        id: 'ps_default_player',
        title: '播放器',
        subtitle: '切换后从当前进度续播',
        type: ItemActionType.MENU,
        value: appSettings.default_player,
        menuOptions: [
          new MenuOption('av', 'AVPlayer'),
          new MenuOption('mpv', 'MPVPlayer'),
          new MenuOption('ijk', 'IjkPlayer'),
          new MenuOption('video', 'VideoPlayer'),
          new MenuOption('red', 'RedPlayer(仅本地)')
        ],
        onChange: (value) => {
          if (appSettings.default_player == value) {
            return
          }
          // 记录当前进度，切换后从该处续播
          const resumePos = this.playerManager.getCurrentPosition()
          appSettings.default_player = value as string
          const eventData: emitter.EventData = { data: { 'resumePos': resumePos } }
          PLAYER_SWITCH_EVENT.emit(emitter.EventPriority.LOW, eventData)
        }
      }),
      new CustomItemInfo({
        id: 'ps_video_fit',
        title: '画面尺寸',
        type: ItemActionType.MENU,
        value: String(this.viewModel.videoFit),
        menuOptions: [
          new MenuOption(String(VideoFit.Contain), '适应'),
          new MenuOption(String(VideoFit.Cover), '填充'),
          new MenuOption(String(VideoFit.Fill), '拉伸'),
          new MenuOption(String(VideoFit.Fit_16_9), '16:9'),
          new MenuOption(String(VideoFit.Fit_4_3), '4:3'),
          new MenuOption(String(VideoFit.Fit_1_1), '1:1')
        ],
        onChange: (value) => {
          this.playerManager.setVideoFit(Number(value) as VideoFit)
        }
      }),
      new CustomItemInfo({
        id: 'ps_episodes_order',
        title: '剧集排序',
        type: ItemActionType.MENU,
        value: appSettings.episodes_order as string,
        menuOptions: [new MenuOption('asc', '正序'), new MenuOption('desc', '倒序')],
        onChange: (value) => {
          appSettings.episodes_order = value as 'asc' | 'desc'
        }
      }),
      new CustomItemInfo({
        id: 'ps_auto_rotate',
        title: '自动全屏',
        subtitle: '手机横屏时自动进入全屏',
        type: ItemActionType.TOGGLE,
        value: appSettings.auto_sensor_rotate,
        onChange: (value) => {
          appSettings.auto_sensor_rotate = value as boolean
          this.applyAutoRotateOrientation(value as boolean)
        }
      }),
      new CustomItemInfo({
        id: 'ps_auto_next',
        title: '自动播放下一集',
        subtitle: '视频结束后自动播放下一集',
        type: ItemActionType.TOGGLE,
        value: appSettings.auto_play_next_episode,
        onChange: (value) => {
          appSettings.auto_play_next_episode = value as boolean
        }
      }),
      new CustomItemInfo({
        id: 'ps_auto_play_no_wifi',
        title: '非Wifi下自动播放',
        subtitle: '非Wifi环境下不再提醒，自动播放视频',
        type: ItemActionType.TOGGLE,
        value: appSettings.auto_play_on_no_wifi,
        onChange: (value) => {
          appSettings.auto_play_on_no_wifi = value as boolean
        }
      }),
      new CustomItemInfo({
        id: 'ps_auto_pip',
        title: '退出播放页自动小窗',
        subtitle: '返回、导航、后台时自动进入画中画',
        type: ItemActionType.TOGGLE,
        value: appSettings.auto_pip_on_exit,
        onChange: (value) => {
          appSettings.auto_pip_on_exit = value as boolean
        }
      })
    ].filter((item: CustomItemInfo) => {
      // 小窗播放仅支持部分播放器后端：选了不支持的后端时隐藏自动小窗开关
      if (item.id === 'ps_auto_pip') {
        return PiPManager.isPlayerSupported(appSettings.default_player)
      }
      return true
    })
  }

  /** 播放设置面板内容（简介同款半模态面板内展示） */
  @Builder PlayerSettingsPanel() {
    Scroll() {
      Column() {
        ForEach(this.settingsItems, (item: CustomItemInfo) => {
          CustomListItem({
            item: item,
            itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
          })
        }, (item: CustomItemInfo) => item.id)
      }
      .width('100%')
      .padding({ top: 4, bottom: 16 })
      .constraintSize({ minHeight: '100%' })
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height('100%')
  }

  /** 自动全屏开关联动窗口方向（与播放器控制层面板逻辑一致） */
  private applyAutoRotateOrientation(isOn: boolean): void {
    if (this.viewModel.isFullScreen) {
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

  /**
   * 视频剧集列表
   */
  @Builder EpisodeList() {
    ForEach(this.viewModel.videoDetailInfo.episodes, (episodeList: EpisodeList, episodeListIndex: number) => {
      Column() {
        Row() {
          Row()
            .height(14)
            .width(6)
            .margin({ right: 2 })
            .borderRadius(4)
            .backgroundColor($r('app.color.primary_color'))
          Text(episodeList.title)
            .fontColor($r('app.color.color_text_major'))
            .fontSize(16)
            .fontWeight(500)
          Blank()
          // 剧集排序快捷开关：点击切换正序/倒序，列表实时重排
          Row({ space: 4 }) {
            SymbolGlyph(appSettings.episodes_order === 'asc'
              ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
              .fontSize(12)
              .fontColor([$r('app.color.color_text_normal')])
            Text(appSettings.episodes_order === 'asc' ? '正序' : '倒序')
              .fontColor($r('app.color.color_text_normal'))
              .fontSize(12)
          }
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor($r('app.color.background_color_accent'))
          .onClick(() => {
            appSettings.episodes_order = appSettings.episodes_order === 'asc' ? 'desc' : 'asc'
          })
        }
        .width('100%')
        .padding({ left: 16, top: 16, right: 16, bottom: 4 })
        Flex({ alignItems: ItemAlign.Start, justifyContent: FlexAlign.Start, wrap: FlexWrap.Wrap }) {
          ForEach(sortEpisodesByNumber(episodeList.episodes, appSettings.episodes_order), (item: EpisodeInfo) => {
            Text(item.title)
              .textAlign(TextAlign.Center)
              .backgroundColor(
                (this.viewModel.episodeListIndex == episodeListIndex
                  && episodeList.episodes[this.viewModel.episodeIndex] === item)
                  ? '#bb3366ff' : $r('app.color.background_color_accent')
              )
              .fontColor(
                (this.viewModel.episodeListIndex == episodeListIndex
                  && episodeList.episodes[this.viewModel.episodeIndex] === item)
                  ? Color.White : $r('app.color.color_text_major')
              )
              .fontSize(12)
              .padding({ top: 8, bottom: 8 })
              .borderRadius(6)
              .borderWidth(
                (this.viewModel.episodeListIndex == episodeListIndex
                  && episodeList.episodes[this.viewModel.episodeIndex] === item)
                  ? 0 : 1.5
              )
              .borderColor($r('app.color.background_color_accent'))
              .margin({ bottom: 8, right: '2%' })
              .width(this.viewModel.isFullScreen ? '17%' : '18%')
              .maxLines(1)
              .onClick(() => {
                // 显示顺序可能被排序打乱，按剧集对象映射回规范索引
                const canonicalIdx = episodeList.episodes.indexOf(item)
                if (this.viewModel.episodeListIndex == episodeListIndex
                  && this.viewModel.episodeIndex == canonicalIdx) {
                  return;
                }
                this.viewModel.historyInfo.videoProgress = 0;
                this.viewModel.historyInfo.currentTime = 0;
                this.viewModel.historyInfo.totalTime = 0;
                this.viewModel.playVideo(episodeListIndex, canonicalIdx);
              })
          })
        }
        .width('100%')
        .margin({ top: 8 })
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    })
  }

  /**
   * 猜你喜欢
   */
  @Builder GuessYouLike() {
    Column() {
      Header('猜你喜欢')
      VideoList({
        videoList: this.viewModel.videoDetailInfo.recommends,
        scrollable: false,
        isFullList: false
      })
        .padding({ left: 16, right: 16 })
        .margin({ top: 8 })
    }
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 收藏、缓存、分享按钮
   */
  @Builder ButtonGroup() {
    Row() {
      // 收藏
      if (!this.viewModel.isCollect) {
        this.IconWithText($r('app.media.ic_collection'), "收藏", () => {
          this.viewModel.collect();
        })
      } else {
        this.IconWithText($r('app.media.ic_collected2'), "已收藏", () => {
          this.viewModel.removeCollect();
        })
      }
      // 缓存
      this.IconWithText(
        $r('app.media.ic_download2'),
        '缓存',
        () => {
          this.viewModel.panelContentType = 1;
          this.panelController.show()
        })
      // 分享
      this.IconWithText($r('app.media.ic_share'), "分享", () => {
        ToastUtil.showToast({ message: "开发中" });
      })
    }
    .justifyContent(FlexAlign.SpaceEvenly)
    .width('100%')
  }

  /**
   * 按钮构建-图标 + 文字 上下排列
   */
  @Builder IconWithText(src: ResourceStr, text: ResourceStr, onClick?: (event?: ClickEvent) => void) {
    Column() {
      Image(src)
        .fillColor($r('app.color.color_text_normal'))
        .width(20)
        .height(20)
      Text(text)
        .fontSize(10)
        .width(40)
        .fontColor($r('app.color.color_text_normal'))
        .textAlign(TextAlign.Center)
        .margin({ top: 4 })
    }
    .backgroundColor(
      this.viewModel.isBackgroundLoaded ? '#aaffffff' : $r('app.color.background_color_accent')
    )
    .padding({ left: 20, top: 8, right: 20, bottom: 8 })
    .borderRadius(12)
    .borderWidth(1.5)
    .borderColor($r('app.color.background_color_accent'))
    .onClick(onClick)
  }

}
