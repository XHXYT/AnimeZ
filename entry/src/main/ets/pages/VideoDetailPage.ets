import mediaquery from '@ohos.mediaquery';
import { MultiVideoPlayer } from '../player/MultiVideoPlayer';
import IPlayerManager, { PlayerListener, PlayerStatus, VideoFit } from '../entity/VideoPlayer/IPlayerManager';
import media from '@ohos.multimedia.media';
import { HISTORY_CHANGED_EVENT } from '../utils/EventBus';
import PlayerManagerImpl from '../entity/VideoPlayer/PlayerManagerImpl';
// import { VideoCacheList } from '../components/VideoCacheList';
import CustomPanel, { PanelController } from '../components/CustomPanel';
import StateView, { ViewState } from '../components/StateView';
import { VideoList } from '../components/VideoList';
import EpisodeInfo from '../entity/EpisodeInfo';
import EpisodeList from '../entity/EpisodeList';
import VideoDetailInfo from '../entity/VideoDetailInfo';
import Logger from '../utils/Logger';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { ShareDialog } from '../components/dialog/ShareDialog';
import { display, promptAction } from '@kit.ArkUI';
import { HistoryInfo, VideoHistoryInfo, videoHistoryInfoDB } from '../database/VideoHistoryInfoDB';
import { CollectionInfo, VideoCollectionInfo, videoCollectionInfoDB } from '../database/VideoCollectionInfoDB';
import { BusinessError, settings } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';
import SystemBarUtils from '../utils/SystemBarUtils';
import { deviceInfo } from '@kit.BasicServicesKit'
import { BreakpointState } from '../utils/BreakPointManager';
import { DEFAULT_DURATION } from '../utils/TransitionHelper';
import { VideoNavigateInfo } from '../entity/VideoNavigateInfo';
import { ToastUtil } from '../utils/ToastUtils';
import { AppConfigs } from '../entryability/Settings';
import { dataSourceManager } from '../api/DataSourceManager';
import {
  VideoDetailGridColHeight,
  VideoDetailGridColSpan,
  VideoDetailNewGridColSpan,
  VideoPlayerGridColSpan, VideoPlayerNewGridColSpan } from '../utils/breakpoint/BreakPoint';


// 系统路由
@Builder
export function VideoDetailPageBuilder(name: string, param: Object) {
  VideoDetailPage()
}

@Entry
@Component
struct VideoDetailPage {
  @State videoDetailInfo: VideoDetailInfo = {
    title: '',
    sourceKey: '',
    coverUrl: '',
    episodes: [],
    recommends: []
  }

  // 收藏判断
  @State isCollect: boolean = false
  @State episodeIndex: number = 0;
  @State errorMessage: string = ''
  @State episodeListIndex: number = 0;
  @State isFullScreen: boolean = false
  /**背景图是否加载完成*/
  @State isBackgroundLoaded: boolean = false
  @Consume('pageStack') pageStack: NavPathStack
  @State state: number = 0
  // 顶部避让高度
  @StorageProp('topRectHeight') topHeight: number = 0
  // 底部避让高度
  @StorageProp('bottomRectHeight') bottomHeight: number = 0
  // 宽度断点
  @StorageLink('currentWidthBreakpoint') widthBp: WidthBreakpoint = 1
  // 高度断点
  @StorageLink('currentHeightBreakpoint') heightBp: HeightBreakpoint = 0
  // 手机横屏
  @Consume @Watch('onPhoneLandscape') isPhoneLandscape: boolean
  // 颜色模式
  @StorageLink('currentColorMode') currentMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT

  // 视频页面链接
  private url: string = ''
  // 加载webview
  private showWebview: boolean = false
  // 视频唯一标识符
  private videoID: number | null = -1
  // 视频收藏标识
  private collectID: number | null = 0
  private sourceKey: string = ''
  private title: string = ''
  private isFirstPlay: boolean = true
  @State playerManager: IPlayerManager = new PlayerManagerImpl()
  // 应用设置
  @StorageLink('AppSettings') appSettings: AppConfigs = new AppConfigs()
  // 收藏信息
  @State collectionInfo: VideoCollectionInfo = CollectionInfo
  // 历史信息
  private historyInfo: VideoHistoryInfo = HistoryInfo
  // 是否处于自由多窗 TODO 等待相应API
  @State isFreeWindow: boolean = false

