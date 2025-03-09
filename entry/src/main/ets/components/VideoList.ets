import promptAction from '@ohos.promptAction';
import router from '@ohos.router';
import VideoInfo from '../entity/VideoInfo';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { VideoNavigateInfo } from '../entity/VideoDetailInfo';

/**
 * 主页视频列表
 */
@Component
export struct VideoList {
  videoList: VideoInfo[] = []
  @State scrollable: boolean = true
  @Consume('pageStack') pageStack: NavPathStack
  @StorageProp('currentColorMode') currentMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT

  build() {
    Column() {
      if (this.scrollable) {
        Grid() {
          ForEach(this.videoList, (item: VideoInfo) => {
            GridItem() {
              this.VideoItem(item)
            }
          })
        }
        .hitTestBehavior(this.scrollable ? HitTestMode.Default : HitTestMode.None)
        .columnsTemplate("1fr 1fr 1fr")
        .columnsGap(8)
        .rowsGap(8)
        .width('100%')
        .height('100%')
      } else {
        Flex({ alignItems: ItemAlign.Start, justifyContent: FlexAlign.Start, wrap: FlexWrap.Wrap }) {
          ForEach(this.videoList, (item: VideoInfo) => {
            Column() {
              this.VideoItem(item)
            }
            .padding({ bottom: 8, right: 8 })
            .width('33.3%')
          })
        }
      }
    }
  }

  @Builder VideoItem(item: VideoInfo) {
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
          .borderRadius({ topLeft: 8, topRight: 8 })
          .width('100%')
          .layoutWeight(1)
      }
      Text(item.title)
        .height(40)
        .fontSize(12)
        .maxLines(2)
        .fontColor($r('app.color.color_text_major'))
        .padding({ left: 2, right: 2 })
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .fontWeight(500)
    }
    .borderRadius(12)
    .backgroundColor($r('app.color.background_color'))
    .aspectRatio(0.618)
    .shadow({ radius: 12, color: this.currentMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#000000' : '#eeeeee', offsetX: 6, offsetY: 6 })
    .onClick(() => {
      // 暂时默认为新增
      const params: VideoNavigateInfo = {
        id: null,
        url: item.url as string,
        sourceKey: item.sourceKey,
        title: item.title,
        cover: item.imgUrl as string
      }
      console.log('VideoTest 主页列表传递的params：', JSON.stringify(params))
      this.pageStack.pushPathByName("VideoDetailPage", params)
    })
  }
}