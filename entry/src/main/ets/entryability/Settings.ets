import { bundleManager } from "@kit.AbilityKit"
import { SortType } from "../viewmodel/VideoSourcesViewModel"
import { preferenceUtil } from "../utils/PreferenceUtil"
import Logger from "../utils/Logger"
import { _AnimeState } from "./AnimeState"

const SETTINGS_KEY = 'app_settings'

/**
 * 应用配置（V2）
 * @ObservedV2 + @Trace：任一处修改即刻全局响应；@Monitor 监听字段变化自动持久化到 preferences。
 */
@ObservedV2
export class AppConfigs {
  /**
   * 自动播放下一集，默认开启
   */
  @Trace auto_play_next_episode: boolean = true
  /**
   * 跟随传感器自动旋屏，默认开启
   */
  @Trace key_homepage_source: boolean = true
  /**
   * WiFi下自动播放，默认开启
   */
  @Trace auto_play_on_no_wifi: boolean = true
  /**
   * 启动app时，在WiFi下自动下载未完成任务，默认关闭
   */
  @Trace auto_resume_download_on_wifi: boolean = false
  /**
   * 背景模糊
   */
  @Trace need_blur: boolean = false
  /**
   * 最大同时下载任务数，默认为3
   */
  @Trace max_downloading_count: number = 3
  /**
   * 默认播放器
   */
  @Trace default_player: string = 'av'
  /**
   * 颜色模式，默认为 跟随系统
   */
  @Trace color_mode: number = ThemeColorMode.SYSTEM
  /**
   * 自动旋转
   */
  @Trace auto_sensor_rotate: boolean = false
  /**
   * 视频目录页列表类型
   */
  @Trace category_UI_type: number = 0
  /**
   * 视频剧集排列顺序
   */
  @Trace episodes_order: 'asc' | 'desc' = 'asc'
  /**
   * 视频源排序
   */
  @Trace video_sources_order: SortType = SortType.CUSTOM
  /**
   * 视频源分组筛选
   */
  @Trace video_sources_group_filter: string = '不分组'
  /**
   * 视频源分组管理
   */
  @Trace video_sources_group_filter_manager: string = ''
  /**
   * 视频源配置覆盖导入
   */
  @Trace video_source_import_overwrite: boolean = false

  /** 加载/重置期间置为 true，@Monitor 触发的 save() 直接跳过，避免逐字段赋值引发多次落盘 */
  private isLoading: boolean = false

  constructor() {
  }

  /**
   * 从 preferences 加载配置；首次运行时执行旧版 PersistentStorage 数据的一次性迁移
   */
  public async load(): Promise<void> {
    this.isLoading = true
    try {
      const jsonStr: string = await preferenceUtil.get<string>(SETTINGS_KEY, "")
      if (jsonStr) {
        this.applyJson(jsonStr)
        Logger.i('Settings', '应用配置加载成功')
      } else {
        // preferences 中无数据 → 尝试旧版本 PersistentStorage 数据迁移
        await this.migrateFromLegacy()
        this.isLoading = false
        await this.save()
      }
    } catch (e) {
      Logger.e('fail', '应用配置加载', e)
    }
    this.isLoading = false
  }

  private applyJson(jsonStr: string): void {
    const json: Record<string, Object> = JSON.parse(jsonStr)
    this.auto_play_next_episode = (json["auto_play_next_episode"] as boolean) ?? this.auto_play_next_episode
    this.key_homepage_source = (json["key_homepage_source"] as boolean) ?? this.key_homepage_source
    this.auto_play_on_no_wifi = (json["auto_play_on_no_wifi"] as boolean) ?? this.auto_play_on_no_wifi
    this.auto_resume_download_on_wifi =
      (json["auto_resume_download_on_wifi"] as boolean) ?? this.auto_resume_download_on_wifi
    this.need_blur = (json["need_blur"] as boolean) ?? this.need_blur
    this.max_downloading_count = (json["max_downloading_count"] as number) ?? this.max_downloading_count
    this.default_player = (json["default_player"] as string) ?? this.default_player
    this.color_mode = (json["color_mode"] as number) ?? this.color_mode
    this.auto_sensor_rotate = (json["auto_sensor_rotate"] as boolean) ?? this.auto_sensor_rotate
    this.category_UI_type = (json["category_UI_type"] as number) ?? this.category_UI_type
    this.episodes_order = (json["episodes_order"] as 'asc' | 'desc') ?? this.episodes_order
    this.video_sources_order = (json["video_sources_order"] as SortType) ?? this.video_sources_order
    this.video_sources_group_filter = (json["video_sources_group_filter"] as string) ?? this.video_sources_group_filter
    this.video_sources_group_filter_manager =
      (json["video_sources_group_filter_manager"] as string) ?? this.video_sources_group_filter_manager
    this.video_source_import_overwrite =
      (json["video_source_import_overwrite"] as boolean) ?? this.video_source_import_overwrite
  }