  /**
   * 二级面板内容类型
   */
  @State panelContentType: number = 0
  private readonly panelController: PanelController = new PanelController()
  private pausedOnHide = false
  private readonly playerListenerD: PlayerListener = {
    onStatusChanged: (status: number) => {
      if (status == PlayerStatus.DONE) {
        if (this.appSettings.auto_play_next_episode && this.videoDetailInfo.episodes !== undefined) {
          let episodeList = this.videoDetailInfo.episodes[this.episodeListIndex]
          if (this.episodeIndex < episodeList.episodes.length - 1) {
            this.playVideo(this.episodeListIndex, this.episodeIndex + 1)
          }
        }
      }
      return
    },
    onEpisodeChanged: (episodeList: EpisodeInfo[], episodeIndex: number) => {
      if (this.episodeIndex == episodeIndex) {
        return
      }
      this.episodeIndex = episodeIndex
      this.playVideo(this.episodeListIndex, this.episodeIndex)
      return
    },
    onVideoSpeedChanged: (videoSpeed: media.PlaybackSpeed) => {},
    onFullScreenChanged: (isFullScreen: boolean) => {
      // console.log('VideoDetailPage #onFullScreenChanged isFullScreen：', isFullScreen)
      this.getUIContext()?.animateTo({
        duration: DEFAULT_DURATION ,
        curve: Curve.Ease
      }, () => {
        this.isFullScreen = isFullScreen
      })
      // console.log('VideoDetailPage #onFullScreenChanged isFullScreen：', this.isFullScreen)
    },
    onVideoFitChanged: (videoFit: VideoFit): VideoFit => {
      return videoFit
    },
    onVideoSizeChange: (w: number, h: number) => {},
    onProgressChange: (totalTime: number, currentTime: number) => {
      Logger.e('tips', 'totalTime=' + totalTime + ' currentTime=' + currentTime)
      if (this.historyInfo) {
        this.historyInfo.totalTime = totalTime
        this.historyInfo.currentTime = currentTime
        console.log('VideoTest #onProgressChange 视频进度调用保存')
        this.saveHistoryInfo()
      }
      return
    },
    onBuffering: (type: media.BufferingInfoType, value: number): number => {
      return value
    },
  }

  private controller: webview.WebviewController = new webview.WebviewController()

  // 用于捕获视频链接
  private jsStr: string = `var video = document.querySelector("#artplayer > div > video");
            video ? video.src : "元素未找到或没有src属性";`

  /**
   * TODO 跟随重力感应旋转屏幕全屏, 仅手机生效
   */
  onPhoneLandscape() {
    console.log('VideoDetailPage #aboutToAppear 自动旋屏启用状态： ', this.appSettings.auto_sensor_rotate)
    console.log('VideoDetailPage #aboutToAppear 手机横屏启用状态： ', this.isPhoneLandscape)
    if (this.isPhoneLandscape) {
      // 横屏进入全屏
      this.playerManager.enterFullScreen()
    } else {
      // 竖屏退出全屏
      this.pageStack.pop(true)
      // setTimeout(() => {this.pageStack.pop(true)}, 300)
    }
  }

  aboutToAppear() {
    this.state = 0
    this.playerManager.addListener(this.playerListenerD)
    if (this.videoDetailInfo) {
      if (this.pausedOnHide) {
        if (!this.playerManager.isPlaying()) {
          this.playerManager.start()
        }
        this.pausedOnHide = false
      }
    }
   }

  aboutToDisappear() {
    console.log('VideoTest #aboutToDisappear 页面销毁调用保存')
    this.saveHistoryInfo()
    promptAction.showToast({ message: '历史记录已保存' })
    console.log('VideoTest #aboutToDisappear 已运行完保存历史记录')
    HISTORY_CHANGED_EVENT.emit()
    this.playerManager.removeListener(this.playerListenerD)
    this.playerManager.destroy()
    if (this.playerManager.isPlaying()) {
      this.playerManager.pause()
      this.pausedOnHide = true
    } else {
      this.pausedOnHide = false
    }
  }

