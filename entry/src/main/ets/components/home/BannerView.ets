import VideoInfo from "../../entity/VideoInfo";
import { BaseDataSource } from "../common/BaseDataSource";
import { ConfigurationConstant } from "@kit.AbilityKit";
import { VideoNavigateInfo } from "../../entity/VideoNavigateInfo";
import { HomeBannerBannerMargin, HomeBannerDisplayCount } from "../../utils/breakpoint/BreakPoint";


@Component
export struct BannerView {
  @Link bannerList: VideoInfo[]
  @Consume('pageStack') pageStack: NavPathStack
  private bannerDataSource: BannerDataSource = new BannerDataSource([])
  // 宽度断点
  @StorageLink('currentWidthBreakpoint') widthBp: WidthBreakpoint = 1
  // 高度断点
  @StorageLink('currentHeightBreakpoint') heightBp: HeightBreakpoint = 0
  @StorageLink('currentColorMode') currentMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT

  aboutToAppear(): void {
    this.bannerDataSource.pushData(this.bannerList)
  }

  build() {
    Swiper() {
      LazyForEach(this.bannerDataSource, (item: VideoInfo, index: number) => {
        this.BannerItem(item)
      }, (item: VideoInfo, index: number) => index + JSON.stringify(item))
    }.loop(true)
    .width('100%')
    .itemSpace(9)
    .autoPlay(true)
    .interval(6000)
    .indicator(false)
    .prevMargin(HomeBannerBannerMargin(this.widthBp))
    .nextMargin(HomeBannerBannerMargin(this.widthBp))
    .displayCount(HomeBannerDisplayCount(this.widthBp))
  }

  // 轮播图项
  @Builder BannerItem(item: VideoInfo) {
    Stack({ alignContent: Alignment.BottomStart }) {
      // 封面
      Image(item.imgUrl)
        .layoutWeight(1)
        .borderRadius(16)
        .aspectRatio(1.75)
        .objectFit(ImageFit.Cover)
        .alt($r('app.media.pic_load_failed')) // 占位图
        .shadow({ radius: 16, color: this.currentMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#000000' : '#aaaaaa', offsetX: 6, offsetY: 6 })
      // 遮罩
      Row()
        .width('100%')
        .borderRadius(16)
        .aspectRatio(1.75)
        .backgroundColor(this.currentMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#80000000' : '#40000000')
      // 标题
      Text(item.title)
        .fontColor(Color.White)
        .fontSize(16)
        .padding(12)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .alignSelf(ItemAlign.Start)
    }
    .padding({ top: 16, bottom: 16 })
    .onClick(() => {
      console.log('Home 点击图片 ')
      // 默认为新增 由数据库抛出重复值
      const params: VideoNavigateInfo = {
        id: null,
        url: item.url as string,
        sourceKey: item.sourceKey,
        title: item.title,
        cover: item.imgUrl as string
      }
      console.log('VideoTest 主页轮播图传递的params：', JSON.stringify(params))
      this.pageStack.pushPathByName("VideoDetailPage", params)
    })
  }

}

class BannerDataSource extends BaseDataSource<VideoInfo> {
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