import { MyPage } from './MyPage';
import { HomePage } from './Homepage';
import mediaQuery from '@ohos.mediaquery'
import { common } from '@kit.AbilityKit';
import { AppConfigs } from '../entryability/Settings';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ColorModeManager } from '../utils/ColorModeManager';
import { TabBarHeight, TabBarPosition, TabBarVertical, TabBarWidth } from '../utils/breakpoint/BreakPoint';
import { appContinueModel } from '../viewmodel/AppContinueModel';
import { hilog } from '@kit.PerformanceAnalysisKit';

@Entry
@Component
struct Index {
  @State currentIndex: number = 0
  @Provide onShow: boolean = false
  // 深色模式监听
  @Provide DarkModeImage: boolean = false
  // 页面加载状态
  @Provide('StateView') state: number = 0
  // 手机横屏监听
  @Provide isPhoneLandscape: boolean = false
  // 顶部避让高度
  @StorageProp('topRectHeight') topHeight: number = 0
  // 底部避让高度
  @StorageProp('bottomRectHeight') bottomHeight: number = 0
  // 宽度断点
  @StorageLink('currentWidthBreakpoint') widthBp: WidthBreakpoint = 1
  // 高度断点
  @StorageLink('currentHeightBreakpoint') heightBp: HeightBreakpoint = 0

  private controller: TabsController = new TabsController()
  @Provide('pageStack') pageStack: NavPathStack = new NavPathStack()
  // 应用设置
  @StorageLink('AppSettings') appSettings: AppConfigs = new AppConfigs()

  private context: common.UIAbilityContext = this.getUIContext().getHostContext()! as common.UIAbilityContext
  /** 系统为深色模式时为true，否则为false */
  DarkModeListener: mediaQuery.MediaQueryListener = this.getUIContext().getMediaQuery().matchMediaSync('(dark-mode: true)')
  /**手机横屏监听*/
  PhoneLandscapeListener: mediaQuery.MediaQueryListener = this.getUIContext().getMediaQuery().matchMediaSync('(320vp< height <= 500vp) and (640vp< width <= 1000vp)')

  aboutToAppear() {
    // 初始化颜色模式
    console.log(`当前颜色模式：${this.appSettings.color_mode}`)
    ColorModeManager.switchColorMode(this.context, this.appSettings.color_mode)
    // 启用颜色模式监听
    this.DarkModeListener.on('change', (mediaQueryResult: mediaQuery.MediaQueryResult) => {
      this.DarkModeImage  = mediaQueryResult.matches as boolean
    })
    // 当开启自动旋屏和设备类型为手机时启用手机横屏监听
    if (this.appSettings.auto_sensor_rotate && deviceInfo.deviceType === 'phone') {
      this.PhoneLandscapeListener.on('change', (mediaQueryResult: mediaQuery.MediaQueryResult) => {
        this.isPhoneLandscape = mediaQueryResult.matches
        console.info(`#媒体查询#手机横屏状态改变 结果: ${mediaQueryResult.matches}`)
      })
    }
  }

  onDidBuild(): void {
    // 应用接续 -> 恢复页面
    setTimeout(() => {
      const appContinueData = appContinueModel.getCurrentVideoPageDetail()
      hilog.info(0x0000, 'AppContinue', 'Index - %{public}s', JSON.stringify(appContinueData))
      if (appContinueData.currentPage !== '' && typeof appContinueData.currentPageParams === 'object') {
        this.pageStack.pushPathByName(appContinueData.currentPage, appContinueData.currentPageParams)
      }
    })
  }

  aboutToDisappear(): void {
    // 停止各种监听事件
    this.DarkModeListener.off('change')
    this.PhoneLandscapeListener.off('change')
  }


  build() {
    Navigation(this.pageStack) {
      Tabs({
        barPosition: TabBarPosition(this.widthBp, this.heightBp),
        controller: this.controller
      }) {
        TabContent() {
          HomePage()
        }
        .tabBar(this.TabBarBuilder(0, '首页', $r('app.media.ic_homepage'), $r('app.media.ic_homepage_selected')))
        .onWillShow(() => {
          this.currentIndex = 0
        })
        TabContent() {
          MyPage()
        }
        .tabBar(this.TabBarBuilder(1, '我的', $r('app.media.ic_me'), $r('app.media.ic_me_selected')))
        .onWillShow(() => {
          this.currentIndex = 1
        })
      }.layoutWeight(1)
      .barMode(BarMode.Fixed)
      .vertical(TabBarVertical(this.widthBp, this.heightBp))
      .barWidth(TabBarWidth(this.widthBp, this.heightBp))
      .barHeight(TabBarHeight(this.widthBp, this.heightBp))
      .onChange((index: number) => {
        this.currentIndex = index
      })
    }.hideToolBar(true)
    .mode(NavigationMode.Stack)
    .width('100%').height('100%')
  }

  @Builder TabBarBuilder(index: number, title: string, icon: Resource, iconSelected: Resource) {
    Column({space: 3}) {
      Image(this.currentIndex === index ? iconSelected : icon)
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
      Text(title)
        .fontColor(this.currentIndex === index ? '#007DFF' : '#817977')
        .margin({bottom: this.bottomHeight})
        .fontSize(12)
        .fontWeight(400)
        .lineHeight(14)
    }
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.currentIndex === 0 ? $r('app.color.background_color') : $r('app.color.background_color_accent'))
    .height('100%')
    .width('100%')
  }
}