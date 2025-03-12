import Logger from './Logger';
import window from '@ohos.window';

/**
 * 状态栏和导航栏工具类
 */
export default class SystemBarUtils {

  /**
   * 设置状态栏和导航栏
   * @param systemBarProperties
   */
  static setWindowSystemBarProperties(systemBarProperties: window.SystemBarProperties) {
    window.getLastWindow(getContext(SystemBarUtils), (err, win) => {
      Logger.e(SystemBarUtils, 'setWindowSystemBarProperties win=' + JSON.stringify(win) + ' err=' + JSON.stringify(err))
      try {
        if (win) {
          // 透明状态栏和导航栏
          win.setWindowSystemBarProperties(systemBarProperties, null);
        }
      } catch (e) {
        Logger.e(SystemBarUtils, 'setWindowSystemBarProperties error! e=' + JSON.stringify(e))
      }
    })
  }

  /**
   * 设置状态栏和导航栏颜色等属性
   * @param systemBarProperties
   */
  static setWindowSystemBarTransparent(isDarkContent: boolean = true) {
    SystemBarUtils.setWindowSystemBarProperties({
      statusBarColor: '#00000000', // 透明
      statusBarContentColor: isDarkContent ? '#ff8f7a7a' : '#000000',
      navigationBarColor: '#00000000',
      navigationBarContentColor: isDarkContent ? '#000000' : '#FFFFFF'
    })
  }

}