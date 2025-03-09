import promptAction from '@ohos.promptAction';
import router from '@ohos.router';
import VideoInfo from '../entity/VideoInfo';
import { DramaList } from '../entity/HomepageData';
import { ConfigurationConstant } from '@kit.AbilityKit';
import StateView, { ViewState } from '../components/StateView';
import { SOURCE_CHANGED_EVENT } from '../utils/EventBus';
import { VideoList } from '../components/VideoList';
import DataSourceManager from '../api/DataSourceManager';
import Logger from '../utils/Logger';
import VideoDetailInfo, { VideoNavigateInfo } from '../entity/VideoDetailInfo';

// 系统路由
@Builder
export function HomePageBuilder(name: string, param: Object) {
  HomePage()
}

@Component
export struct HomePage {
  @State state: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @StorageProp('currentColorMode') currentMode: number = 1
  // 顶部避让高度
  @StorageProp('topRectHeight') topHeight: number = 0
  // 底部避让高度
  @StorageProp('bottomRectHeight') bottomHeight: number = 0

  build() {
    NavDestination() {
      // 搜索栏
      Row({space: 16}) {
        Image($r("app.media.ic_anime"))
          .width(28)
          .height(28)
          .objectFit(ImageFit.Contain)

        Row() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontColor(['#817977'])
            .margin({ left: 12, right: 8 })
          Text("番剧搜索")
            .fontWeight(300)
            .fontColor('#817977')
            .fontSize(14)
        }
        .height(32)
        .layoutWeight(1)
        .backgroundColor($r('app.color.background_color_accent'))
        .borderRadius(32)
        .onClick(() => {
          this.pageStack.pushPathByName("SearchPage", '')
        })

        Image($r("app.media.ic_download_manager"))
          .width(20)
          .height(20)
          .fillColor('#817977')
          .objectFit(ImageFit.Contain)
          .onClick(() => {
            router.pushUrl({ url: 'pages/DownloadManagerPage' })
          })

        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(20)
          .fontColor(['#817977'])
          .onClick(() => {
            this.pageStack.pushPathByName("VideoHistoryPage", '')
          })
      }
      .height(56)
      .width('100%')
      .padding({left: 16, right: 16})
      // 推荐
      Recommend()

    }.width('100%')
    .height('100%')
    .hideToolBar(true)
    .backgroundColor($r('app.color.background_color'))
    .padding({top: this.topHeight, bottom: this.bottomHeight - 20})
    .onShown(() => {
      this.state = ViewState.CONTENT
    })
  }
}

/**
 * 首页推荐
 */
@Component
struct Recommend {
  @State bannerList: VideoInfo[] = []
  @State categoryList: DramaList[] = []
  @Prop state: number
  @State errorMessage: string = ''
  @Consume('pageStack') pageStack: NavPathStack
  @StorageProp('currentColorMode') currentMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT

  aboutToAppear() {
    this.state = ViewState.LOADING
    this.loadNextPage()
    SOURCE_CHANGED_EVENT.on(() => {
      this.loadNextPage()
    })
  }

  aboutToDisappear() {
    SOURCE_CHANGED_EVENT.off()
  }

  build() {
    StateView(
      {
        state: this.state,
        errorMessage: $errorMessage,
        content: () => {
          this.Content()
        },
        custom: undefined,
        onRetry: () => {
          this.loadNextPage()
          return true;
        }
      }
    )
      .width('100%')
      .layoutWeight(1)
  }

  @Builder Content() {
    Stack() {
      Scroll() {
        Column() {
          this.Banner()
          ForEach(this.categoryList, (category: DramaList) => {
            this.Category(category)
          })
        }
        .constraintSize({
          minHeight: '100%'
        })
      }
      .edgeEffect(EdgeEffect.Spring)
      .height('100%')
      .width('100%')
    }
    .height('100%')
    .width('100%')
  }

  // 轮播图
  @Builder Banner() {
    Swiper() {
      ForEach(this.bannerList, (item: VideoInfo) => {
        this.BannerItem(item)
      })
    }
    .width('100%')
    .aspectRatio(2)
    .autoPlay(true)
    .interval(5000)
    .loop(true)
    .indicator(false)
  }

  // 轮播图项
  @Builder BannerItem(item: VideoInfo) {
    Stack({ alignContent: Alignment.BottomStart }) {
      Image(item.imgUrl)
        .alt($r('app.media.pic_load_failed'))
        .objectFit(ImageFit.Cover)
        .layoutWeight(1)
        .borderRadius(16)
        .shadow({ radius: 16, color: this.currentMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#000000' : '#aaaaaa', offsetX: 6, offsetY: 6 })

      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(this.currentMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#80000000' : '#40000000')
        .borderRadius(16)

      Text(item.title)
        .fontColor(Color.White)
        .fontSize(16)
        .padding(12)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .alignSelf(ItemAlign.Start)
    }
    .padding(16)
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
  // 分类项
  @Builder Category(category: DramaList) {
    Column() {
      this.Bar(category.title, category.moreUrl)
      VideoList({
        videoList: category.videoList,
        scrollable: false
      }).padding(16)
    }
  }
  // 标题 & 更多行 TODO 更多
  @Builder Bar(title: string, more: string) {
    Row() {
      Row()
        .height(14)
        .width(6)
        .margin({ right: 2 })
        .borderRadius(4)
        .backgroundColor($r('app.color.primary_color'))
      Text(title)
        .fontColor($r('app.color.color_text_major'))
        .fontSize(16)
        .fontWeight(500)

      Blank()

      // TODO 打开更多
      //      Text('更多')
      //        .fontColor($r('app.color.color_text_major'))
      //        .fontSize(12)
      //      Image($r("app.media.ic_enter"))
      //        .width(24)
      //        .height(24)
      //        .fillColor('#817977')
      //        .alignSelf(ItemAlign.End)
      //        .objectFit(ImageFit.Contain)
    }
    .alignSelf(ItemAlign.Start)
    .width('100%')
    .padding({ left: 16, top: 16, right: 16, bottom: 0 })
  }

  private loadNextPage() {
    this.state = ViewState.LOADING
    DataSourceManager.getCurrentSource()
      .getHomepageData()
      .then((data) => {
        Logger.e(this, 'loadNextPage list=' + JSON.stringify(data))
        this.bannerList = data.bannerList
        this.categoryList = data.categoryList
        Logger.e(this, 'categoryList=' + JSON.stringify(data.categoryList))
        this.state = ViewState.CONTENT
      })
      .catch((e: Error) => {
        this.errorMessage = JSON.stringify(e)
        this.state = ViewState.ERROR
      })
  }

}