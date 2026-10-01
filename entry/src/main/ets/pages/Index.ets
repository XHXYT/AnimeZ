import { MyPage } from './MyPage';
import { HomePage } from './HomePage';
import { SchedulePage } from './SchedulePage';
import mediaQuery from '@ohos.mediaquery'
import { appSettings } from '../entryability/Settings';
import { AnimeState } from '../entryability/AnimeState';
import { deviceInfo } from '@kit.BasicServicesKit';
import { TabBarHeight, TabBarPosition, TabBarVertical, TabBarWidth } from '../utils/breakpoint/BreakPoint';
import { appContinueModel } from '../viewmodel/AppContinueModel';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WebParseOverlay } from '../components/WebParseOverlay';

@Entry
@ComponentV2
struct Index {

  /** 深色模式监听 */
  DarkModeListener: mediaQuery.MediaQueryListener = this.getUIContext().getMediaQuery().matchMediaSync('(dark-mode: true)')
  /**手机横屏监听*/
  PhoneLandscapeListener: mediaQuery.MediaQueryListener = this.getUIContext().getMediaQuery().matchMediaSync('(320vp< height <= 500vp) and (640vp< width <= 1000vp)')

  aboutToAppear() {
    // 颜色模式初始化已由 EntryAbility 启动链完成
    // 启用颜色模式监听
    this.DarkModeListener.on('change', (mediaQueryResult: mediaQuery.MediaQueryResult) => {
      AnimeState.darkModeImage = mediaQueryResult.matches as boolean
    })
    // 当设备类型为手机时启用手机横屏监听（是否响应由 VideoDetailViewModel 结合"自动旋屏"设置判断，改设置无需重启）
    if (deviceInfo.deviceType === 'phone') {
      this.PhoneLandscapeListener.on('change', (mediaQueryResult: mediaQuery.MediaQueryResult) => {
        AnimeState.isPhoneLandscape = mediaQueryResult.matches
        console.info(`#媒体查询#手机横屏状态改变 结果: ${mediaQueryResult.matches}`)
      })
      // 读取初始状态，覆盖应用启动时已处于横屏的场景
      AnimeState.isPhoneLandscape = this.PhoneLandscapeListener.matches
    }
  }

  onDidBuild(): void {
    // 应用接续 -> 恢复页面
    setTimeout(() => {
      const appContinueData = appContinueModel.getCurrentVideoPageDetail()
      hilog.info(0x0000, 'AppContinue', 'Index - %{public}s', JSON.stringify(appContinueData))
      if (appContinueData.currentPage !== '' && typeof appContinueData.currentPageParams === 'object') {
        AnimeState.pageStack.pushPathByName(appContinueData.currentPage, appContinueData.currentPageParams)
      }
    })
  }

  aboutToDisappear(): void {
    // 停止各种监听事件
    this.DarkModeListener.off('change')
    this.PhoneLandscapeListener.off('change')
  }


  build() {
    Stack() {
      Navigation(AnimeState.pageStack) {
        Tabs({
          barPosition: TabBarPosition(AnimeState.widthBp, AnimeState.heightBp),
          controller: AnimeState.tabsController
        }) {
          TabContent() {
            HomePage()
          }
          .tabBar(this.TabBarBuilder(0, '首页', $r('app.media.ic_homepage'), $r('app.media.ic_homepage_selected')))
          .onWillShow(() => {
            AnimeState.currentIndex = 0
          })
          TabContent() {
            SchedulePage()
          }
          .tabBar(this.TabBarBuilder(1, '周表', $r('app.media.ic_schedule'), $r('app.media.ic_schedule_selected')))
          .onWillShow(() => {
            AnimeState.currentIndex = 1
          })
          TabContent() {
            MyPage()
          }
          .tabBar(this.TabBarBuilder(2, '我的', $r('app.media.ic_me'), $r('app.media.ic_me_selected')))
          .onWillShow(() => {
            AnimeState.currentIndex = 2
          })
        }.layoutWeight(1)
        .barMode(BarMode.Fixed)
        .vertical(TabBarVertical(AnimeState.widthBp, AnimeState.heightBp))
        .barWidth(TabBarWidth(AnimeState.widthBp, AnimeState.heightBp))
        .barHeight(TabBarHeight(AnimeState.widthBp, AnimeState.heightBp))
        .onChange((index: number) => {
          AnimeState.currentIndex = index
        })
        // 仅周表 Tab 禁用主 Tab 滑动切换：左右滑动优先切换星期（见 SchedulePage 的 PanGesture），
        // 周界后继续外滑由 SchedulePage 程序化 changeIndex 联动切换主 Tab
        .scrollable(AnimeState.currentIndex !== 1)
      }.hideToolBar(true)
      .backgroundColor($r('app.color.background_color_accent'))
      .mode(NavigationMode.Stack)
      .width('100%').height('100%')
      .foregroundBlurStyle(appSettings.need_blur ? BlurStyle.Thin : BlurStyle.NONE,
        { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT, scale: 0.3 })

      // 全局 WebView 解析悬浮层（顶层，平时不渲染任何节点）
      WebParseOverlay()
    }
    .width('100%')
    .height('100%')
  }

  @Builder TabBarBuilder(index: number, title: string, icon: Resource, iconSelected: Resource) {
    Column({space: 3}) {
      Image(AnimeState.currentIndex === index ? iconSelected : icon)
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
      Text(title)
        .fontColor(AnimeState.currentIndex === index ? '#007DFF' : '#817977')
        .margin({bottom: AnimeState.bottomRectHeight})
        .fontSize(12)
        .fontWeight(400)
        .lineHeight(14)
    }
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.background_color'))
    .padding({ top: 8 })
    .height('100%')
    .width('100%')
  }
}
