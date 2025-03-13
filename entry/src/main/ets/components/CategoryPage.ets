import DataSourceManager from "../api/DataSourceManager"
import VideoInfo, { TypeInfo } from "../entity/VideoInfo"
import { VideoCategoryNavigateInfo } from "../entity/VideoNavigateInfo"
import { BreakpointState } from "../utils/BreakPointManager"
import Logger from "../utils/Logger"
import { BaseDataSource } from "./common/BaseDataSource"
import StateView, { ViewState } from "./StateView"
import TitleBar from "./TitleBar"
import { VideoList } from "./VideoList"


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
  @State sourceUItype: number = 0
  @State errorMessage: string = ''
  @State videoList: VideoInfo[] = []
  @Consume('pageStack') pageStack: NavPathStack
  // 顶部避让高度
  @StorageProp('topRectHeight') topHeight: number = 0
  // 底部避让高度
  @StorageProp('bottomRectHeight') bottomHeight: number = 0
  @State categoryDataSource: CategoryDataSource = new CategoryDataSource([])
  @Consume('VideoCategoryColumnsTemplate') videoCategoryColumnsTemplate: BreakpointState<string>

  aboutToAppear(): void {

  }

  checkSourceUItype(key: string) {
    this.sourceUItype = DataSourceManager.getSourceUItype(key)
    console.log('CategoryPage 视频目录页UI类型：', this.sourceUItype)
  }

  loadFirstPage() {
    this.state = ViewState.LOADING
    DataSourceManager.getCurrentSource()
      .getVideoList(this.url, this.page)
      .then((data) => {
        Logger.e(this, 'CategoryPage #loadNextPage list=' + JSON.stringify(data))
        this.videoList = data
        this.state = ViewState.CONTENT
        if (this.sourceUItype === 0) {
          console.log('CategoryPage 视频目录页推送懒加载数据：', this.sourceUItype)
          // 推送数据
          this.categoryDataSource.pushData(this.videoList)
          console.log('CategoryPage 视频目录页已推送懒加载数据：', this.sourceUItype)
        }
      })
      .catch((e: Error) => {
        this.errorMessage = JSON.stringify(e)
        this.state = ViewState.ERROR
      })
  }

  loadNextPage() {

  }

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
            this.Content(this.sourceUItype)
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
        this.checkSourceUItype(params.sourceKey)
      } catch (e) {
        console.log(`VideoList Navigate onReady catch exception: ${JSON.stringify(e)}`)
      }
    })

  }

  @Builder
  Content(UItype: number) {
    if (UItype === 1) {
      // 图片 + 标题 1
      VideoList({
        videoList: this.videoList
      }).padding(16)
    } else {
      // 详细 0
      Grid() {
        LazyForEach(this.categoryDataSource, (item: VideoInfo, index: number) => {
          GridItem() {
            this.VideoItemDetailed(item)
          }
        }, (item: VideoInfo, index: number) => index + JSON.stringify(item))
      }.padding(16)
      .columnsGap(6)
      .rowsGap(8)
      .columnsTemplate(this.videoCategoryColumnsTemplate.value)
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

}


class CategoryDataSource extends BaseDataSource<VideoInfo> {
  private dataArray: VideoInfo[] = []

  public totalCount(): number {
    return this.dataArray.length
  }

  public getData(index: number): VideoInfo {
    return this.dataArray[index]
  }

  public addData(index: number, data: VideoInfo): void {
    this.dataArray.splice(index, 0, data)
    this.notifyDataAdd(index)
  }

  public pushData(data: VideoInfo[]): void {
    this.dataArray = data
    this.notifyDataAdd(this.dataArray.length - 1)
  }

  // 删除全部数据
  public clear(): void {
    this.empty()
    this.refresh()
  }

  public empty(): void {
    this.dataArray = []
  }

  public refresh(): void {
    this.notifyDataReload()
  }

}
