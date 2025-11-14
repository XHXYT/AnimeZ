// VideoDetailPage.ets
import { MultiVideoPlayer } from '../player/MultiVideoPlayer';
import IPlayerManager, { PlayerStatus } from '../player/model/IPlayerManager';
import CustomPanel, { PanelController } from '../components/CustomPanel';
import StateView from '../components/StateView';
import { VideoList } from '../components/VideoList';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { VideoNavigateInfo } from '../entity/VideoNavigateInfo';
import { ToastUtil } from '../utils/ToastUtils';
import { AppConfigs } from '../entryability/Settings';
import {
  VideoDetailGridColHeight,
  VideoDetailGridColSpan,
  VideoDetailNewGridColSpan,
  VideoPlayerGridColSpan,
  VideoPlayerNewGridColSpan
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

// 系统路由
@Builder
export function VideoDetailPageBuilder(name: string, param: Object) {
  VideoDetailPage()
}

@Entry
@Component
struct VideoDetailPage {

  @State state: number = 0
  @State errorMessage: string = ''
  @State isFullScreen: boolean = false

  @Consume('pageStack') pageStack: NavPathStack;
  @StorageLink('showWebView') showWebView: boolean = false
  @StorageProp('webview_url') webUrl: string = ''
  @StorageProp('run_js') runJavaScript: string = ''
  @StorageLink('web_js_video_link') videJsLink: string = ''

  @StorageProp('topRectHeight') topHeight: number = 0;
  @StorageProp('bottomRectHeight') bottomHeight: number = 0;
  @StorageLink('currentWidthBreakpoint') widthBp: WidthBreakpoint = 1;
  @StorageLink('currentHeightBreakpoint') heightBp: HeightBreakpoint = 0;
  @Consume @Watch('onPhoneLandscape') isPhoneLandscape: boolean;
  @StorageLink('currentColorMode') currentMode: number = ThemeColorMode.SYSTEM

  @State @Watch('onViewModelChange') viewModel: VideoDetailViewModel = new VideoDetailViewModel(
    new PlayerManagerImpl(),
    new AppConfigs(),
    this.getUIContext().getHostContext()!
  )
  @State playerManager: IPlayerManager = new PlayerManagerImpl()
  @State panelController: PanelController = new PanelController()
  // 应用设置
  @StorageLink('AppSettings') appSettings: AppConfigs = new AppConfigs()
  private webviewController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear() {
    this.viewModel = new VideoDetailViewModel(this.playerManager, this.appSettings, this.getUIContext().getHostContext()!)
    this.viewModel.setOnStatusChangedCallback((status: number) => {
      // 处理状态变化
      if (status == PlayerStatus.ERROR) {
        this.errorMessage = this.viewModel.errorMessage
      }
    });

    this.viewModel.setOnFullScreenChangedCallback((isFullScreen: boolean) => {
      // 处理全屏变化
      this.isFullScreen = isFullScreen
    });

    this.viewModel.setOnProgressChangeCallback((totalTime: number, currentTime: number) => {
      // 处理进度变化
    });
  }

  aboutToDisappear() {
    this.viewModel.onDestroy();
  }

  onPhoneLandscape() {
    this.viewModel.onPhoneLandscape(this.isPhoneLandscape);
  }

  onViewModelChange() {
    this.state = this.viewModel.state
    this.playerManager = this.viewModel.playerManager
  }

  build() {
    NavDestination() {
      Stack() {
        StateView({
          state: this.state,
          errorMessage: this.errorMessage,
          content: () => {
            this.Content()
          },
          custom: undefined,
          onRetry: () => {
            this.viewModel.getDetailInfo();
            return true;
          }
        })
          .width('100%')
          .height('100%')
        // WebView
        if (this.showWebView) {
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
    Web({ src: this.webUrl, controller: this.webviewController })
      .backgroundColor(Color.Transparent)
      .javaScriptAccess(true)
      .width(1).height(1)
      .onPageBegin((event) => {
        console.log(`链接 ${event.url} 成功加载`)
      })
      .onPageEnd(e => {
        try {
          if (e) {
            Logger.e('tips', `URL ${e.url} 开始加载JavaScript`)
            setTimeout(() => {
              // TODO 待修复 webviewController 未绑定上或者绑定了多个 Web 组件
              this.webviewController.runJavaScript(this.runJavaScript)
                .then((result) => {
                  console.info(`URL ${e.url} 执行 result: ${result}`)
                  this.videJsLink = JSON.parse(result)
                  this.showWebView = false
                  console.info(`URL ${e.url} 显示状态: ${this.showWebView} 解析后链接：${this.videJsLink}`)
                })
                .catch((error: BusinessError) => {
                  Logger.e('fail', '加载JavaScript', error)
                })
            }, 4000)
          }
        } catch (error) {
          Logger.e('fail', 'webviewController 加载JavaScript', error)
        }
      })
  }

  @Builder Content() {
    GridRow({ columns: 12 }) {
      // 播放器区
      GridCol({
        span: this.isFullScreen ? VideoPlayerNewGridColSpan : VideoPlayerGridColSpan,
        order: 1
      }) {
        Stack() {
          MultiVideoPlayer({ playerManager: this.playerManager, isFullScreen: this.isFullScreen })
        }
        .width('100%')
        .backgroundColor(Color.Black)
        .alignContent(Alignment.Center)
        .padding({ top: this.isFullScreen ? 0 : this.topHeight - 10 })
        .height(this.isFullScreen ? '100%' : VideoDetailGridColHeight(this.widthBp, this.heightBp))
      }

      // 视频详情区
      GridCol({
        span: this.isFullScreen ? VideoDetailNewGridColSpan : VideoDetailGridColSpan,
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
          .padding({ top: this.isFullScreen ? 0 : this.topHeight - 10 })
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
                color: this.currentMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#333333' : '#aaaaaa',
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
        Text(this.viewModel.panelContentType == 0 ? '详情' : '缓存')
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
      } else {
        // 缓存页
        VideoCacheList({ videoDetailInfo: this.viewModel.videoDetailInfo })
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
            color: this.currentMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#333333' : '#aaaaaa',
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
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
  }

  /**
   * 视频剧集列表
   */
  @Builder EpisodeList() {
    ForEach(this.viewModel.videoDetailInfo.episodes, (episodeList: EpisodeList, episodeListIndex: number) => {
      Column() {
        Header(episodeList.title)
        Flex({ alignItems: ItemAlign.Start, justifyContent: FlexAlign.Start, wrap: FlexWrap.Wrap }) {
          ForEach(sortEpisodesByNumber(episodeList.episodes, this.appSettings.episodes_order), (item: EpisodeInfo, episodeIndex: number) => {
            Text(item.title)
              .textAlign(TextAlign.Center)
              .backgroundColor(
                (this.viewModel.episodeListIndex == episodeListIndex && this.viewModel.episodeIndex == episodeIndex)
                  ? '#bb3366ff' : $r('app.color.background_color_accent')
              )
              .fontColor(
                (this.viewModel.episodeListIndex == episodeListIndex && this.viewModel.episodeIndex == episodeIndex)
                  ? Color.White : $r('app.color.color_text_major')
              )
              .fontSize(12)
              .padding({ top: 8, bottom: 8 })
              .borderRadius(6)
              .borderWidth(
                (this.viewModel.episodeListIndex == episodeListIndex && this.viewModel.episodeIndex == episodeIndex)
                  ? 0 : 1.5
              )
              .borderColor($r('app.color.background_color_accent'))
              .margin({ bottom: 8, right: '2%' })
              .width(this.isFullScreen ? '17%' : '18%')
              .maxLines(1)
              .onClick(() => {
                if (this.viewModel.episodeListIndex == episodeListIndex && this.viewModel.episodeIndex == episodeIndex) {
                  return;
                }
                this.viewModel.historyInfo.videoProgress = 0;
                this.viewModel.historyInfo.currentTime = 0;
                this.viewModel.historyInfo.totalTime = 0;
                this.viewModel.playVideo(episodeListIndex, episodeIndex);
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
