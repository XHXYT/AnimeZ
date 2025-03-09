import DataStore from './DataStore';

/**
 * app设置
 */
export default class Settings {
  static KEY_AUTO_PLAY_NEXT_EPISODE = 'key_auto_play_next_episode'
  static KEY_HOMEPAGE_SOURCE = 'key_homepage_source'
  static KEY_AUTO_PLAY_ON_NO_WIFI = 'key_auto_play_on_no_wifi'
  static KEY_AUTO_RESUME_DOWNLOAD_ON_WIFI = 'key_auto_resume_download_on_wifi'
  static KEY_MAX_DOWNLOADING_COUNT = 'key_max_downloading_count'
  static KEY_DEFAULT_PLAYER = 'key_default_player'
  static KEY_COLOR_MODE = 'key_color_mode'

  /**
   * 自动播放下一集，默认开启
   */
  static isAutoPlayNextEpisode(): boolean {
    return DataStore.getBoolean(Settings.KEY_AUTO_PLAY_NEXT_EPISODE, true)
  }

  /**
   * Wifi下自动播放，默认开启
   */
  static isAutoPlayOnNoWifi(): boolean {
    return DataStore.getBoolean(Settings.KEY_AUTO_PLAY_ON_NO_WIFI, true)
  }

  /**
   * 启动app时，在Wifi下自动下载未完成任务，默认关闭
   */
  static isAutoResumeDownloadOnWifi(): boolean {
    return DataStore.getBoolean(Settings.KEY_AUTO_PLAY_ON_NO_WIFI, false)
  }

  /**
   * 最大同时下载任务数，默认为3
   */
  static getMaxDownloadingCount(): number {
    return DataStore.getInt(Settings.KEY_MAX_DOWNLOADING_COUNT, 3)
  }

  static getDefaultPlayerType(): number {
    return DataStore.getInt(Settings.KEY_DEFAULT_PLAYER, -1)
  }

  /**
   * 颜色模式，默认为 跟随系统
   */
  static getColorMode(): number {
    return DataStore.getInt(Settings.KEY_COLOR_MODE, -1)
  }

}