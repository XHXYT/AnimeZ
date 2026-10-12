import { bundleManager } from "@kit.AbilityKit"
import { window } from "@kit.ArkUI"
import { BusinessError } from "@kit.BasicServicesKit"
import { SortType } from "../viewmodel/VideoSourcesViewModel"
import { preferenceUtil } from "../utils/PreferenceUtil"
import Logger from "../utils/Logger"
import { _AnimeState, AnimeState } from "./AnimeState"
import { VideoFit } from "../player/model/IPlayerManager"

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
   * 流量播放弹窗勾选「不再提醒」并取消后置 true：不再弹窗、不自动播放，手动点播放不受影响
   */
  @Trace metered_prompt_disabled: boolean = false
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
  @Trace default_player: string = 'mpv'
  /**
   * 颜色模式，默认为 跟随系统
   */
  @Trace color_mode: number = ThemeColorMode.SYSTEM
  /**
   * 自动全屏：手机/平板横屏（进入详情时已横屏/播放中转横屏）自动进入全屏
   */
  @Trace auto_fullscreen: boolean = false
  /**
   * 自由旋转：应用跟随传感器自由旋转（默认开启；关闭则锁定到关闭瞬间的屏幕方向）
   */
  @Trace free_rotate: boolean = true
  /**
   * 自由旋转关闭时锁定的窗口方向（关闭开关瞬间捕获：横屏锁横屏、竖屏锁竖屏）
   */
  @Trace locked_orientation: window.Orientation = window.Orientation.PORTRAIT
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
  /**
   * 应用外自动小窗播放：退出应用（回桌面/切其他应用）时系统自动拉起画中画小窗
   */
  @Trace pip_auto_outside: boolean = false
  /**
   * 应用内自动小窗播放：返回或页面内导航离开播放页时自动进入画中画小窗
   */
  @Trace pip_auto_inside: boolean = false
  /**
   * 小窗默认尺寸档位：1较小 2适中 3较大 4超大（默认适中），透传系统 defaultWindowSizeType
   */
  @Trace pip_default_size: number = 2
  /**
   * 弹幕开关
   */
  @Trace danmaku_enabled: boolean = true
  /**
   * 弹幕不透明度 0.25~1
   */
  @Trace danmaku_opacity: number = 1.0
  /**
   * 弹幕字体缩放 0.5~1.5
   */
  @Trace danmaku_font_scale: number = 0.9
  /**
   * 弹幕加粗显示
   */
  @Trace danmaku_bold: boolean = true
  /**
   * 弹幕滚动速度系数 1.0~2.0
   */
  @Trace danmaku_speed: number = 1.5
  /**
   * 弹幕显示区域占比 0.25~1
   */
  @Trace danmaku_area: number = 1.0
  /**
   * 弹幕屏蔽：屏蔽滚动弹幕
   */
  @Trace danmaku_block_scroll: boolean = false
  /**
   * 弹幕屏蔽：屏蔽固定弹幕（顶部/底部）
   */
  @Trace danmaku_block_fixed: boolean = false
  /**
   * 弹幕屏蔽：屏蔽彩色弹幕（非白色）
   */
  @Trace danmaku_block_color: boolean = false
  /**
   * 弹幕屏蔽：隐藏重复弹幕（相同文本短时间窗口内仅显示首条）
   */
  @Trace danmaku_hide_duplicate: boolean = false
  /**
   * 弹幕屏蔽：屏蔽词（逗号/空格分隔，命中即过滤）
   */
  @Trace danmaku_block_words: string = ''
  /**
   * 画面尺寸（VideoFit），默认为 适应
   */
  @Trace video_fit: VideoFit = VideoFit.Contain
  /**
   * 双击播放器右侧区域快进的秒数，默认 10 秒
   */
  @Trace double_tap_seek_forward: number = 10
  /**
   * 双击播放器左侧区域快退的秒数，默认 10 秒
   */
  @Trace double_tap_seek_rewind: number = 10
  /**
   * 播放器键盘快捷键覆盖（JSON Record<string, number>，空串=全部默认值）
   */
  @Trace player_shortcuts: string = ''
  /**
   * 搜索：精准搜索（勾选后仅保留标题与关键词完全一致的结果，否则模糊匹配）
   */
  @Trace search_precise: boolean = false
  /**
   * 搜索：结果屏蔽词（逗号/空格分隔，命中标题即过滤）
   */
  @Trace search_block_words: string = ''
  /**
   * 搜索：范围类型 all=全部源 group=按分组 source=按源
   */
  @Trace search_scope: string = 'all'
  /**
   * 搜索：选中的分组列表（JSON 数组字符串，与视频源分组管理同步）
   */
  @Trace search_scope_groups: string = ''
  /**
   * 搜索：选中的源 key 列表（JSON 数组字符串）
   */
  @Trace search_scope_sources: string = ''
  /**
   * 搜索：结果展示样式 card=卡片 list=列表 auto=自动（按源扩展字段多数判定）
   */
  @Trace search_result_style: string = 'auto'
  /**
   * 下载保存位置 sandbox=应用沙箱目录 public=公共下载目录(Download/包名/)
   */
  @Trace download_location: string = 'sandbox'
  /**
   * 下载区分剧集路线：开启后任务目录为 番剧名/线路名/，关闭后为 番剧名/；仅影响新任务
   */
  @Trace download_separate_route: boolean = true
  /**
   * 周表数据源 key（空=未选择，周表页显示空态引导）
   */
  @Trace schedule_source_key: string = ''
  /**
   * 后台继续播放：开启后应用切后台时申请音频长时任务，播放不中断
   */
  @Trace background_play: boolean = false
  /**
   * m3u8 广告拦截：播放前剔除播放列表中注入的广告分片（如 adjump 贴片广告）
   */
  @Trace m3u8_ad_filter: boolean = false

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
    this.metered_prompt_disabled = (json["metered_prompt_disabled"] as boolean) ?? this.metered_prompt_disabled
    this.auto_resume_download_on_wifi =
      (json["auto_resume_download_on_wifi"] as boolean) ?? this.auto_resume_download_on_wifi
    this.need_blur = (json["need_blur"] as boolean) ?? this.need_blur
    this.max_downloading_count = (json["max_downloading_count"] as number) ?? this.max_downloading_count
    const savedPlayer = (json["default_player"] as string) ?? this.default_player
    // VideoPlayer（Video 组件）后端已移除：存量选择迁移到 AVPlayer
    this.default_player = savedPlayer === 'video' ? 'av' : savedPlayer
    this.color_mode = (json["color_mode"] as number) ?? this.color_mode
    // 旧版单开关 auto_sensor_rotate 拆分为自动全屏/自由旋转两个开关：
    // 自动全屏沿用旧值迁移；自由旋转「默认开启」版本一次性重置（此前版本写入的 false 不保留），
    // 迁移后写入 free_rotate_default_on 标记，用户后续手动关闭可正常持久化
    const legacyRotate: boolean | undefined = json["auto_sensor_rotate"] as boolean
    this.auto_fullscreen = (json["auto_fullscreen"] as boolean) ?? legacyRotate ?? this.auto_fullscreen
    if ((json["free_rotate_default_on"] as boolean) === true) {
      this.free_rotate = (json["free_rotate"] as boolean) ?? true
    } else {
      this.free_rotate = true
    }
    this.locked_orientation = (json["locked_orientation"] as window.Orientation) ?? this.locked_orientation
    this.category_UI_type = (json["category_UI_type"] as number) ?? this.category_UI_type
    this.episodes_order = (json["episodes_order"] as 'asc' | 'desc') ?? this.episodes_order
    this.video_sources_order = (json["video_sources_order"] as SortType) ?? this.video_sources_order
    this.video_sources_group_filter = (json["video_sources_group_filter"] as string) ?? this.video_sources_group_filter
    this.video_sources_group_filter_manager =
      (json["video_sources_group_filter_manager"] as string) ?? this.video_sources_group_filter_manager
    this.video_source_import_overwrite =
      (json["video_source_import_overwrite"] as boolean) ?? this.video_source_import_overwrite
    // 旧版单开关 auto_pip_on_exit 拆分为应用内/应用外两个开关：无新键时沿用旧值迁移
    const legacyPip: boolean | undefined = json["auto_pip_on_exit"] as boolean
    this.pip_auto_inside = (json["pip_auto_inside"] as boolean) ?? legacyPip ?? this.pip_auto_inside
    this.pip_auto_outside = (json["pip_auto_outside"] as boolean) ?? legacyPip ?? this.pip_auto_outside
    this.pip_default_size = (json["pip_default_size"] as number) ?? this.pip_default_size
    this.danmaku_enabled = (json["danmaku_enabled"] as boolean) ?? this.danmaku_enabled
    this.danmaku_opacity = (json["danmaku_opacity"] as number) ?? this.danmaku_opacity
    this.danmaku_font_scale = (json["danmaku_font_scale"] as number) ?? this.danmaku_font_scale
    this.danmaku_bold = (json["danmaku_bold"] as boolean) ?? this.danmaku_bold
    this.danmaku_speed = (json["danmaku_speed"] as number) ?? this.danmaku_speed
    this.danmaku_area = (json["danmaku_area"] as number) ?? this.danmaku_area
    this.danmaku_block_scroll = (json["danmaku_block_scroll"] as boolean) ?? this.danmaku_block_scroll
    this.danmaku_block_fixed = (json["danmaku_block_fixed"] as boolean) ?? this.danmaku_block_fixed
    this.danmaku_block_color = (json["danmaku_block_color"] as boolean) ?? this.danmaku_block_color
    this.danmaku_hide_duplicate = (json["danmaku_hide_duplicate"] as boolean) ?? this.danmaku_hide_duplicate
    this.danmaku_block_words = (json["danmaku_block_words"] as string) ?? this.danmaku_block_words
    this.video_fit = (json["video_fit"] as VideoFit) ?? this.video_fit
    this.double_tap_seek_forward = (json["double_tap_seek_forward"] as number) ?? this.double_tap_seek_forward
    this.double_tap_seek_rewind = (json["double_tap_seek_rewind"] as number) ?? this.double_tap_seek_rewind
    this.player_shortcuts = (json["player_shortcuts"] as string) ?? this.player_shortcuts
    this.search_precise = (json["search_precise"] as boolean) ?? this.search_precise
    this.search_block_words = (json["search_block_words"] as string) ?? this.search_block_words
    this.search_scope = (json["search_scope"] as string) ?? this.search_scope
    this.search_scope_groups = (json["search_scope_groups"] as string) ?? this.search_scope_groups
    this.search_scope_sources = (json["search_scope_sources"] as string) ?? this.search_scope_sources
    this.search_result_style = (json["search_result_style"] as string) ?? this.search_result_style
    this.download_location = (json["download_location"] as string) ?? this.download_location
    this.download_separate_route = (json["download_separate_route"] as boolean) ?? this.download_separate_route
    this.schedule_source_key = (json["schedule_source_key"] as string) ?? this.schedule_source_key
    this.background_play = (json["background_play"] as boolean) ?? this.background_play
    this.m3u8_ad_filter = (json["m3u8_ad_filter"] as boolean) ?? this.m3u8_ad_filter
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
        // 旧版单开关 auto_sensor_rotate 拆分为自动全屏/自由旋转两个开关：
        // 自动全屏沿用旧值迁移；自由旋转「默认开启」版本一次性重置（此后手动关闭正常持久化）
        const legacyRotate: boolean | undefined = legacy["auto_sensor_rotate"] as boolean
        this.auto_fullscreen = (legacy["auto_fullscreen"] as boolean) ?? legacyRotate ?? this.auto_fullscreen
        if ((legacy["free_rotate_default_on"] as boolean) === true) {
          this.free_rotate = (legacy["free_rotate"] as boolean) ?? true
        } else {
          this.free_rotate = true
        }
        this.category_UI_type = (legacy["category_UI_type"] as number) ?? this.category_UI_type
        this.episodes_order = (legacy["episodes_order"] as 'asc' | 'desc') ?? this.episodes_order
        this.video_sources_order = (legacy["video_sources_order"] as SortType) ?? this.video_sources_order
        this.video_sources_group_filter =
          (legacy["video_sources_group_filter"] as string) ?? this.video_sources_group_filter
        this.video_sources_group_filter_manager =
          (legacy["video_sources_group_filter_manager"] as string) ?? this.video_sources_group_filter_manager
        this.video_source_import_overwrite =
          (legacy["video_source_import_overwrite"] as boolean) ?? this.video_source_import_overwrite
    const legacyPip: boolean | undefined = legacy["auto_pip_on_exit"] as boolean
    this.pip_auto_inside = (legacy["pip_auto_inside"] as boolean) ?? legacyPip ?? this.pip_auto_inside
    this.pip_auto_outside = (legacy["pip_auto_outside"] as boolean) ?? legacyPip ?? this.pip_auto_outside
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
  @Monitor('auto_play_next_episode', 'key_homepage_source', 'auto_play_on_no_wifi', 'metered_prompt_disabled',
    'auto_resume_download_on_wifi', 'need_blur', 'max_downloading_count', 'default_player',
    'color_mode', 'auto_fullscreen', 'free_rotate', 'locked_orientation', 'category_UI_type', 'episodes_order',
    'video_sources_order', 'video_sources_group_filter', 'video_sources_group_filter_manager',
    'video_source_import_overwrite', 'pip_auto_outside', 'pip_auto_inside', 'pip_default_size',
    'danmaku_enabled', 'danmaku_opacity', 'danmaku_font_scale', 'danmaku_bold', 'danmaku_speed', 'danmaku_area',
    'danmaku_block_scroll', 'danmaku_block_fixed', 'danmaku_block_color', 'danmaku_hide_duplicate',
    'danmaku_block_words',
    'video_fit', 'double_tap_seek_forward', 'double_tap_seek_rewind', 'player_shortcuts',
    'search_precise', 'search_block_words', 'search_scope', 'search_scope_groups', 'search_scope_sources',
    'search_result_style', 'download_location', 'download_separate_route', 'schedule_source_key',
    'background_play', 'm3u8_ad_filter')
  public async save(): Promise<void> {
    if (this.isLoading) {
      return
    }
    try {
      const data: Record<string, Object> = {
        "auto_play_next_episode": this.auto_play_next_episode,
        "key_homepage_source": this.key_homepage_source,
        "auto_play_on_no_wifi": this.auto_play_on_no_wifi,
        "metered_prompt_disabled": this.metered_prompt_disabled,
        "auto_resume_download_on_wifi": this.auto_resume_download_on_wifi,
        "need_blur": this.need_blur,
        "max_downloading_count": this.max_downloading_count,
        "default_player": this.default_player,
        "color_mode": this.color_mode,
        "auto_fullscreen": this.auto_fullscreen,
        "free_rotate": this.free_rotate,
        "locked_orientation": this.locked_orientation,
        "free_rotate_default_on": true,
        "category_UI_type": this.category_UI_type,
        "episodes_order": this.episodes_order,
        "video_sources_order": this.video_sources_order,
        "video_sources_group_filter": this.video_sources_group_filter,
        "video_sources_group_filter_manager": this.video_sources_group_filter_manager,
        "video_source_import_overwrite": this.video_source_import_overwrite,
        "pip_auto_outside": this.pip_auto_outside,
        "pip_auto_inside": this.pip_auto_inside,
        "pip_default_size": this.pip_default_size,
        "danmaku_enabled": this.danmaku_enabled,
        "danmaku_opacity": this.danmaku_opacity,
        "danmaku_font_scale": this.danmaku_font_scale,
        "danmaku_bold": this.danmaku_bold,
        "danmaku_speed": this.danmaku_speed,
        "danmaku_area": this.danmaku_area,
        "danmaku_block_scroll": this.danmaku_block_scroll,
        "danmaku_block_fixed": this.danmaku_block_fixed,
        "danmaku_block_color": this.danmaku_block_color,
        "danmaku_hide_duplicate": this.danmaku_hide_duplicate,
        "danmaku_block_words": this.danmaku_block_words,
        "video_fit": this.video_fit,
        "double_tap_seek_forward": this.double_tap_seek_forward,
        "double_tap_seek_rewind": this.double_tap_seek_rewind,
        "player_shortcuts": this.player_shortcuts,
        "search_precise": this.search_precise,
        "search_block_words": this.search_block_words,
        "search_scope": this.search_scope,
        "search_scope_groups": this.search_scope_groups,
        "search_scope_sources": this.search_scope_sources,
        "search_result_style": this.search_result_style,
        "download_location": this.download_location,
        "download_separate_route": this.download_separate_route,
        "schedule_source_key": this.schedule_source_key,
        "background_play": this.background_play,
        "m3u8_ad_filter": this.m3u8_ad_filter
      }
      await preferenceUtil.put(SETTINGS_KEY, JSON.stringify(data))
    } catch (e) {
      Logger.e('fail', '应用配置保存', e)
    }
  }

  /**
   * 按自由旋转设置应用窗口方向（全应用统一策略，任意页面即时调用）：
   * 开启（默认）→ 跟随传感器旋转；关闭 → 锁定到关闭开关时捕获的方向
   */
  public applyOrientation(): void {
    const windowClass = _AnimeState.window
    if (!windowClass) {
      return
    }
    const orientation: window.Orientation = this.free_rotate
      ? window.Orientation.AUTO_ROTATION_RESTRICTED
      : this.locked_orientation
    windowClass.setPreferredOrientation(orientation).catch((err: BusinessError) => {
      Logger.e('fail', `applyOrientation 设置窗口方向 code=${err.code}`, err)
    })
  }

  /**
   * 关闭自由旋转时调用：捕获当前窗口方向作为锁定方向（横屏锁横屏、竖屏锁竖屏），
   * 之后 applyOrientation / 重启后均按此方向锁定，直到重新开启自由旋转
   */
  public lockCurrentOrientation(): void {
    this.locked_orientation = AnimeState.windowWidth > AnimeState.windowHeight
      ? window.Orientation.AUTO_ROTATION_LANDSCAPE
      : window.Orientation.AUTO_ROTATION_PORTRAIT
  }

  /**
   * 清理数据 还原默认值
   */
  public async reset(): Promise<void> {
    this.isLoading = true
    this.auto_play_next_episode = true
    this.key_homepage_source = true
    this.auto_play_on_no_wifi = true
    this.metered_prompt_disabled = false
    this.auto_resume_download_on_wifi = false
    this.need_blur = false
    this.max_downloading_count = 3
    this.default_player = 'av'
    this.color_mode = ThemeColorMode.SYSTEM
    this.auto_fullscreen = false
    this.free_rotate = true
    this.locked_orientation = window.Orientation.PORTRAIT
    this.category_UI_type = 0
    this.episodes_order = 'asc'
    this.video_sources_order = SortType.CUSTOM
    this.video_sources_group_filter = '不分组'
    this.video_sources_group_filter_manager = ''
    this.video_source_import_overwrite = false
    this.pip_auto_outside = false
    this.pip_auto_inside = false
    this.pip_default_size = 2
    this.danmaku_enabled = true
    this.danmaku_opacity = 1.0
    this.danmaku_font_scale = 1.0
    this.danmaku_bold = true
    this.danmaku_speed = 1.0
    this.danmaku_area = 1.0
    this.danmaku_block_scroll = false
    this.danmaku_block_fixed = false
    this.danmaku_block_color = false
    this.danmaku_hide_duplicate = false
    this.danmaku_block_words = ''
    this.video_fit = VideoFit.Contain
    this.double_tap_seek_forward = 10
    this.double_tap_seek_rewind = 10
    this.player_shortcuts = ''
    this.search_precise = false
    this.search_block_words = ''
    this.search_scope = 'all'
    this.search_scope_groups = ''
    this.search_scope_sources = ''
    this.search_result_style = 'auto'
    this.download_location = 'sandbox'
    this.download_separate_route = false
    this.schedule_source_key = ''
    this.background_play = false
    this.m3u8_ad_filter = true
    this.isLoading = false
    await this.save()
  }
}

// 全局单例：所有页面/组件直接 import 使用
export const appSettings: AppConfigs = new AppConfigs()

/**
 * 兼容壳：仅保留 versionName 供 AppInfoPage 读取
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
