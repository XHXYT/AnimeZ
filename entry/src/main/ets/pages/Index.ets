import { MyPage } from './MyPage';
import { HomePage } from './Homepage';
import mediaQuery from '@ohos.mediaquery'
import { initDataSources } from '../api/DataSourceManager';
import { setAutoColorMode, setDarkColorMode, setLightColorMode } from '../utils/ColorModeManager';
import { common } from '@kit.AbilityKit';
import DataStore from '../utils/DataStore';
import Settings from '../utils/Settings';
import { BreakpointState, BreakpointSystem } from '../utils/BreakPointManager';
import { CompStr,
  HomeBannerBannerMargin,
  HomeBannerDisplayCount,
  TabBarHeight,
  TabBarWidth,
  TabVertical,
  TabBarPosition,
  VideoDetailGridColHeight,
  VideoListColumnsTemplate } from '../components/common/BreakPoint';
import { deviceInfo } from '@kit.BasicServicesKit';

const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

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
  @StorageLink('currentColorMode') currentMode: number = -1
  private controller: TabsController = new TabsController()
  @Provide('pageStack') pageStack: NavPathStack = new NavPathStack()
  // 断点
  @Provide('CompStr') compStr: BreakpointState<string> = CompStr
  // Tab栏宽度
  @Provide('TabBarWidth') tabBarWidth: BreakpointState<string> = TabBarWidth
  // tab栏位置
  @Provide('TabVertical') tabVertical: BreakpointState<boolean> = TabVertical
  // Tab栏高度
  @Provide('TabBarHeight') tabBarHeight: BreakpointState<string> = TabBarHeight
  // Tab栏位置
  @Provide('TabBarPosition') tabBarPosition: BreakpointState<BarPosition> = TabBarPosition
  // 首页轮播图显示数量
  @Provide('HomeBannerDisplayCount') homeBannerDisplayCount: BreakpointState<number> = HomeBannerDisplayCount
  // 首页轮播图前&后边距（前后露出的部分
  @Provide('HomeBannerBannerMargin') homeBannerBannerMargin: BreakpointState<number> = HomeBannerBannerMargin
  // 视频详情页GridCol高度
  @Provide('VideoDetailGridColHeight') videoDetailGridColHeight: BreakpointState<Length> = VideoDetailGridColHeight
  // 视频列表Grid列数
  @Provide('VideoListColumnsTemplate') videoListColumnsTemplate: BreakpointState<string> = VideoListColumnsTemplate

  /**系统为深色模式时为true，否则为false*/
  DarkModeListener: mediaQuery.MediaQueryListener = mediaQuery.matchMediaSync('(dark-mode: true)')
  /**手机横屏监听*/
  PhoneLandscapeListener: mediaQuery.MediaQueryListener =
    this.getUIContext().getMediaQuery().matchMediaSync('(320vp< height <= 500vp) and (640vp< width <= 1000vp)')

  aboutToAppear() {
    // 初始化视频数据源
    initDataSources()
    // 初始化颜色模式
    this.switchColorMode(DataStore.getInt(Settings.KEY_COLOR_MODE, -1))
    // 初始化断点系统
    BreakpointSystem.getInstance().start()
    BreakpointSystem.getInstance().attach(this.compStr)
    BreakpointSystem.getInstance().attach(this.tabBarWidth)
    BreakpointSystem.getInstance().attach(this.tabVertical)
    BreakpointSystem.getInstance().attach(this.tabBarHeight)
    BreakpointSystem.getInstance().attach(this.tabBarPosition)
    BreakpointSystem.getInstance().attach(this.homeBannerDisplayCount)
    BreakpointSystem.getInstance().attach(this.homeBannerBannerMargin)
    BreakpointSystem.getInstance().attach(this.videoDetailGridColHeight)
    BreakpointSystem.getInstance().attach(this.videoListColumnsTemplate)
    // 启用颜色模式监听
    this.DarkModeListener.on('change', (mediaQueryResult: mediaQuery.MediaQueryResult) => {
      this.DarkModeImage  = mediaQueryResult.matches as boolean
    })
    // 当开启自动旋屏和设备类型为手机时启用手机横屏监听
    if (DataStore.getBoolean(Settings.KEY_SENSOR_ROTATE, true) /*&& deviceInfo.deviceType === 'phone'*/) {
      this.PhoneLandscapeListener.on('change', (mediaQueryResult: mediaQuery.MediaQueryResult) => {
        this.isPhoneLandscape = mediaQueryResult.matches
        console.info(`#媒体查询#手机横屏状态改变 结果: ${mediaQueryResult.matches}`)
      })
    }
  }

  aboutToDisappear(): void {
    // 停止各种监听事件
    BreakpointSystem.getInstance().stop()
    this.DarkModeListener.off('change')
    this.PhoneLandscapeListener.off('change')
  }

  /**
   * 切换颜色模式
   * @param index 颜色模式序号
   */
  switchColorMode(index: number) {
    switch (index) {
      case -1:
        // 跟随系统
        setAutoColorMode(context)
        break;
      case 0:
        // 夜晚
        setDarkColorMode(context)
        break
      case 1:
        // 白天
        setLightColorMode(context)
        break
    }
  }


  build() {
    Navigation(this.pageStack) {
      Tabs({
        barPosition: this.isPhoneLandscape ? BarPosition.Start : this.tabBarPosition.value,
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
      .vertical(this.isPhoneLandscape ? true : this.tabVertical.value)
      .barWidth(this.isPhoneLandscape ? '54vp' : this.tabBarWidth.value)
      .barHeight(this.isPhoneLandscape ? '100%' : this.tabBarHeight.value)
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