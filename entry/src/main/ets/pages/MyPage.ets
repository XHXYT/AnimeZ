import { More } from '../components/MoreContainer';
import { common } from '@kit.AbilityKit';
import { VideoNavigateInfo } from '../entity/VideoNavigateInfo';
import { ToastUtil } from '../utils/ToastUtils';
import { appSettings } from '../entryability/Settings';
import { ColorModeManager } from '../utils/ColorModeManager';
import { Header } from '../components/common/Header';
import { AnimeState } from '../entryability/AnimeState';
import { historyViewModel } from '../viewmodel/HistoryViewModel';
import VideoHistoryInfo from '../entity/VideoHistoryInfo';

const TAG: string = 'MyPage'

/**
 * 我的页面
 */
@ComponentV2
export struct MyPage {

  aboutToAppear() {
    // HISTORY_CHANGED_EVENT 已由 historyViewModel 常驻订阅，进入页面时显式刷新一次
    historyViewModel.loadHistoryList()
  }

  build() {
    List({ space: 16 }) {
      // 应用标题栏
      ListItem() {
        this.Header()
      }
      // 快捷工具栏Start（收藏、缓存）
      ListItem() {
        Flex({ justifyContent: FlexAlign.SpaceAround }) {
          this.IconWithText($r('app.media.ic_star'), '我的收藏', () => {
            AnimeState.pageStack.pushPathByName("VideoCollectionPage", '', true)
          })
          this.IconWithText($r('app.media.ic_download'), '离线缓存', () => {
            AnimeState.pageStack.pushPathByName("DownloadManagerPage", '', true)
          })
        }
        .padding(8)
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
      }
      // 快捷工具栏End

      // 观看历史列表
      ListItem() {
        this.HistoryList()
      }

      // 更多设置项
      ListItem() {
        this.MoreBuilder()
      }

      ListItem() {
        Text('本应用仅供学习交流！')
          .fontSize(16)
          .fontColor($r('app.color.color_text_major'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 16 })
      }
    }
    .contentEndOffset(57)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off)
    .padding({
      left: 16,
      right: 16,
      top: AnimeState.topRectHeight,
      bottom: AnimeState.bottomRectHeight - 20
    })
    .backgroundColor($r('app.color.background_color_accent'))
    .width('100%')
    .height('100%')
  }

  /**
   * 应用标题栏
   */
  @Builder
  Header() {
    Row() {
      Stack() {
        Image($r("app.media.ic_anime"))
          .width(32)
          .height(32)
          .objectFit(ImageFit.Contain)
      }
      .width(56)
      .height(56)
      .borderWidth(1)
      .borderRadius(28)
      .borderColor('#eeeeee')

      Column() {
        Text($r('app.string.app_name'))
          .fontWeight(FontWeight.Bold)
          .fontSize(16)
          .alignSelf(ItemAlign.Start)

        Text($r('app.string.module_desc'))
          .fontSize(12)
          .margin({ top: 8 })
          .alignSelf(ItemAlign.Start)
      }
      .margin({ left: 16, right: 16 })
      .layoutWeight(1)

      Image(AnimeState.darkModeImage ? $r("app.media.ic_theme_night") : $r("app.media.ic_theme_day"))
        .width(54)
        .height(42)
        .padding({ left: 12, top: 6, right: 12, bottom: 6 })
        .borderRadius(10)
        .objectFit(ImageFit.Contain)
        .onClick(() => {
          if (appSettings.color_mode ===  ThemeColorMode.LIGHT) {
            // 设置为 黑暗
            appSettings.color_mode = ThemeColorMode.DARK
          } else if (appSettings.color_mode ===  ThemeColorMode.DARK) {
            // 设置为 日间
            appSettings.color_mode = ThemeColorMode.LIGHT
          } else {
            ToastUtil.showToast({ message: '当前设置为跟随系统捏' })
            return
          }
          ColorModeManager.switchColorMode(this.getUIContext().getHostContext()! as common.UIAbilityContext, appSettings.color_mode)
        })
    }
    .margin({ left: 16, right: 16, top: 56, bottom: 16 })
  }

  /**
   * 图标 + 文本格式组合
   * @param icons 图标地址
   * @param title 文本内容
   * @param onClick 点击后触发的事件
   */
  @Builder
  IconWithText(icons: string | PixelMap | Resource, title: string, onClick?: (event?: ClickEvent) => void) {
    Row() {
      Image(icons)
        .width(20)
        .height(20)
      Text(title)
        .fontSize(14)
        .fontColor($r('app.color.color_text_major'))
        .margin({ left: 8 })
    }
    .padding(8)
    .onClick(onClick)
  }

  /**
   * 观看历史构建
   */
  @Builder
  HistoryList() {
    Column() {
      Header('观看历史', () => {
        AnimeState.pageStack.pushPathByName("VideoHistoryPage", '')
      })
      Column() {
        if (historyViewModel.historyList && historyViewModel.historyList.length > 0) {
          List() {
            ForEach(historyViewModel.historyList, (item: VideoHistoryInfo) => {
              ListItem() {
                this.HistoryItem(item)
              }
              .height(137)
              .aspectRatio(1)
            })
          }
          .height(139)
          .listDirection(Axis.Horizontal)
          .width('100%')
          .scrollBar(BarState.Off)
        } else {
          Column() {
            Image($r('app.media.ic_empty'))
              .objectFit(ImageFit.Contain)
              .height(56)
              .width(56)
            Text('暂无记录').fontSize(14)
              .margin({ top: 8 })
              .fontColor($r('app.color.color_text_normal'))
          }
          .padding({ top: 16, bottom: 32 })
          .width('100%')
        }
      }.width('100%')
      .padding({ left: 16, right: 16 })
    }
    .backgroundColor($r('app.color.background_color'))
    .alignItems(HorizontalAlign.Start)
    .borderRadius(16)
    .clip(true)
  }

  /**
   * 观看历史列表项
   */
  @Builder
  HistoryItem(item: VideoHistoryInfo) {
    Column() {
      Image(item.coverUrl)
        .alt($r('app.media.pic_load_failed'))
        .borderRadius(8)
        .width('100%')
        .layoutWeight(1)
        .objectFit(ImageFit.Cover)
        .shadow({ radius: 12, color: $r('app.color.image_shadow_color'), offsetX: 6, offsetY: 6 })
      Text(item.title)
        .alignSelf(ItemAlign.Start)
        .margin({ top: 8, bottom: 8 })
        .maxLines(2)
        .lineHeight(14)
        .height(28)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontColor($r('app.color.color_text_minor'))
        .fontSize(12)
    }
    .width('100%')
    .height('100%')
    .padding({ top: 8, bottom: 8, left: 4, right: 4 })
    .onClick(() => {
      const params: VideoNavigateInfo = {
        id: item.id,
        url: item.link as string,
        sourceKey: item.sourceKey,
        title: item.title,
        cover: item.coverUrl as string
      }
      console.log('VideoTest 我的页面历史栏传递的params：', JSON.stringify(params))
      AnimeState.pageStack.pushPathByName("VideoDetailPage", params)
    })
  }

  /**
   * 更多设置项构建
   */
  @Builder
  MoreBuilder() {
    More()
  }

}
