import { MultiVideoPlayer } from '../player/MultiVideoPlayer';
import IPlayerManager from '../player/model/IPlayerManager';
import CustomPanel, { PanelController } from '../components/CustomPanel';
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

  aboutToDisappear() {
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
    Web({ src: AnimeState.webviewUrl, controller: this.webviewController })
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
              this.webviewController.runJavaScript(AnimeState.runJs)
                .then((result) => {
                  console.info(`URL ${e.url} 执行 result: ${result}`)
                  AnimeState.webJsVideoLink = JSON.parse(result)
                  AnimeState.showWebView = false
                  console.info(`URL ${e.url} 显示状态: ${AnimeState.showWebView} 解析后链接：${AnimeState.webJsVideoLink}`)
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
          .padding({ top: this.viewModel.isFullScreen ? 0 : AnimeState.topRectHeight })
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
          ForEach(sortEpisodesByNumber(episodeList.episodes, appSettings.episodes_order), (item: EpisodeInfo, episodeIndex: number) => {
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
              .width(this.viewModel.isFullScreen ? '17%' : '18%')
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
