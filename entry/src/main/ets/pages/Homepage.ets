import promptAction from '@ohos.promptAction';
import router from '@ohos.router';
import VideoInfo from '../entity/VideoInfo';
import { DramaList } from '../entity/HomepageData';
import { ConfigurationConstant } from '@kit.AbilityKit';
import StateView, { ViewState } from '../components/StateView';
import { SOURCE_CHANGED_EVENT } from '../utils/EventBus';
import { VideoList } from '../components/VideoList';
import Logger from '../utils/Logger';
import { BannerView } from '../components/home/BannerView';
import { CategoryView } from '../components/home/CategoryView';
import { dataSourceManager } from '../api/DataSourceManager';

// 系统路由
@Builder
export function HomePageBuilder(name: string, param: Object) {
  HomePage()
}

@Component
export struct HomePage {
  @State state: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('currentColorMode') currentMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
  // 顶部避让高度
  @StorageProp('topRectHeight') topHeight: number = 0
  // 底部避让高度
  @StorageProp('bottomRectHeight') bottomHeight: number = 0
  @State bannerList: VideoInfo[] = []
  @State categoryList: DramaList[] = []
  @State errorMessage: string = ''

  aboutToAppear() {
    this.loadNextPage()
    // 启用数据源监听
    SOURCE_CHANGED_EVENT.on(() => {
      this.loadNextPage()
    })
  }

  aboutToDisappear() {
    SOURCE_CHANGED_EVENT.off()
  }

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
      // 视频推荐区
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

    }.width('100%')
    .height('100%')
    .hideToolBar(true)
    .backgroundColor($r('app.color.background_color'))
    .padding({top: this.topHeight, bottom: this.bottomHeight - 20})
    .onShown(() => {
      this.state = ViewState.CONTENT
    })
  }

  @Builder
  Content() {
    Stack() {
      Scroll() {
        Column() {
          // 轮播图
          BannerView({bannerList: this.bannerList})
          // 视频目录
          CategoryView({categoryList: this.categoryList})
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

  private loadNextPage() {
    this.state = ViewState.LOADING
    dataSourceManager.getHomepageData()
      .then((data) => {
        Logger.e('tips', 'loadNextPage list=' + JSON.stringify(data))
        this.bannerList = data.bannerList
        this.categoryList = data.categoryList
        Logger.e('tips', 'categoryList=' + JSON.stringify(data.categoryList))
        this.state = ViewState.CONTENT
      })
      .catch((e: Error) => {
        this.errorMessage = e.message
        this.state = ViewState.ERROR
        console.log(`主页state状态：${this.state}`)
        Logger.e('fail', '主页数据加载', e)
      })
  }

}
