
import VideoInfo from '../entity/VideoInfo';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { VideoNavigateInfo } from '../entity/VideoNavigateInfo';
import { VideoListColumnsTemplate, VideoListColumnsTemplate2, VideoListColumnsCount, VideoListColumnsCount2 } from '../utils/breakpoint/BreakPoint';
import { CategoryDataSource } from '../entity/CategoryData';
import { appContinueModel } from '../viewmodel/AppContinueModel';
import { AnimeState } from '../entryability/AnimeState';

/**
 * 视频列表
 */
@ComponentV2
export struct VideoList {

  @Param scrollable: boolean = true
  // 列表是否占满窗口
  @Param isFullList: boolean = true
  @Param videoList: VideoInfo[] | undefined = undefined
  @Param videoListDataSource: CategoryDataSource = new CategoryDataSource([])

  aboutToAppear(): void {
    if (this.videoList) {
      this.videoListDataSource.pushData(this.videoList)
    }
  }

  @Monitor('videoList')
  onVideoListChange(): void {
    if (this.videoList) {
      this.videoListDataSource.pushData(this.videoList)
    }
  }

  build() {
    Column() {
      if (this.scrollable) {
        Grid() {
          LazyForEach(this.videoListDataSource, (item: VideoInfo, index: number) => {
            GridItem() {
              this.VideoItem(item)
            }
          }, (item: VideoInfo, index: number) => index + JSON.stringify(item))
        }
        .hitTestBehavior(HitTestMode.Default)
        .columnsTemplate(this.isFullList ? VideoListColumnsTemplate(AnimeState.widthBp) : VideoListColumnsTemplate2(AnimeState.widthBp))
        .width('100%')
        .columnsGap(8)
        .rowsGap(8)
      } else {
        this.RowsLayout()
      }
    }.width('100%')
  }

  private getGroups(): Array<Array<VideoInfo | undefined>> {
    const cols: number = this.isFullList ? VideoListColumnsCount(AnimeState.widthBp) : VideoListColumnsCount2(AnimeState.widthBp)
    const source: VideoInfo[] = this.videoList ?? []
    const groups: Array<Array<VideoInfo | undefined>> = []
    for (let i = 0; i < source.length; i += cols) {
      const group: Array<VideoInfo | undefined> = []
      for (let j = i; j < i + cols; j++) {
        group.push(j < source.length ? source[j] : undefined)
      }
      groups.push(group)
    }
    return groups
  }

  @Builder
  RowsLayout() {
    Column({ space: 8 }) {
      ForEach(this.getGroups(), (group: Array<VideoInfo | undefined>, gi: number) => {
        Row({ space: 8 }) {
          ForEach(group, (item: VideoInfo | undefined, ii: number) => {
            if (item !== undefined) {
              Column() {
                this.VideoItem(item)
              }.layoutWeight(1)
            } else {
              Column().layoutWeight(1)
            }
          }, (item: VideoInfo | undefined, ii: number) => ii + (item ? JSON.stringify(item) : 'empty'))
        }.width('100%')
      }, (group: Array<VideoInfo | undefined>, gi: number) => gi + JSON.stringify(group))
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
    .shadow({ radius: 14, color: AnimeState.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#000000' : '#cccccc', offsetX: 6, offsetY: 6 })
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
      AnimeState.pageStack.pushPathByName("VideoDetailPage", params)
      appContinueModel.jumpVideoDetail("VideoDetailPage", params)
    })
  }
}
