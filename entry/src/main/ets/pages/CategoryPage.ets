import { dataSourceManager } from "../api/DataSourceManager"
import VideoInfo, { TypeInfo } from "../entity/VideoInfo"
import { VideoCategoryNavigateInfo } from "../entity/VideoNavigateInfo"
import Logger from "../utils/Logger"
import { BaseDataSource } from "../viewmodel/BaseDataSource"
import StateView, { ViewState } from "../components/StateView"
import TitleBar from "../components/TitleBar"
import { VideoList } from "../components/VideoList"
import { VideoCategoryColumnsTemplate } from "../utils/breakpoint/BreakPoint"
import { AppConfigs } from "../entryability/Settings"
import { CategoryDataSource } from "../entity/CategoryData"


// 系统路由
@Builder
export function CategoryPageBuilder(name: string, param: Object) {
  CategoryPage()
}

/**
 * 视频目录页
 */
@Component
export struct CategoryPage {

  @State state: number = 0
  @State url: string = ''
  @State page: number = 0
  @State title: string = ''
  @State errorMessage: string = ''
  @Consume('pageStack') pageStack: NavPathStack
  // 顶部避让高度
  @StorageProp('topRectHeight') topHeight: number = 0
  // 底部避让高度
  @StorageProp('bottomRectHeight') bottomHeight: number = 0
  // 宽度断点
  @StorageLink('currentWidthBreakpoint') widthBp: WidthBreakpoint = 1
  // 高度断点
  @StorageLink('currentHeightBreakpoint') heightBp: HeightBreakpoint = 0
  // 应用设置
  @StorageLink('AppSettings') appSettings: AppConfigs = new AppConfigs()
  @State categoryDataSource: CategoryDataSource = new CategoryDataSource([])

  build() {
    NavDestination() {
      TitleBar({
        title: this.title
      })
      StateView(
        {
          state: this.state,
          errorMessage: $errorMessage,
          content: () => {
            this.Content(this.appSettings.category_UI_type)
          },
          custom: undefined,
          onRetry: () => {
            this.loadFirstPage()
            return true
          }
        }
      )
        .width('100%')
        .layoutWeight(1)
    }
    .padding({top: this.topHeight - 15, bottom: this.bottomHeight - 20})
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
    .onReady(async (ctx: NavDestinationContext) => {
      // 接收信息
      try {
        const params: VideoCategoryNavigateInfo = ctx?.pathInfo?.param as VideoCategoryNavigateInfo
        this.title = params.title
        this.url = params.url
        this.loadFirstPage()
        console.log('CategoryPage 视频目录页接收的params：', JSON.stringify(params))
      } catch (e) {
        console.log(`VideoList Navigate onReady catch exception: ${e.code} ${e.message}`)
      }
    })

  }

  @Builder
  Content(UI_type: number) {
    if (UI_type === 1) {
      // 图片 + 标题 1
      VideoList({
        videoListDataSource: this.categoryDataSource
      }).padding(16)
    } else {
      // 详细 0
      Grid() {
        LazyForEach(this.categoryDataSource, (item: VideoInfo) => {
          GridItem() {
            this.VideoItemDetailed(item)
          }
        }, (item: VideoInfo) => item.title + item.imgUrl)
      }.padding(16)
      .columnsGap(6)
      .rowsGap(8)
      .columnsTemplate(VideoCategoryColumnsTemplate(this.widthBp))
    }

  }

  @Builder
  VideoItemDetailed(item: VideoInfo) {
    Row({space: 16}) {
      // 封面
      if (item.imgUrl) {
        Image(item.imgUrl)
          .borderRadius({ topLeft: 8, topRight: 8 })
          .alt($r('app.media.pic_load_failed'))
          .objectFit(ImageFit.Fill)
          .aspectRatio(0.65)
          .borderRadius(12)
          .layoutWeight(1)
          .width('100%')
      } else {
        Image($r('app.media.pic_load_failed'))
          .borderRadius({ topLeft: 8, topRight: 8 })
          .layoutWeight(1)
          .width('100%')
      }
      // 详情
      Column({space: 5}) {
        // 标题
        Text(item.title)
          .maxLines(2)
          .fontSize(15)
          .width('100%')
          .fontWeight(FontWeight.Regular)
          .textAlign(TextAlign.Start)
          .padding({ left: 2, right: 2 })
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        // 更新
        Text(item.episode)
          .fontSize(12)
          .width('100%')
          .fontColor(Color.Red)
          .fontWeight(FontWeight.Normal)
        // 类型
        Text() {
          Span('类型：')
          ForEach(item.videoType, (type: TypeInfo) => {
            Span(`${type.typeName}  `)
          })
        }
        .fontSize(12)
        .width('100%')
        .fontWeight(FontWeight.Normal)
        // 简介
        Text(item.videoIntroduction)
          .fontSize(12)
          .width('100%')
          .fontColor($r('app.color.color_text_minor'))
          .fontWeight(FontWeight.Normal)
      }
      .layoutWeight(1)
      // .borderWidth(2)
      // .borderColor(Color.Red)
      .justifyContent(FlexAlign.Start)
    }.padding({right: 10})
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.image_mask_color'))
  }

  aboutToAppear(): void {

  }

  async loadFirstPage() {
    this.state = ViewState.LOADING
    try {
      const data = await dataSourceManager.getVideoList(this.url, this.page)
      Logger.d('CategoryPage', '#loadNextPage list=' + JSON.stringify(data))
      this.state = ViewState.CONTENT
      // 推送数据
      this.categoryDataSource.pushData(data)
    } catch (err) {
      this.errorMessage = err.message
      this.state = ViewState.ERROR
      Logger.e('fail', '获取界面视频数据', err)
    }
  }

  loadNextPage() {

  }

}



