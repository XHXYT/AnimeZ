import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

/**
 * 全局应用状态单例
 * 模式：@ObservedV2 + @Trace 实现跨组件响应式
 */
@ObservedV2
export class _AnimeState {

  /** 顶部避让高度 */
  @Trace topRectHeight: number = 0
  /** 底部避让高度 */
  @Trace bottomRectHeight: number = 0

  /** 宽度断点 */
  @Trace widthBp: WidthBreakpoint = WidthBreakpoint.WIDTH_SM
  /** 高度断点 */
  @Trace heightBp: HeightBreakpoint = HeightBreakpoint.HEIGHT_SM

  /** 窗口高度 -vp */
  @Trace windowHeight: number = 0
  /** 窗口宽度 -vp */
  @Trace windowWidth: number = 0

  /** 全局路由栈（侧边栏内） */
  @Trace pageStack: NavPathStack = new NavPathStack()
  /** 全屏路由栈（PC 模式下视频详情/本地播放等全屏页面） */
  @Trace fullScreenStack: NavPathStack = new NavPathStack()
  /** 全局 Tabs 控制器 */
  @Trace tabsController: TabsController = new TabsController()
  /** 当前 Tab 索引 */
  @Trace currentIndex: number = 0
  /** 是否处于二级页面（子页 onShown/onHidden 写入，MyPage 据此刷新历史） */
  @Trace onShow: boolean = false
  /** pageStack 当前栈顶页面名（navBar/空串表示主页），侧边栏下载/历史入口高亮用 */
  @Trace topPageName: string = ''

  /** 系统深色模式（mediaQuery 监听，用于图标/图片资源切换） */
  @Trace darkModeImage: boolean = false
  /** 手机横屏状态 */
  @Trace isPhoneLandscape: boolean = false
  /** 窗口模式 true为PC窗口模式 false为普通窗口模式 */
  @Trace windowMode: boolean = false
  /** 窗口模式右上角系统三键区域避让宽度（vp） */
  @Trace titleButtonWidth: number = 0
  /** 窗口模式系统三键图标中心线距窗口顶部距离（vp），用于垂直对齐 */
  @Trace titleButtonCenter: number = 0
  /** 当前生效颜色模式 */
  @Trace currentColorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET

  /** PC 全屏页面集合（在 windowMode 下推送至 fullScreenStack） */
  private static readonly FULLSCREEN_PAGES: Set<string> = new Set(['VideoDetailPage', 'LocalVideoPlayerPage'])

  constructor() {
    // 监听 pageStack 栈顶变化，维护 topPageName（'navBar' 表示回到主页）
    this.pageStack.setInterception({
      didShow: (from: NavDestinationContext | NavBar, to: NavDestinationContext | NavBar,
        operation: NavigationOperation, isAnimated: boolean): void => {
        this.topPageName = to === 'navBar' ? '' : to.pathInfo.name
      }
    })
  }

  /** 智能推栈：全屏页面走 fullScreenStack，其余走 pageStack */
  pushPage(name: string, param: Object, isSingle: boolean = false): void {
    if (this.windowMode && _AnimeState.FULLSCREEN_PAGES.has(name)) {
      this.fullScreenStack.pushPathByName(name, param, isSingle)
    } else {
      this.pageStack.pushPathByName(name, param, isSingle)
    }
  }

  /** 智能弹栈：优先弹 fullScreenStack，空则弹 pageStack */
  popPage(useAnim: boolean = false): void {
    if (this.fullScreenStack.size() > 0) {
      this.fullScreenStack.pop(useAnim)
    } else {
      this.pageStack.pop(useAnim)
    }
  }

  /** 清空所有栈 + 切 Tab */
  clearAllStacks(): void {
    this.fullScreenStack.clear()
    this.pageStack.clear()
    this.topPageName = ''
  }

  /** WebView JS 解析通道：是否显示隐藏 WebView */
  @Trace showWebView: boolean = false
  /** WebView JS 解析通道：目标页面地址 */
  @Trace webviewUrl: string = ''
  /** WebView JS 解析通道：待执行的 JS 表达式 */
  @Trace runJs: string = ''
  /** WebView JS 解析通道：JS 执行结果回传链接 */
  @Trace webJsVideoLink: string = ''
  /** WebView JS 解析通道：手动模式（显示完整页面，等待用户点击站点播放按钮后经桥回传结果） */
  @Trace webviewManual: boolean = false
  /** WebView JS 解析通道：手动模式触发原因（展示给用户的当前状态说明） */
  @Trace webviewManualReason: string = ''
  /** WebView JS 解析通道：自定义 User-Agent（空=系统默认；由源级 userAgent 配置在发起解析时写入） */
  @Trace webviewUserAgent: string = ''

  /** 当前播放媒体标题（投播元数据展示用） */
  @Trace playingTitle: string = ''
  /** 当前播放媒体封面URL（投播元数据展示用） */
  @Trace playingCoverUrl: string = ''

  // ===== 非响应式静态资源 =====
  /** UI 上下文 */
  public static UIContext: UIContext | null = null
  /** 应用上下文 */
  public static Context: common.UIAbilityContext | null = null
  /** 主窗口对象 */
  public static window: window.Window | null = null
  /** 设备产品型号 */
  public static DeviceProductModel: string = ''
  /** 应用版本名 */
  public static appVersion: string = ''
}

export const AnimeState: _AnimeState = new _AnimeState()
