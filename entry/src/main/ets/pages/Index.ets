import { MyPage } from './MyPage';
import { HomePage } from './HomePage';
import { SchedulePage } from './SchedulePage';
import mediaQuery from '@ohos.mediaquery'
import { appSettings } from '../entryability/Settings';
import { AnimeState } from '../entryability/AnimeState';
import { deviceInfo } from '@kit.BasicServicesKit';
import { TabBarHeight, TabBarPosition, TabBarVertical, TabBarWidth } from '../utils/breakpoint/BreakPoint';
import { KeyCode } from '@kit.InputKit';
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
    this.DarkModeListener.on('change', (mediaQueryResult: mediaQuery.MediaQueryResult) => {
      AnimeState.darkModeImage = mediaQueryResult.matches as boolean
    })
    if (deviceInfo.deviceType === 'phone') {
      this.PhoneLandscapeListener.on('change', (mediaQueryResult: mediaQuery.MediaQueryResult) => {
        AnimeState.isPhoneLandscape = mediaQueryResult.matches
        console.info(`#媒体查询#手机横屏状态改变 结果: ${mediaQueryResult.matches}`)
      })
      AnimeState.isPhoneLandscape = this.PhoneLandscapeListener.matches
    }
  }

  onDidBuild(): void {
    setTimeout(() => {
      const appContinueData = appContinueModel.getCurrentVideoPageDetail()
      hilog.info(0x0000, 'AppContinue', 'Index - %{public}s', JSON.stringify(appContinueData))
      if (appContinueData.currentPage !== '' && typeof appContinueData.currentPageParams === 'object') {
        AnimeState.pushPage(appContinueData.currentPage, appContinueData.currentPageParams)
      }
    })
  }

  aboutToDisappear(): void {
    this.DarkModeListener.off('change')
    this.PhoneLandscapeListener.off('change')
  }


  build() {
    Stack() {
      if (AnimeState.windowMode) {
        // PC 窗口模式：外层 Navigation（全屏路由）+ 内层 row（侧边栏 + 右侧子页）
        Navigation(AnimeState.fullScreenStack) {
          Row() {
            // 左侧边栏
            Column() {
              this.PcSidebarHeader()
              this.PcTabItem(0, '首页', $r('app.media.ic_homepage'), $r('app.media.ic_homepage_selected'))
              this.PcTabItem(1, '周表', $r('app.media.ic_schedule'), $r('app.media.ic_schedule_selected'))
              this.PcTabItem(2, '我的', $r('app.media.ic_me'), $r('app.media.ic_me_selected'))
              this.PcTabItem(3, '收藏', $r('app.media.ic_collection_entry'), $r('app.media.ic_collection_entry_selected'), 'VideoCollectionPage')
              this.PcTabItem(4, '下载', $r('app.media.ic_download_entry'), $r('app.media.ic_download_entry_selected'), 'DownloadManagerPage')
              this.PcTabItem(5, '历史', $r('app.media.ic_history_entry'), $r('app.media.ic_history_entry_selected'), 'VideoHistoryPage')
            }
            .padding({ left: 16, right: 16 })
            .width(220)
            .height('100%')
            .backgroundColor($r('app.color.background_color'))

            // 右侧 Navigation（栈空时显示当前 Tab 主页，栈非空时显示 NavDestination 子页）
            Navigation(AnimeState.pageStack) {
              Stack() {
                HomePage()
                  .visibility(AnimeState.currentIndex === 0 ? Visibility.Visible : Visibility.Hidden)
                SchedulePage()
                  .visibility(AnimeState.currentIndex === 1 ? Visibility.Visible : Visibility.Hidden)
                MyPage()
                  .visibility(AnimeState.currentIndex === 2 ? Visibility.Visible : Visibility.Hidden)
              }
            }
            .hideToolBar(true)
            .backgroundColor($r('app.color.background_color_accent'))
            .mode(NavigationMode.Stack)
            .layoutWeight(1)
            .height('100%')
            .foregroundBlurStyle(appSettings.need_blur ? BlurStyle.Thin : BlurStyle.NONE,
              { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT, scale: 0.3 })
          }
          .width('100%')
          .height('100%')
        }
        .hideToolBar(true)
        .mode(NavigationMode.Stack)
        .width('100%')
        .height('100%')
        .focusable(true)
        .onKeyEvent((event: KeyEvent) => {
          if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
            AnimeState.popPage(true)
          }
        })
      } else {
        // 移动端：Tabs + Navigation 布局
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
          .scrollable(AnimeState.currentIndex !== 1)
        }.hideToolBar(true)
        .backgroundColor($r('app.color.background_color_accent'))
        .mode(NavigationMode.Stack)
        .width('100%').height('100%')
        .foregroundBlurStyle(appSettings.need_blur ? BlurStyle.Thin : BlurStyle.NONE,
          { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT, scale: 0.3 })
      }

      // 全局 WebView 解析悬浮层（顶层，平时不渲染任何节点）
      WebParseOverlay()
    }
    .width('100%')
    .height('100%')
  }

  // ===== PC 窗口模式侧边栏 =====

  @Builder PcSidebarHeader() {
    Text('AnimeZ')
      .fontSize(22)
      .fontWeight(700)
      .fontColor($r('app.color.color_text_major'))
      .width('100%')
      .textAlign(TextAlign.Start)
      .padding({ left: 4, top: AnimeState.topRectHeight + 24, bottom: 16 })
  }

  /** 侧边栏项是否高亮：普通 Tab 看 currentIndex（无子页时），页面项看 topPageName */
  private pcItemActive(index: number, pageName: string): boolean {
    if (pageName !== '') {
      return AnimeState.topPageName === pageName
    }
    return AnimeState.currentIndex === index && AnimeState.topPageName === ''
  }

  @Builder PcTabItem(index: number, title: string, icon: Resource, iconSelected: Resource, pageName: string = '') {
    Row({ space: 12 }) {
      Image(this.pcItemActive(index, pageName) ? iconSelected : icon)
        .width(22)
        .height(22)
        .objectFit(ImageFit.Contain)
      Text(title)
        .fontColor(this.pcItemActive(index, pageName) ? '#007DFF' : $r('app.color.color_text_major'))
        .fontSize(15)
        .fontWeight(this.pcItemActive(index, pageName) ? 600 : 400)
    }
    .padding({ left: 20, top: 16, bottom: 16, right: 20 })
    .margin({ bottom: 4 })
    .width('100%')
    .borderRadius(10)
    .backgroundColor(this.pcItemActive(index, pageName) ? $r('app.color.background_color_accent') : Color.Transparent)
    .onClick(() => {
      if (pageName === '') {
        AnimeState.currentIndex = index
      }
      AnimeState.clearAllStacks()
      if (pageName !== '') {
        AnimeState.pageStack.pushPathByName(pageName, '', true)
        AnimeState.topPageName = pageName
      }
      if (deviceInfo.deviceType === 'phone' && pageName === '') {
        AnimeState.tabsController.changeIndex(index)
      }
    })
  }

  // ===== 移动端 Tab 栏构建 =====

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
