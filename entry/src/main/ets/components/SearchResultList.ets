import VideoInfo from '../entity/VideoInfo';
import { VideoNavigateInfo } from '../entity/VideoNavigateInfo';
import { AnimeState } from '../entryability/AnimeState';
import { appContinueModel } from '../viewmodel/AppContinueModel';
import { dataSourceManager } from '../api/DataSourceManager';
import { sourceBadgeColor } from '../utils/SourceBadgeUtils';

/**
 * 搜索结果横排列表（单行一图多字段 + 右下角源角标，便于展示更多扩展信息）
 */
@ComponentV2
export struct SearchResultList {

  @Require @Param videoList: VideoInfo[] = []

  build() {
    List({ space: 10 }) {
      ForEach(this.videoList, (item: VideoInfo) => {
        ListItem() {
          SearchResultItem({ item: item })
        }
      }, (item: VideoInfo): string => `${item.sourceKey}|${item.url ?? ''}|${item.title}`)
    }
    .width('100%')
    .height('100%')
    .edgeEffect(EdgeEffect.Spring)
    .padding({ top: 4, bottom: 16, left: 16, right: 16 })
  }
}

/**
 * 搜索结果横排条目
 */
@ComponentV2
struct SearchResultItem {

  @Require @Param item: VideoInfo

  private get sourceTitle(): string {
    return dataSourceManager.getSourceTitle(this.item.sourceKey) ?? ''
  }

  private hasText(value?: string): boolean {
    return (value ?? '').trim() !== ''
  }

  build() {
    // 卡片根节点用 Stack 锚定：角标始终固定在卡片右下角，不随上方字段缺失上移
    Stack({ alignContent: Alignment.BottomEnd }) {
      Row({ space: 12 }) {
        // 封面
        if (this.item.imgUrl) {
          Image(this.item.imgUrl)
            .alt($r('app.media.pic_load_failed'))
            .objectFit(ImageFit.Cover)
            .width(84)
            .height(112)
            .borderRadius(8)
        } else {
          Image($r('app.media.pic_load_failed'))
            .objectFit(ImageFit.Cover)
            .width(84)
            .height(112)
            .borderRadius(8)
        }

        // 右侧信息区
        Column({ space: 5 }) {
          Text(this.item.title)
            .fontSize(15)
            .fontWeight(500)
            .fontColor($r('app.color.color_text_major'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // 播放量 / 播出年份 / 播出月份 三个方框
          if (this.hasText(this.item.playCount) || this.hasText(this.item.year) || this.hasText(this.item.month)) {
            Row({ space: 6 }) {
              if (this.hasText(this.item.playCount)) {
                Text(this.item.playCount)
                  .fontSize(11)
                  .fontColor($r('app.color.color_text_minor'))
                  .maxLines(1)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(4)
                  .backgroundColor('#1A808080')
              }
              if (this.hasText(this.item.year)) {
                Text(this.item.year)
                  .fontSize(11)
                  .fontColor($r('app.color.color_text_minor'))
                  .maxLines(1)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(4)
                  .backgroundColor('#1A808080')
              }
              if (this.hasText(this.item.month)) {
                Text(this.item.month)
                  .fontSize(11)
                  .fontColor($r('app.color.color_text_minor'))
                  .maxLines(1)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(4)
                  .backgroundColor('#1A808080')
              }
            }
          }

          // 导演（单行省略）
          if (this.hasText(this.item.director)) {
            Text('导演：' + this.item.director)
              .fontSize(12)
              .fontColor($r('app.color.color_text_minor'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          // 演员（单行省略）
          if (this.hasText(this.item.actors)) {
            Text('主演：' + this.item.actors)
              .fontSize(12)
              .fontColor($r('app.color.color_text_minor'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          // 标签（可占两行）
          if (this.hasText(this.item.tags)) {
            Text('标签：' + this.item.tags)
              .fontSize(12)
              .fontColor($r('app.color.color_text_minor'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .constraintSize({ minHeight: 112 })
        // 信息区过高撑开卡片时，为右下角角标预留空间，避免文字与角标重叠
        .padding({ bottom: this.sourceTitle !== '' ? 30 : 0 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 右下角数据源角标（Stack 锚定卡片右下角，与观看历史同款颜色区分）
      if (this.sourceTitle !== '') {
        Text(this.sourceTitle)
          .fontSize(10)
          .fontColor(sourceBadgeColor(this.item.sourceKey))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '60%' })
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor('#33808080')
          .margin({ right: 12, bottom: 8 })
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 12, right: 12 })
    .borderRadius(12)
    .backgroundColor($r('app.color.background_color'))
    .onClick(() => {
      const params: VideoNavigateInfo = {
        id: null,
        url: this.item.url as string,
        sourceKey: this.item.sourceKey,
        title: this.item.title,
        cover: this.item.imgUrl as string
      }
      AnimeState.pageStack.pushPathByName("VideoDetailPage", params)
      appContinueModel.jumpVideoDetail("VideoDetailPage", params)
    })
  }
}