  /**检查视频历史信息*/
  async checkVideoInfo() {
    // 查询并初始化列表数据
    // 根据 title 查找视频历史记录
    const HistoryList = await videoHistoryInfoDB.query(this.title)
    console.log('VideoTest #checkVideoInfo 查到的历史记录：', JSON.stringify(HistoryList))
    if (HistoryList.length !== 0) {
      // 非新增视频，提取出历史记录
      const HistoryDetail = HistoryList[0]
      console.log('VideoTest #checkVideoInfo 将要替换的历史记录：', JSON.stringify(HistoryDetail))
      // 如果有历史记录详情，回显到页面中
      if (HistoryDetail) {
        this.historyInfo = HistoryDetail
        // 及时更新视频id
        this.videoID = this.historyInfo.id
        console.log('VideoTest #checkVideoInfo 替换的历史记录：', JSON.stringify(this.historyInfo))
      }
    } else {
      // 为新增视频
      console.log('VideoTest #checkVideoInfo 新增视频')
      return
    }
  }

  /**检查视频收藏信息*/
  private async checkCollectionInfo() {
    console.log('VideoCollectionDetail #checkCollectionInfo 视频id状况：', this.videoID)
    const CollectionList = await videoCollectionInfoDB.query(this.title)
    if (CollectionList) {
      const CollectionDetail = CollectionList[0]
      this.collectionInfo = CollectionDetail
      if (this.collectionInfo !== undefined && this.videoID !== null) {
        this.isCollect = true
      }
      console.log('VideoCollectionDetail #checkCollectionInfo 视频收藏状况：', JSON.stringify(this.collectionInfo))
    }
  }

  private getDetailInfo() {
    console.log(`VideoTest #getDetailInfo当前数据源: ${this.sourceKey}`)
    dataSourceManager.getVideoDetailInfo(this.url)
      .then(async (info) => {
        this.videoDetailInfo = info
        this.historyInfo.link = this.videoDetailInfo.url as string // 保存页面链接
        this.historyInfo.title = this.videoDetailInfo.title
        this.historyInfo.coverUrl = this.videoDetailInfo.coverUrl
        this.historyInfo.sourceKey = this.sourceKey
        this.state = ViewState.CONTENT
        // 设置状态栏
        SystemBarUtils.setWindowSystemBarTransparent(true)
        this.playVideo(this.historyInfo.episodeListIndex, this.historyInfo.episodeIndex)
      })
      .catch((e: Error) => {
        this.errorMessage = JSON.stringify(e)
        Logger.e('tips', 'VideoTest #getDetailInfo error = ' + this.errorMessage)
        this.state = ViewState.ERROR
      })
  }

  private playVideo(episodeListIndex: number, episodeIndex: number) {
    Logger.e('tips', 'playVideo episodeListIndex = ' + episodeListIndex + " episodeIndex=" + episodeIndex)
    // 跳转至历史记录的播放列表
    this.episodeListIndex = episodeListIndex
    // 跳转至历史记录的播放集数
    this.episodeIndex = episodeIndex
    const episodeList = this.videoDetailInfo.episodes[this.episodeListIndex]
    Logger.e('tips', 'VideoTest #playVideo historyInfo=' + JSON.stringify(episodeList))
    let episode = episodeList.episodes[this.episodeIndex];
    Logger.e('tips', 'playVideo episode=' + JSON.stringify(episode))
    this.historyInfo.episodeListIndex = episodeListIndex
    this.historyInfo.episodeIndex = episodeIndex
    this.historyInfo.episodeName = episode.title
    this.historyInfo.videoUrl = episode.videoUrl as string
    Logger.e('tips', 'VideoTest #playVideo historyInfo=' + JSON.stringify(this.historyInfo))
    if (episode.videoUrl) {
      console.log('VideoTest #playVideo 存在视频链接的视频播放调用保存')
      this.saveHistoryInfo()
      // 保存后检查更新id
      this.checkVideoInfo()
      this.playerManager.playEpisodeList(episodeList.episodes, this.episodeIndex)
    } else {
      // 查找视频播放链接
      dataSourceManager.parseVideoUrl(episode.link)
        .then((url) => {
          // if (this.videoDetailInfo.sourceKey !== 'key_agedmvideo') {
          //
          // } else {
          //   // AGE动漫源需要调用webview组件获取视频链接
          //   this.controller.loadUrl(url)
          //   Logger.e(this, '#parseVideoUrl 接收的云播放器link = ' + url)
          // }
          this.showWebview = false
          episode.videoUrl = url
          this.historyInfo.videoUrl = url
          console.log('VideoTest #playVideo 网络请求的视频链接时的视频播放调用保存')
          this.saveHistoryInfo()
          // 保存后检查更新历史记录id
          this.checkVideoInfo()
          this.playerManager.playEpisodeList(episodeList.episodes, this.episodeIndex)
        })
        .catch((e: Error) => {
          this.playerManager.setStatus(PlayerStatus.ERROR)
          Logger.e('tips', 'parseVideoUrl failed! e=' + JSON.stringify(e))
        })
    }
  }

