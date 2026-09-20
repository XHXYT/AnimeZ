
import StateView, { ViewState } from '../components/StateView';
import { BannerView } from '../components/home/BannerView';
import { CategoryView } from '../components/home/CategoryView';
import { homeViewModel } from '../viewmodel/HomeViewModel';
import { AnimeState } from '../entryability/AnimeState';

// 系统路由
@Builder
export function HomePageBuilder(name: string, param: Object) {
  HomePage()
}

@ComponentV2
export struct HomePage {

  aboutToAppear() {
    homeViewModel.loadHomepageData()
    // SOURCE_CHANGED_EVENT 已由 homeViewModel 常驻订阅
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
          AnimeState.pageStack.pushPathByName("SearchPage", '', true)
        })

        Image($r("app.media.ic_download_manager"))
          .width(20)
          .height(20)
          .fillColor('#817977')
          .objectFit(ImageFit.Contain)
          .onClick(() => {
            AnimeState.pageStack.pushPathByName("DownloadManagerPage", '', true)
          })

        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(20)
          .fontColor(['#817977'])
          .onClick(() => {
            AnimeState.pageStack.pushPathByName("VideoHistoryPage", '', true)
          })
      }
      .height(56)
      .width('100%')
      .padding({left: 16, right: 16})
      // 视频推荐区
      StateView(
        {
          state: homeViewModel.state,
          errorMessage: homeViewModel.errorMessage,
          content: () => {
            this.Content()
          },
          onRetry: () => {
            homeViewModel.loadHomepageData()
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
    .padding({top: AnimeState.topRectHeight, bottom: AnimeState.bottomRectHeight - 20})
    .onShown(() => {
      homeViewModel.state = ViewState.CONTENT
    })
  }

  @Builder
  Content() {
    Stack() {
      Scroll() {
        Column() {
          // 轮播图
          BannerView({bannerList: homeViewModel.bannerList})
          // 视频目录
          CategoryView({categoryList: homeViewModel.categoryList})
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

}
