import { bundleManager } from "@kit.AbilityKit"
import { SortType } from "../viewmodel/VideoSourcesViewModel"

// @StorageLink('app_settings')
export class AppConfigs {
  /**
   * 自动播放下一集，默认开启
   */
  auto_play_next_episode: boolean = true
  /**
   * 跟随传感器自动旋屏，默认开启
   */
  key_homepage_source: boolean = true
  /**
   * WiFi下自动播放，默认开启
   */
  auto_play_on_no_wifi: boolean = true
  /**
   * 启动app时，在WiFi下自动下载未完成任务，默认关闭
   */
  auto_resume_download_on_wifi: boolean = false
  /**
   * 背景模糊
   */
  need_blur: boolean = false
  /**
   * 最大同时下载任务数，默认为3
   */
  max_downloading_count: number = 3
  /**
   * 默认播放器
   */
  default_player: string = 'av'
  /**
   * 颜色模式，默认为 跟随系统
   */
  color_mode: number = ThemeColorMode.SYSTEM
  /**
   * 自动旋转
   */
  auto_sensor_rotate: boolean = false
  /**
   * 视频目录页列表类型
   */
  category_UI_type: number = 0
  /**
   * 视频剧集排列顺序
   */
  episodes_order: 'asc' | 'desc' = 'asc'
  /**
   * 视频源排序
   */
  video_sources_order: SortType = SortType.CUSTOM
  /**
   * 视频源分组筛选
   */
  video_sources_group_filter: string = '不分组'
  /**
   * 视频源分组管理
   */
  video_sources_group_filter_manager: string = ''
  /**
   * 视频源配置覆盖导入
   */
  video_source_import_overwrite: boolean = false

  constructor() {
  }

}


@Observed
export class AppSettings {

  static versionName = ""

  // 初始化
  static async init() {
    if (canIUse("SystemCapability.BundleManager.BundleFramework.Core")) {
      const packageInfo =
        await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
      AppSettings.versionName = packageInfo.versionName
    } else {
      console.error(`当前设备不支持包名查询 SystemCapability.BundleManager.BundleFramework.Core`)
    }
    PersistentStorage.persistProp("AppSettings", new AppConfigs())
  }

  static Serializable(obj: AppConfigs)  {
    return Object.keys(obj).map(key => `${encodeURIComponent(key)}=${encodeURIComponent(Reflect.get(obj, key))}`).join('&');
  }

  // 清理数据 还原默认值
  static async ResetSettings(context: Context) {
    AppStorage.set("AppSettings", new AppConfigs())
  }

}