  private async saveHistoryInfo() {
    if (this.historyInfo) {
      if (this.videoID !== null) {
        // 如果有 id 调用修改 update
        this.historyInfo.id = this.videoID
        this.historyInfo.accessTime = new Date().getTime()
        console.log('VideoTest #saveHistoryInfo 视频详情页将要保存的历史记录：', JSON.stringify(this.historyInfo))
        await videoHistoryInfoDB.update(this.historyInfo, this.videoID)
          .then((updateId) => {
            console.log('VideoTest #saveHistoryInfo 更新成功id为：', updateId)
          })
          .catch((error: BusinessError) => {
            console.error("VideoTest #saveHistoryInfo 更新操作失败: ", error)
          })
      } else {
        this.historyInfo.id = this.videoID
        // 没有 id 调用新增 insert
        await videoHistoryInfoDB.insert(this.historyInfo)
          .then((insertId) => {
            console.log('VideoTest #saveHistoryInfo 插入成功id为：', insertId)
            // 及时更新视频id
            this.videoID = insertId
          })
          .catch((error: Error) => {
            console.error("VideoTest #saveHistoryInfo 插入操作失败: ", error)
          })
      }

    }
  }

  /**移除收藏*/
  private async removeCollect() {
    if (this.collectID !== null) {
      await videoCollectionInfoDB.delete(this.collectID)
      this.isCollect = false
      promptAction.showToast({ message: "取消收藏" })
    }
  }
  /**收藏*/
  private async collect() {
    if(this.videoDetailInfo.title !== undefined && this.videoDetailInfo.coverUrl !== undefined) {
      const theTollectionInfo: VideoCollectionInfo = {
        id: this.collectID,
        link: this.url,
        title: this.videoDetailInfo.title,
        coverUrl: this.videoDetailInfo.coverUrl,
        sourceKey: this.sourceKey,
        accessTime: Date.now()
      }
      if (this.collectID === null) {
        console.log('VideoCollectionDetail #collect 插入视频收藏id状况：', this.collectID)
        // 没有 id 调用新增 insert
        await videoCollectionInfoDB.insert(theTollectionInfo)
          .then((insertId) => {
            console.log('VideoCollect #collect 插入成功收藏id为：', insertId)
            this.isCollect = true
            promptAction.showToast({ message: "收藏成功" })
          })
          .catch((error: Error) => {
            console.error("VideoCollect #collect 插入操作失败: ", error)
          })
      } else {
        console.log('VideoCollectionDetail #collect 更新视频收藏id状况：', this.collectID)
        // 如果有 收藏id 调用修改 update
        await videoCollectionInfoDB.update(theTollectionInfo)
          .then((insertId) => {
            console.log('VideoCollect #collect 更新成功收藏id为：', insertId)
            this.isCollect = true
            promptAction.showToast({ message: "收藏成功" })
          })
          .catch((error: Error) => {
            console.error("VideoCollect #collect 更新操作失败: ", error)
          })
      }

    }
  }

