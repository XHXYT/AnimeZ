import promptAction from '@ohos.promptAction';
import VideoInfo from '../entity/VideoInfo';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { BreakpointState } from '../utils/BreakPointManager';
import { BaseDataSource } from './common/BaseDataSource';
import { VideoNavigateInfo } from '../entity/VideoNavigateInfo';

/**
 * 视频列表
 */
@Component
export struct VideoList {
  @State videoList: VideoInfo[] = []
  @State scrollable: boolean = true
  @Consume('pageStack') pageStack: NavPathStack
  @State videoListDataSource: VideoListDataSource = new VideoListDataSource([])
  @Consume('VideoListColumnsTemplate') videoListColumnsTemplate: BreakpointState<string>
  @StorageLink('currentColorMode') currentMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT

  aboutToAppear(): void {
    this.videoListDataSource.pushData(this.videoList)
  }

  build() {
    Column() {
      Grid() {
        LazyForEach(this.videoListDataSource, (item: VideoInfo, index: number) => {
          GridItem() {
            this.VideoItem(item)
          }
        }, (item: VideoInfo, index: number) => index + JSON.stringify(item))
      }
      .hitTestBehavior(this.scrollable ? HitTestMode.Default : HitTestMode.None)
      .columnsTemplate(this.videoListColumnsTemplate.value)
      .width('100%')
      .columnsGap(8)
      .rowsGap(8)
    }.width('100%')
  }

  @Builder
  VideoItem(item: VideoInfo) {
    Stack() {
      Column() {
        // 封面
        if (item.imgUrl) {
          Image(item.imgUrl)
            .borderRadius({ topLeft: 8, topRight: 8 })
            .alt($r('app.media.pic_load_failed'))
            .objectFit(ImageFit.Fill)
            .layoutWeight(1)
            .width('100%')
        } else {
          Image($r('app.media.pic_load_failed'))
            .borderRadius({ topLeft: 8, topRight: 8 })
            .layoutWeight(1)
            .width('100%')
        }
        // 番名
        Text(item.title)
          .height(40)
          .maxLines(2)
          .fontSize(12)
          .fontWeight(500)
          .fontColor($r('app.color.color_text_major'))
          .textAlign(TextAlign.Center)
          .padding({ left: 2, right: 2 })
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .borderRadius(12)
      .aspectRatio(0.65)
      if (item.episode) {
        // 集数
        Column() {
          Text(item.episode)
            .fontColor(Color.White)
            .fontSize(10)
        }
        .height(18)
        .borderRadius(4)
        .padding({left: 3, right: 3})
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .margin({right: 5, left: 5, bottom: 45})
        .backgroundColor($r('app.color.color_text_normal'))
      }

    }.width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.background_color'))
    .alignContent(Alignment.BottomEnd)
    .shadow({ radius: 12, color: this.currentMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#000000' : '#eeeeee', offsetX: 6, offsetY: 6 })
    .onClick(() => {
      // 默认为新增
      const params: VideoNavigateInfo = {
        id: null,
        url: item.url as string,
        sourceKey: item.sourceKey,
        title: item.title,
        cover: item.imgUrl as string
      }
      console.log('VideoTest 视频列表传递的params：', JSON.stringify(params))
      this.pageStack.pushPathByName("VideoDetailPage", params)
    })
  }
}

class VideoListDataSource extends BaseDataSource<VideoInfo> {
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