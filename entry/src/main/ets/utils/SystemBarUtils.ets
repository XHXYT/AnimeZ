import Logger from './Logger';
import window from '@ohos.window';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { appSettings } from '../entryability/Settings';
import { AnimeState } from '../entryability/AnimeState';

/**
 * 状态栏和导航栏工具类
 */
export default class SystemBarUtils {

  /** 当前是否为视频详情页样式（浅色模式下状态栏文字用主题色），颜色模式切换后按此重绘 */
  private static detailStyle: boolean = false

  /**
   * 设置状态栏和导航栏
   * @param systemBarProperties
   */
  static setWindowSystemBarProperties(systemBarProperties: window.SystemBarProperties) {
    window.getLastWindow(getContext(SystemBarUtils), (err, win) => {
      Logger.e('tips', 'setWindowSystemBarProperties win=' + JSON.stringify(win) + ' err=' + JSON.stringify(err))
      try {
        if (win) {
          // 透明状态栏和导航栏
          win.setWindowSystemBarProperties(systemBarProperties, null);
        }
      } catch (e) {
        Logger.e('tips', 'setWindowSystemBarProperties error! e=' + JSON.stringify(e))
      }
    })
  }

  /**
   * 当前应用生效的颜色模式是否为深色（应用设置优先，跟随系统时取系统配置）
   */
  static isAppDarkMode(): boolean {
    if (appSettings.color_mode === ThemeColorMode.DARK) {
      return true
    }
    if (appSettings.color_mode === ThemeColorMode.LIGHT) {
      return false
    }
    return AnimeState.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
  }

  /**
   * 设置状态栏和导航栏为透明底，内容颜色跟随应用深浅色
   * @param isDetailStyle 视频详情页样式（浅色下播放器深色/页面浅色各占一半，用中性灰保证两侧都可读）
   */
  static setWindowSystemBarTransparent(isDetailStyle: boolean = true) {
    SystemBarUtils.detailStyle = isDetailStyle
    const isDark: boolean = SystemBarUtils.isAppDarkMode()
    SystemBarUtils.setWindowSystemBarProperties({
      statusBarColor: '#00000000', // 透明
      statusBarContentColor: isDark ? '#FFFFFF' : (isDetailStyle ? '#ff888888' : '#000000'),
      navigationBarColor: '#00000000',
      navigationBarContentColor: isDark ? '#FFFFFF' : '#000000'
    })
  }

  /**
   * 颜色模式变化后按最近一次样式重新应用系统栏颜色
   */
  static reapplyWindowSystemBar(): void {
    SystemBarUtils.setWindowSystemBarTransparent(SystemBarUtils.detailStyle)
  }
}