  build() {
    NavDestination() {
      Stack() {
        StateView(
          {
            state: this.state,
            errorMessage: this.errorMessage,
            content: () => {
              this.Content()
            },
            custom: undefined,
            onRetry: () => {
              this.getDetailInfo()
              return true;
            }
          }
        )
          .width('100%')
          .height('100%')
      }
      .width('100%')
      .height('100%')
    }.hideToolBar(true)
    .hideTitleBar(true)
    .backgroundColor($r('app.color.background_color'))
    .onReady(async (ctx: NavDestinationContext) => {
      // 接收信息
      try {
        const params: VideoNavigateInfo = ctx?.pathInfo?.param as VideoNavigateInfo
        this.url = params.url as string
        this.videoID = params.id
        this.collectID = params.id
        this.title = params.title
        this.sourceKey = params.sourceKey as string
        if (this.videoID !== null) {
          this.isFirstPlay = false
        }
        console.log('VideoTest 视频详情页接收的videoID：', JSON.stringify(this.videoID))
        // 首次打开检查一次视频id
        await this.checkVideoInfo()
        // 根据源获取视频数据
        this.getDetailInfo()
        // 检查收藏信息
        this.checkCollectionInfo()
        console.log('VideoTest 视频详情页接收的params：', JSON.stringify(params))
      } catch (e) {
        console.log(`VideoTest Navigate onReady catch exception: ${JSON.stringify(e)}`)
      }
    })
    .onBackPressed(() => {
      console.log('VideoDetailPage #onBackPressed')
      console.log('VideoDetailPage #onBackPressed isFullScreen：', this.isFullScreen)
      if (!this.panelController.isShow() && !this.isFullScreen) {
        // 还原状态栏颜色
        SystemBarUtils.setWindowSystemBarTransparent(false)
        return false
      }
      if (this.panelController.isShow()) {
        // 关闭详情页二级面板
        this.panelController.close()
        return true
      }
      if (this.isFullScreen) {
        // 退出全屏
        this.getUIContext()?.animateTo({
          duration: DEFAULT_DURATION,
          curve: Curve.Ease
        }, () => {
          this.isFullScreen = false
          this.playerManager.exitFullScreen()
        })
        return true
      }
      return true
    })
  }

