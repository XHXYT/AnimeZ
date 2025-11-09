import { HISTORY_CHANGED_EVENT } from '../utils/EventBus';
import { More } from '../components/MoreContainer';
import { common } from '@kit.AbilityKit';
import { videoHistoryInfoDB } from '../database/VideoHistoryInfoDB';
import { VideoNavigateInfo } from '../entity/VideoNavigateInfo';
import { ToastUtil } from '../utils/ToastUtils';
import { AppConfigs } from '../entryability/Settings';
import { ColorModeManager } from '../utils/ColorModeManager';
import { Header } from '../components/common/Header';
import { VideoHistoryInfo } from '../entity/VideoHistoryInfo';

const TAG: string = 'MyPage'

/**
 * 我的页面 （Stack布局 背景 + 功能）
 */
@Component
export struct MyPage {
  @Consume('pageStack') pageStack: NavPathStack
  // 顶部避让高度
  @StorageProp('topRectHeight') topHeight: number = 0
  // 底部避让高度
  @StorageProp('bottomRectHeight') bottomHeight: number = 0
  // 应用设置
  @StorageLink('AppSettings') appSettings: AppConfigs = new AppConfigs()
  @Watch('onShowChanged') @Consume onShow: boolean
  @Consume DarkModeImage: boolean
  @State items: VideoHistoryInfo[] = []
  @State bgHeight: number = 0
  private readonly scroller = new Scroller()
  private context: common.UIAbilityContext = this.getUIContext().getHostContext()! as common.UIAbilityContext

  aboutToAppear() {
    this.loadHistoryList()
    HISTORY_CHANGED_EVENT.on(() => {
      if (this.onShow) {
        this.loadHistoryList()
      } else {
      }
    })
  }

  aboutToDisappear() {
    HISTORY_CHANGED_EVENT.off()
  }

  private onShowChanged() {
    if (this.onShow) {
      // 历史记录改变，重新加载
      this.loadHistoryList()
    }
  }

  private async loadHistoryList() {
    // 查询全部历史记录
    const list = await videoHistoryInfoDB.query()
    // 如果有历史记录，回显到页面中
    if (list) {
      // 倒序查询入组
      this.items = list
      console.log(`${TAG} VideoTest #loadHistoryList 历史记录项：${JSON.stringify( this.items)}`)
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // 我的页面整体背景图
      Stack() {
        Image($r('app.media.bg_main_nav'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.image_mask_color'))
      }
      .width('100%')
      .height(this.bgHeight)

      Scroll(this.scroller) {
        Column({ space: 16 }) {
          // 应用标题栏
          this.Header()
          // 快捷工具栏Start（收藏、缓存）
          Flex({ justifyContent: FlexAlign.SpaceAround }) {
            this.IconWithText($r('app.media.ic_star'), '我的收藏', () => {
              this.pageStack.pushPathByName("VideoCollectionPage", '', true)
            })
            this.IconWithText($r('app.media.ic_download'), '离线缓存', () => {
              this.pageStack.pushPathByName("DownloadManagerPage", '', true)
            })
          }
          .padding(8)
          .backgroundColor($r('app.color.background_color'))
          .borderRadius(16)
          .onAreaChange((_, newArea) => {

          })
          // 快捷工具栏End

          // 观看历史列表
          this.HistoryList()

          // 更多设置项
          this.MoreBuilder()

          Text('本应用仅供学习交流！')
            .fontSize(16)
            .fontColor($r('app.color.color_text_major'))
            .margin({ bottom: 16 })

        }
        .padding({ left: 16, right: 16 })
        .width('100%')
        .constraintSize({
          minHeight: '100%'
        })
      }
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
    }
    .padding({top: this.topHeight, bottom: this.bottomHeight - 20})
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

      Image(this.DarkModeImage ? $r("app.media.ic_theme_night") : $r("app.media.ic_theme_day"))
        .width(54)
        .height(42)
        .padding({ left: 12, top: 6, right: 12, bottom: 6 })
        .borderRadius(10)
        .objectFit(ImageFit.Contain)
        .onClick(() => {
          if (this.appSettings.color_mode ===  ThemeColorMode.LIGHT) {
            // 设置为 黑暗
            this.appSettings.color_mode = ThemeColorMode.DARK
          } else if (this.appSettings.color_mode === ThemeColorMode.DARK) {
            // 设置为 日间
            this.appSettings.color_mode = ThemeColorMode.LIGHT
          } else {
            ToastUtil.showToast({ message: '当前设置为跟随系统捏' })
            return
          }
          ColorModeManager.switchColorMode(this.context, this.appSettings.color_mode)
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
        this.pageStack.pushPathByName("VideoHistoryPage", '')
      })
      Column() {
        if (this.items && this.items.length > 0) {
          List() {
            ForEach(this.items, (item: VideoHistoryInfo) => {
              ListItem() {
                this.HistoryItem(item)
              }
              .constraintSize({ maxHeight: 137 })
              .height('100%')
              .aspectRatio(1)
            })
          }
          .constraintSize({ maxHeight: 139 })
          .listDirection(Axis.Horizontal)
          .width('100%')
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
      this.pageStack.pushPathByName("VideoDetailPage", params)
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