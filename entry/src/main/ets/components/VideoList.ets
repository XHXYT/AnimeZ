import promptAction from '@ohos.promptAction';
import router from '@ohos.router';
import VideoInfo from '../entity/VideoInfo';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { VideoNavigateInfo } from '../entity/VideoDetailInfo';
import { BreakpointState } from '../utils/BreakPointManager';
import { BaseDataSource } from './common/BaseDataSource';

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
    Column() {
      if (item.imgUrl) {
        Image(item.imgUrl)
          .alt($r('app.media.pic_load_failed'))
          .objectFit(ImageFit.Cover)
          .borderRadius({ topLeft: 8, topRight: 8 })
          .width('100%')
          .layoutWeight(1)
      } else {
        Image($r('app.media.pic_load_failed'))
          .width('100%')
          .layoutWeight(1)
          .borderRadius({ topLeft: 8, topRight: 8 })
      }
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
    .aspectRatio(0.72)
    .backgroundColor($r('app.color.background_color'))
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