  @Builder Content() {
    GridRow() {
      // 播放器区
      GridCol({
        span: this.isFullScreen ? VideoPlayerNewGridColSpan : VideoPlayerGridColSpan,
        order: 1
      }) {
        Stack() {
          // 复合型播放器
          MultiVideoPlayer({ playerManager: this.playerManager })
          // webview加载
          if (this.showWebview) {
            /*Column() {
              // webview加载
              Web({ src: '', controller: this.controller })
                .fileAccess(true)
                .imageAccess(true)
                .databaseAccess(true)
                .onlineImageAccess(true)
                .javaScriptAccess(true)
                .domStorageAccess(true)
                .onPageBegin((event) => {
                  console.log('parseVideoUrl #webview', `onPageBegin= ${JSON.stringify(event)}`)
                })
                .onPageEnd(e => {
                  try {
                    // 延迟3秒执行查询视频src的脚本
                    setTimeout(() => {
                      this.controller.runJavaScript(this.jsStr)
                        .then((result) => {
                          console.log('parseVideoUrl #webview 延迟加载的视频src:', result)
                          this.historyInfo.videoUrl = result
                          let episodeList = this.videoDetailInfo.episodes[this.episodeListIndex]
                          episodeList.episodes[this.episodeIndex].videoUrl = result
                          console.log('VideoTest #playVideo webview捕获的视频链接时的视频播放调用保存')
                          this.saveHistoryInfo()
                          // 保存后检查更新历史记录id
                          this.checkVideoInfo()
                          this.showWebview = false
                          // this.playerManager.playEpisodeList(episodeList.episodes, this.episodeIndex)
                        })
                        .catch((error: BusinessError) => {
                          console.error("parseVideoUrl #webview Error:", error)
                        })
                    }, 3000)
                    if (e) {
                      console.info('parseVideoUrl #webview 页面加载完成，URL:', e.url)
                    }
                  } catch (error) {
                    console.error(`parseVideoUrl #webview 错误代码: ${(error as BusinessError).code}, 消息: ${(error as BusinessError).message}`)
                  }
                })
            }
            .borderWidth(2)
            .borderColor(Color.Red)
            .backgroundColor(Color.Green)
            .zIndex(1)
            .constraintSize({minHeight: 20, maxHeight: 200})*/
          }
        }.width('100%')
        .backgroundColor(Color.Black)
        .alignContent(Alignment.Center)
        .padding({top: this.isFullScreen ? 0 : this.topHeight - 10})
        .height(VideoDetailGridColHeight(this.widthBp))
      }
      // 视频详情区
      GridCol({
        span: this.isFullScreen ? VideoDetailNewGridColSpan : VideoDetailGridColSpan,
        order: 2
      }) {
        if (this.videoDetailInfo) {
          Stack() {
            // Image(this.videoDetailInfo.coverUrl)
            //   .objectFit(ImageFit.Cover)
            //   .height('100%')
            //   .width('100%')
            //   .onComplete(() => {
            //     // TODO 背景加载完成
            //     this.isBackgroundLoaded = true;
            //   })
            //   .blur(16)
            // 主详情
            this.RootContent()
            // 详情二级页面
            CustomPanel(
              {
                controller: this.panelController,
                panelContent: () => {
                  this.SecondaryContent()
                }
              }
            )
              .hitTestBehavior(HitTestMode.None)
              .width('100%')
              .height('100%')
          }
          .width('100%')
          .layoutWeight(1)
          .padding({top: this.isFullScreen ? 0 : this.topHeight - 10})
        }
      }.layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    // .borderWidth(2)
    // .borderColor(Color.Red)
    .backgroundColor($r('app.color.background_color'))
  }

  /**视频根内容，包括视频信息、视频播放列表、猜你喜欢*/
  @Builder RootContent() {
    Column() {
      Scroll() {
        Column({ space: 16 }) {
          Row() {
            Column() {
              Text(this.videoDetailInfo.title)
                .alignSelf(ItemAlign.Start)
                .fontColor($r('app.color.color_text_major'))
                .fontWeight(FontWeight.Bold)
                .fontSize(18)
              Column() {
                if (this.videoDetailInfo.updateTime) {
                  Text(this.videoDetailInfo.updateTime)
                    .fontColor($r('app.color.color_text_normal'))
                    .fontSize(12)
                }
                if (this.videoDetailInfo.category) {
                  Text(`分类：${this.videoDetailInfo.category}`)
                    .fontColor($r('app.color.color_text_normal'))
                    .fontSize(12)
                }
                if (this.videoDetailInfo.desc) {
                  Row() {
                    Text(this.videoDetailInfo.desc)
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
                    this.panelContentType = 0
                    this.panelController.show()
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

            Image(this.videoDetailInfo.coverUrl)
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
                this.panelContentType = 0
                this.panelController.show()
              })
          }
          .width('100%')
          .height(140)
          .padding(16)

          this.ButtonGroup()
          this.EpisodeList()
          this.GuessYouLike()
          Text("没有更多了").fontSize(14)
            .textAlign(TextAlign.Center)
            .margin({ top: 16, bottom: 52 })
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .constraintSize({
          minHeight: '100%'
        })
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

  /**面板内容*/
  @Builder SecondaryContent() {
    Column() {
      Row() {
        Text(this.panelContentType == 0 ? '详情' : '缓存')
          .fontColor($r('app.color.color_text_major'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)

        Blank()
        Image($r('app.media.ic_close'))
          .width(24).height(24)
          .onClick(() => {
            this.getUIContext()?.animateTo({
              duration: 520,
              curve: Curve.Ease
            }, () => {
              this.panelController.close()
            })
          })
      }
      .padding({ left: 16, top: 16, right: 16, bottom: 8 })
      .width('100%')

      if (this.panelContentType == 0) {
        Scroll() {
          Column() {
            //            if (this.panelContentType == 0) {
            //              this.VideoDetail()
            //            } else {
            //              this.DownloadPage()
            //            }
            this.VideoDetail()
          }
          .alignItems(HorizontalAlign.Start)
          .constraintSize({
            minHeight: '100%'
          })
        }
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
        .height('100%')
      } else {
        //        this.DownloadPage()

        // VideoCacheList({ videoDetailInfo: this.videoDetailInfo })

      }
    }
    .backgroundColor($r('app.color.background_color'))
    .width('100%')
    .height('100%')
  }

  /**下载页*/
  @Builder DownloadPage() {
    Column() {
      Row() {
        Scroll() {
          Column() {
            ForEach(this.videoDetailInfo.episodes, (episodeList: EpisodeList, episodeListIndex: number) => {
              Column() {
                // TODO 展开和折叠、单个下载列表缓存全部
                //                this.Header(episodeList.title)
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
                  Blank()
                  Text('缓存全部')
                    .fontSize(12)
                    .fontColor($r('app.color.color_text_normal'))
                    .padding(8)
                    .borderRadius(6)
                    .onClick(() => {
                      // TODO
                    })
                }
                .padding({ left: 16, top: 16, right: 16, bottom: 8 })
                .width('100%')

                Flex({ alignItems: ItemAlign.Start, justifyContent: FlexAlign.Start, wrap: FlexWrap.Wrap }) {
                  ForEach(episodeList.episodes, (item: EpisodeInfo, episodeIndex: number) => {
                    Text(item.title)
                      .textAlign(TextAlign.Center)
                      .backgroundColor(
                          (this.episodeListIndex == episodeListIndex && this.episodeIndex == episodeIndex)
                          ? '#bb3366ff' : '#aaf5f5f5')
                      .fontColor(
                          (this.episodeListIndex == episodeListIndex && this.episodeIndex == episodeIndex)
                          ? Color.White : $r('app.color.color_text_major'))
                      .fontSize(12)
                      .padding({ top: 12, bottom: 12 })
                      .borderRadius(6)
                      .margin({ bottom: 8, right: (episodeIndex + 1) % 4 == 0 ? 0 : '4%' })
                      .width('22%')
                      .maxLines(1)
                  })
                }
                .margin({ top: 8 })
                .padding({ left: 16, right: 16 })
              }
              .alignItems(HorizontalAlign.Start)
            })
          }
          .alignItems(HorizontalAlign.Start)
          .constraintSize({
            minHeight: '100%'
          })
        }
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .layoutWeight(1)

      //      Row() {
      //        Text("缓存全部")
      //          .height('100%')
      //          .layoutWeight(1)
      //          .textAlign(TextAlign.Center)
      //          .fontSize(14)
      //          .fontColor(getTheme(this.currentMode).color_text_normal)
      //          .onClick(() => {
      //          })
      //        Stack()
      //          .size({ width: 1.5, height: '30%' })
      //          .backgroundColor("#80cccccc")
      //        Text("下载列表")
      //          .textAlign(TextAlign.Center)
      //          .fontSize(14)
      //          .fontColor("#317ef5")
      //          .height('100%')
      //          .layoutWeight(1)
      //          .onClick(() => {
      //            router.pushUrl({ url: 'pages/DownloadManagerPage' })
      //          })
      //          .height(46)
      //          .width('100%')
      //      }
      //      .height(46)
      //      .width('100%')


      Row() {
        Text("下载列表")
          .textAlign(TextAlign.Center)
          .fontSize(14)
          .backgroundColor($r('app.color.primary_color'))
          .fontColor(Color.White)
          .borderRadius(21)
          .layoutWeight(1)
          .onClick(() => {
            // router.pushUrl({ url: 'pages/DownloadManagerPage' })
          })
          .height(42)
          .width('100%')
      }
      .padding(24)


    }
    .width('100%')
    .layoutWeight(1)
  }

  /**视频详情*/
  @Builder VideoDetail() {
    Column() {
      Row() {
        // 封面
        Image(this.videoDetailInfo.coverUrl)
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
          .onClick(() => {
            this.panelController.show()
          })
        Column() {
          // 标题
          Text(this.videoDetailInfo.title)
            .alignSelf(ItemAlign.Start)
            .fontColor($r('app.color.color_text_major'))
            .fontSize(16)
          Column() {
            if (this.videoDetailInfo.updateTime) {
              Text(this.videoDetailInfo.updateTime).fontSize(12)
            }
            if (this.videoDetailInfo.category) {
              Text(`分类：${this.videoDetailInfo.category}`).fontSize(12)
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

      if (this.videoDetailInfo.desc) {
        this.Header('简介')
        Text(this.videoDetailInfo.desc)
          .fontColor($r('app.color.color_text_normal'))
          .fontSize(12).padding(16)
      }
      if (this.videoDetailInfo.protagonist) {
        this.Header('角色声优')
        Text(this.videoDetailInfo.protagonist)
          .fontColor($r('app.color.color_text_normal'))
          .fontSize(12).padding(16)
      }
      if (this.videoDetailInfo.director) {
        this.Header('制作信息')
        Text(this.videoDetailInfo.director)
          .fontColor($r('app.color.color_text_normal'))
          .fontSize(12).padding(16)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
  }

  @Builder EpisodeList() {
    ForEach(this.videoDetailInfo.episodes, (episodeList: EpisodeList, episodeListIndex: number) => {
      Column() {
        this.Header(episodeList.title)
        Flex({ alignItems: ItemAlign.Start, justifyContent: FlexAlign.Start, wrap: FlexWrap.Wrap }) {
          ForEach(episodeList.episodes, (item: EpisodeInfo, episodeIndex: number) => {
            Text(item.title)
              .textAlign(TextAlign.Center)
              .backgroundColor(
                  (this.episodeListIndex == episodeListIndex && this.episodeIndex == episodeIndex)
                  ? '#bb3366ff' : $r('app.color.background_color_accent')
              )
              .fontColor(
                  (this.episodeListIndex == episodeListIndex && this.episodeIndex == episodeIndex)
                  ? Color.White : $r('app.color.color_text_major')
              )
              .fontSize(12)
              .padding({ top: 8, bottom: 8 })
              .borderRadius(6)
              .borderWidth(
                  (this.episodeListIndex == episodeListIndex && this.episodeIndex == episodeIndex)
                  ? 0 : 1.5
              )
              .borderColor($r('app.color.background_color_accent'))
              .margin({ bottom: 8, right: '2%' })
              // 解决横竖屏切换导致文字显示错位问题
              .width(this.isFullScreen ? '17%' : '18%')
              .maxLines(1)
              .onClick(() => {
                if (this.episodeListIndex == episodeListIndex && this.episodeIndex == episodeIndex) {
                  return
                }
                this.historyInfo.videoProgress = 0
                this.historyInfo.currentTime = 0
                this.historyInfo.totalTime = 0
                this.playVideo(episodeListIndex, episodeIndex)
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

  @Builder GuessYouLike() {
    Column() {
      this.Header('猜你喜欢')
      VideoList({ videoList: this.videoDetailInfo.recommends, scrollable: false })
        .padding({ left: 16, right: 16 })
        .margin({ top: 8 })
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder ButtonGroup() {
    Row() {
      // 收藏
      if (!this.isCollect) {
        this.IconWithText($r('app.media.ic_collection'), "收藏", () => {
          this.collect()
        })
      } else {
        this.IconWithText($r('app.media.ic_collected2'), "已收藏", () => {
          this.removeCollect()
        })
      }
      // 缓存
      this.IconWithText(
      $r('app.media.ic_download2'),
        '缓存',
        () => {
          this.panelContentType = 1
          ToastUtil.showToast({ message: "开发中" })
          // this.panelController.show()
        }
      )
      // 分享
      this.IconWithText($r('app.media.ic_share'), "分享", () => {
        ToastUtil.showToast({ message: "开发中" })
        Logger.e('tips', 'videoDetailInfo=' + JSON.stringify(this.videoDetailInfo))
        /*let sourceController = new CustomDialogController({
          builder: ShareDialog(
            {
              // detailInfo: this.videoDetailInfo,
              onClose: () => {
                sourceController.close()
              }
            }
          ),
          cancel: () => {
            console.log("取消")
          },
          alignment: DialogAlignment.Bottom,
          autoCancel: true,
          customStyle: true
        })
        sourceController.open()*/
      })
    }
    .justifyContent(FlexAlign.SpaceEvenly)
    .width('100%')
  }

  @Builder IconWithText(src: string | PixelMap | Resource, text: string | Resource, onClick?: (event?: ClickEvent) => void) {
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
      this.isBackgroundLoaded ? '#aaffffff' : $r('app.color.background_color_accent')
    )
    .padding({ left: 20, top: 8, right: 20, bottom: 8 })
    .borderRadius(12)
    .borderWidth(1.5)
    .borderColor($r('app.color.background_color_accent'))
    .onClick(onClick)
  }

  @Builder Header(title: string) {
    Row() {
      Row()
        .height(14)
        .width(6)
        .margin({ right: 2 })
        .borderRadius(4)
        .backgroundColor($r('app.color.primary_color'))
      Text(title)
        .fontColor($r('app.color.color_text_major'))
        .fontSize(16)
        .fontWeight(500)
    }
    .padding({ left: 16, top: 16, right: 16, bottom: 8 })
    .width('100%')
  }

}