  /**
   * 旧版数据一次性迁移：PersistentStorage('AppSettings') → preferences('app_settings')
   * 注意：用纯 Record 读取旧数据，避免 @ObservedV2 实例进入 V1 状态管理机制
   */
  private async migrateFromLegacy(): Promise<void> {
    try {
      PersistentStorage.persistProp("AppSettings", {} as Record<string, Object>)
      const legacy = AppStorage.get<Record<string, Object>>("AppSettings")
      if (legacy) {
        this.auto_play_next_episode = (legacy["auto_play_next_episode"] as boolean) ?? this.auto_play_next_episode
        this.key_homepage_source = (legacy["key_homepage_source"] as boolean) ?? this.key_homepage_source
        this.auto_play_on_no_wifi = (legacy["auto_play_on_no_wifi"] as boolean) ?? this.auto_play_on_no_wifi
        this.auto_resume_download_on_wifi =
          (legacy["auto_resume_download_on_wifi"] as boolean) ?? this.auto_resume_download_on_wifi
        this.need_blur = (legacy["need_blur"] as boolean) ?? this.need_blur
        this.max_downloading_count = (legacy["max_downloading_count"] as number) ?? this.max_downloading_count
        this.default_player = (legacy["default_player"] as string) ?? this.default_player
        this.color_mode = (legacy["color_mode"] as number) ?? this.color_mode
        this.auto_sensor_rotate = (legacy["auto_sensor_rotate"] as boolean) ?? this.auto_sensor_rotate
        this.category_UI_type = (legacy["category_UI_type"] as number) ?? this.category_UI_type
        this.episodes_order = (legacy["episodes_order"] as 'asc' | 'desc') ?? this.episodes_order
        this.video_sources_order = (legacy["video_sources_order"] as SortType) ?? this.video_sources_order
        this.video_sources_group_filter =
          (legacy["video_sources_group_filter"] as string) ?? this.video_sources_group_filter
        this.video_sources_group_filter_manager =
          (legacy["video_sources_group_filter_manager"] as string) ?? this.video_sources_group_filter_manager
        this.video_source_import_overwrite =
          (legacy["video_source_import_overwrite"] as boolean) ?? this.video_source_import_overwrite
        Logger.i('Settings', '旧版配置迁移至 preferences 成功')
      }
      PersistentStorage.deleteProp("AppSettings")
    } catch (e) {
      Logger.e('fail', '旧版配置迁移', e)
    }
  }

  /**
   * 任一设置项变化时自动保存
   */
  @Monitor('auto_play_next_episode', 'key_homepage_source', 'auto_play_on_no_wifi',
    'auto_resume_download_on_wifi', 'need_blur', 'max_downloading_count', 'default_player',
    'color_mode', 'auto_sensor_rotate', 'category_UI_type', 'episodes_order',
    'video_sources_order', 'video_sources_group_filter', 'video_sources_group_filter_manager',
    'video_source_import_overwrite')
  public async save(): Promise<void> {
    if (this.isLoading) {
      return
    }
    try {
      const data: Record<string, Object> = {
        "auto_play_next_episode": this.auto_play_next_episode,
        "key_homepage_source": this.key_homepage_source,
        "auto_play_on_no_wifi": this.auto_play_on_no_wifi,
        "auto_resume_download_on_wifi": this.auto_resume_download_on_wifi,
        "need_blur": this.need_blur,
        "max_downloading_count": this.max_downloading_count,
        "default_player": this.default_player,
        "color_mode": this.color_mode,
        "auto_sensor_rotate": this.auto_sensor_rotate,
        "category_UI_type": this.category_UI_type,
        "episodes_order": this.episodes_order,
        "video_sources_order": this.video_sources_order,
        "video_sources_group_filter": this.video_sources_group_filter,
        "video_sources_group_filter_manager": this.video_sources_group_filter_manager,
        "video_source_import_overwrite": this.video_source_import_overwrite
      }
      await preferenceUtil.put(SETTINGS_KEY, JSON.stringify(data))
    } catch (e) {
      Logger.e('fail', '应用配置保存', e)
    }
  }

  /**
   * 清理数据 还原默认值
   */
  public async reset(): Promise<void> {
    this.isLoading = true
    this.auto_play_next_episode = true
    this.key_homepage_source = true
    this.auto_play_on_no_wifi = true
    this.auto_resume_download_on_wifi = false
    this.need_blur = false
    this.max_downloading_count = 3
    this.default_player = 'av'
    this.color_mode = ThemeColorMode.SYSTEM
    this.auto_sensor_rotate = false
    this.category_UI_type = 0
    this.episodes_order = 'asc'
    this.video_sources_order = SortType.CUSTOM
    this.video_sources_group_filter = '不分组'
    this.video_sources_group_filter_manager = ''
    this.video_source_import_overwrite = false
    this.isLoading = false
    await this.save()
  }
}

// 全局单例：所有页面/组件直接 import 使用
export const appSettings: AppConfigs = new AppConfigs()

/**
 * 兼容壳：仅保留 versionName 供 AppInfoPage 读取
 * （AppInfoPage 转 V2 后改用 AnimeState.appVersion，届时删除本类）
 */
export class AppSettings {

  static versionName = ""

  /**
   * 初始化应用版本名
   */
  static async initVersion(): Promise<void> {
    if (canIUse("SystemCapability.BundleManager.BundleFramework.Core")) {
      const packageInfo =
        await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
      AppSettings.versionName = packageInfo.versionName
      _AnimeState.appVersion = packageInfo.versionName
    } else {
      Logger.e('tips', '当前设备不支持包名查询 SystemCapability.BundleManager.BundleFramework.Core')
    }
  }

}
