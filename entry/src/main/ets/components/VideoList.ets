
import VideoInfo from '../entity/VideoInfo';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { VideoNavigateInfo } from '../entity/VideoNavigateInfo';
import { VideoListColumnsTemplate, VideoListColumnsTemplate2, VideoListColumnsCount, VideoListColumnsCount2 } from '../utils/breakpoint/BreakPoint';
import { CategoryDataSource } from '../entity/CategoryData';
import { appContinueModel } from '../viewmodel/AppContinueModel';
import { AnimeState } from '../entryability/AnimeState';
import { dataSourceManager } from '../api/DataSourceManager';

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
  // 是否在封面左上角显示数据源角标（默认样式同集数角标）
  @Param showSourceBadge: boolean = false

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
        // padding 放在滚动容器内部（同主页做法）：滚动条落在右侧留白处，边缘卡片阴影不被截断
        .padding(16)
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
        Stack() {
          if (item.imgUrl) {
            Image(item.imgUrl)
              .borderRadius({ topLeft: 8, topRight: 8 })
              .alt($r('app.media.pic_load_failed'))
              .objectFit(ImageFit.Fill)
              .width('100%')
              .height('100%')
          } else {
            Image($r('app.media.pic_load_failed'))
              .borderRadius({ topLeft: 8, topRight: 8 })
              .width('100%')
              .height('100%')
          }
          // 深色模式轻蒙版压暗封面颜色
          if (AnimeState.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
            Row()
              .backgroundColor('#40000000')
              .width('100%')
              .height('100%')
              .borderRadius({ topLeft: 8, topRight: 8 })
          }
          // 左上角数据源角标（默认色，字边距与列表样式右下角角标一致）
          if (this.showSourceBadge && (dataSourceManager.getSourceTitle(item.sourceKey) ?? '') !== '') {
            Text(dataSourceManager.getSourceTitle(item.sourceKey) ?? '')
              .fontSize(10)
              .fontColor($r('sys.color.font_on_primary'))
              .maxLines(1)
              .constraintSize({ maxWidth: '80%' })
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
              .backgroundColor('#99000000')
              .margin(4)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .alignContent(Alignment.TopStart)
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
            .fontColor($r('sys.color.font_on_primary'))
            .fontSize(10)
        }
        .height(18)
        .borderRadius(4)
        .padding({left: 3, right: 3})
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .margin({right: 5, left: 5, bottom: 45})
        .backgroundColor('#99000000')
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
