
import VideoInfo from '../entity/VideoInfo';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { BaseDataSource } from '../viewmodel/BaseDataSource';
import { VideoNavigateInfo } from '../entity/VideoNavigateInfo';
import { VideoListColumnsTemplate, VideoListColumnsTemplate2 } from '../utils/breakpoint/BreakPoint';
import { CategoryDataSource } from '../entity/CategoryData';

/**
 * 视频列表
 */
@Component
export struct VideoList {

  @State scrollable: boolean = true
  // 列表是否占满窗口
  @State isFullList: boolean = true
  @State videoList?: VideoInfo[] = undefined
  @Consume('pageStack') pageStack: NavPathStack
  // 宽度断点
  @StorageLink('currentWidthBreakpoint') widthBp: WidthBreakpoint = 1
  // 高度断点
  @StorageLink('currentHeightBreakpoint') heightBp: HeightBreakpoint = 0
  @State videoListDataSource: CategoryDataSource = new CategoryDataSource([])
  @StorageLink('currentColorMode') currentMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT

  aboutToAppear(): void {
    if (this.videoList)
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
      .columnsTemplate(this.isFullList ? VideoListColumnsTemplate(this.widthBp) : VideoListColumnsTemplate2(this.widthBp))
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
