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

  /** 全局路由栈 */
  @Trace pageStack: NavPathStack = new NavPathStack()
  /** 全局 Tabs 控制器 */
  @Trace tabsController: TabsController = new TabsController()
  /** 当前 Tab 索引 */
  @Trace currentIndex: number = 0
  /** 是否处于二级页面（子页 onShown/onHidden 写入，MyPage 据此刷新历史） */
  @Trace onShow: boolean = false

  /** 系统深色模式（mediaQuery 监听，用于图标/图片资源切换） */
  @Trace darkModeImage: boolean = false
  /** 手机横屏状态 */
  @Trace isPhoneLandscape: boolean = false
  /** 窗口模式 true为PC窗口模式 false为普通窗口模式 */
  @Trace windowMode: boolean = false
  /** 当前生效颜色模式 */
  @Trace currentColorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET

  /** WebView JS 解析通道：是否显示隐藏 WebView */
  @Trace showWebView: boolean = false
  /** WebView JS 解析通道：目标页面地址 */
  @Trace webviewUrl: string = ''
  /** WebView JS 解析通道：待执行的 JS 表达式 */
  @Trace runJs: string = ''
  /** WebView JS 解析通道：JS 执行结果回传链接 */
  @Trace webJsVideoLink: string = ''

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
