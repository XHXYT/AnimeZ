import { SettingsGroupList } from './SettingsGroupList'
import { CustomItemInfo, ItemActionType, MenuOption } from '../entity/CusItemInfo'
import { ColorModeManager } from '../utils/ColorModeManager'
import { common } from '@kit.AbilityKit'
import { appSettings } from '../entryability/Settings'
import { dataSourceManager } from '../api/DataSourceManager'
import Logger from '../utils/Logger'
import { SOURCE_CHANGED_EVENT, SCHEDULE_SOURCE_CHANGED_EVENT } from '../utils/EventBus'
import { _AnimeState, AnimeState } from '../entryability/AnimeState'
import { PiPManager } from '../player/PiPManager'
import { DownloadDirHelper, DownloadLocationType } from '../utils/DownloadDirHelper'
import { ToastUtil } from '../utils/ToastUtils'

/** "更多"组条目 id（窗口模式下整组并入"我的"页底部更多卡片） */
const MORE_GROUP_IDS: string[] = ['app_info', 'author_info', 'third_party_services']

/**
 * "更多"组条目（应用信息/关于作者/三方服务）：
 * 设置列表（SettingsContent）与"我的"页更多卡片（MoreContainer，窗口模式）共用。
 */
export function buildMoreGroupItems(): CustomItemInfo[] {
  return [
    new CustomItemInfo({
      id: 'app_info',
      title: '应用信息',
      subtitle: $r('app.string.module_desc'),
      type: ItemActionType.ROUTER,
      onChange: () => {
        AnimeState.pageStack.pushPathByName("AppInfoPage", '')
      }
    }),
    new CustomItemInfo({
      id: 'author_info',
      title: '关于作者',
      subtitle: '这人很懒，什么都没有写！',
      type: ItemActionType.ROUTER,
      onChange: () => {
        AnimeState.pageStack.pushPathByName("AboutMePage", '')
      }
    }),
    new CustomItemInfo({
      id: 'third_party_services',
      title: '三方服务',
      subtitle: '开源三方库列表',
      type: ItemActionType.ROUTER,
      onChange: () => {
        AnimeState.pageStack.pushPathByName("ThirdPartyServicesPage", '')
      }
    })
  ]
}

/**
 * 通用设置列表内容（设置页与"我的"页窗口模式内嵌共用）：
 * 含全部设置分组数据与选中态刷新机制，宿主只需决定容器与内边距。
 */
@ComponentV2
export struct SettingsContent {

  @Local animeState: _AnimeState = AnimeState

  private context: common.UIAbilityContext = this.getUIContext().getHostContext()! as common.UIAbilityContext

  /** 列表版本号：递增时作为分组 key 前缀强制重建，刷新选中态 */
  @Local private listVersion: number = 0

  /** 列表内容边距（内嵌宿主已有边距时可传 0 覆盖） */
  @Param contentPadding: Padding = { left: 16, right: 16, top: 4, bottom: 16 }

  /** 二级页面（视频源等）显隐切换时重建列表，同步可能被修改的选中态 */
  @Monitor('animeState.onShow')
  onSubPageVisibilityChange() {
    this.listVersion++
  }

  /**
   * 设置项数据（getter 每次求值，读 appSettings 最新值保证选中态同步）
   */
  private get itemList(): CustomItemInfo[] {
    const sourceViews: ResourceStr[] = dataSourceManager.getHomepageSourceTitles()
    const sourceValues: string[] = dataSourceManager.getHomepageSourceKeys()
    const scheduleKeys: string[] = dataSourceManager.getScheduleSourceKeys()
    const scheduleTitles: string[] = scheduleKeys.map((key: string) => dataSourceManager.getSourceTitle(key) || key)
    return [
      // 界面组
      new CustomItemInfo({ id: 'group_appearance', title: '界面', type: ItemActionType.GROUP }),
      new CustomItemInfo({
        id: 'color_mode',
        title: '颜色主题',
        type: ItemActionType.MENU,
        value: appSettings.color_mode.toString(),
        menuOptions: [
          new MenuOption('0', '自动'),
          new MenuOption('1', '白天'),
          new MenuOption('2', '夜晚')
        ],
        onChange: (value) => {
          appSettings.color_mode = Number(value)
          ColorModeManager.switchColorMode(this.context, appSettings.color_mode)
        }
      }),

      // 数据组
      new CustomItemInfo({ id: 'group_source', title: '数据', type: ItemActionType.GROUP }),
      new CustomItemInfo({
        id: 'video_sources',
        title: '视频源',
        type: ItemActionType.ROUTER,
        onChange: () => {
          AnimeState.pageStack.pushPathByName("VideoSources", '', true)
        }
      }),
      new CustomItemInfo({
        id: 'homepage_source',
        title: '首页数据源',
        type: ItemActionType.MENU,
        value: dataSourceManager.getKey(),
        menuOptions: sourceValues.map((key, index) => new MenuOption(key, sourceViews[index])),
        onChange: (value) => {
          if (typeof value === 'string') {
            // 设置主页数据源
            dataSourceManager.setDataSourceAsDefault(value).then(() => {
              SOURCE_CHANGED_EVENT.emit()
              console.log('主页数据源设置成功' + value)
            }).catch((err: Error) => {
              Logger.e('fail', '设置主页数据源', err)
            })
          }
        }
      }),
      new CustomItemInfo({
        id: 'schedule_source',
        title: '周表数据源',
        subtitle: '周表页的数据来源，需源配置了周表规则',
        type: ItemActionType.MENU,
        value: scheduleKeys.includes(appSettings.schedule_source_key) ? appSettings.schedule_source_key : '',
        menuOptions: scheduleKeys.length > 0
          ? scheduleKeys.map((key, index) => new MenuOption(key, scheduleTitles[index]))
          : [new MenuOption('', '暂无可用源')],
        onChange: (value) => {
          if (typeof value === 'string') {
            // 设置周表数据源（空串=暂无可用源占位，不改变选择）
            if (value !== '') {
              appSettings.schedule_source_key = value
              SCHEDULE_SOURCE_CHANGED_EVENT.emit()
            }
          }
        }
      }),
      new CustomItemInfo({
        id: 'video_source_import_overwrite',
        title: '视频源覆盖更新',
        subtitle: '导入配置自动覆盖更新',
        type: ItemActionType.TOGGLE,
        value: appSettings.video_source_import_overwrite,
        onChange: (value) => {
          appSettings.video_source_import_overwrite = value as boolean
        }
      }),
      new CustomItemInfo({
        id: 'download_location',
        title: '下载保存位置',
        subtitle: '新任务保存位置，不影响已有任务',
        type: ItemActionType.MENU,
        value: appSettings.download_location,
        menuOptions: [
          new MenuOption('sandbox', '应用沙箱'),
          new MenuOption('public', '公共下载')
        ],
        onChange: (value) => {
          if (value === DownloadLocationType.PUBLIC) {
            // 首次需经 DOWNLOAD 模式静默授权，异步确认后再生效
            DownloadDirHelper.ensurePublicDir(this.context).then((dir: string) => {
              if (dir) {
                appSettings.download_location = DownloadLocationType.PUBLIC
                ToastUtil.showToast({ message: '新任务将下载到公共下载目录(Download/应用包名)' })
              } else {
                ToastUtil.showToast({ message: '公共下载目录不可用，仍使用应用沙箱目录' })
              }
              // 刷新列表选中态（公共目录不可用时回显沙箱）
              this.listVersion++
            })
          } else {
            appSettings.download_location = DownloadLocationType.SANDBOX
            ToastUtil.showToast({ message: '新任务将下载到应用沙箱目录' })
          }
        }
      }),
      new CustomItemInfo({
        id: 'download_separate_route',
        title: '下载区分剧集路线',
        subtitle: '开启后新任务按 番剧/线路 分层存放，关闭则直接存放在番剧文件夹',
        type: ItemActionType.TOGGLE,
        value: appSettings.download_separate_route,
        onChange: (value) => {
          appSettings.download_separate_route = value as boolean
        }
      }),

      // 播放组
      new CustomItemInfo({ id: 'group_play', title: '播放', type: ItemActionType.GROUP }),
      new CustomItemInfo({
        id: 'player_control',
        title: '播放控制',
        subtitle: '快捷手势与键盘快捷键',
        type: ItemActionType.ROUTER,
        onChange: () => {
          AnimeState.pageStack.pushPathByName("PlayerControlSettingsPage", '')
        }
      }),
      new CustomItemInfo({
        id: 'default_player',
        title: '默认播放器',
        type: ItemActionType.MENU,
        value: appSettings.default_player,
        menuOptions: [
          new MenuOption('av', 'AVPlayer'),
          new MenuOption('mpv', 'MPVPlayer'),
          new MenuOption('ijk', 'IjkPlayer'),
          new MenuOption('red', 'RedPlayer(仅本地)'),
        ],
        onChange: (value) => {
          appSettings.default_player = value as string
        }
      }),
      new CustomItemInfo({
        id: 'm3u8_ad_filter',
        title: 'm3u8 广告拦截',
        subtitle: '播放前自动剔除播放列表中注入的广告分片',
        type: ItemActionType.TOGGLE,
        value: appSettings.m3u8_ad_filter,
        onChange: (value) => {
          appSettings.m3u8_ad_filter = value as boolean
        }
      }),
      new CustomItemInfo({
        id: 'episodes_order',
        title: '剧集列表排序',
        type: ItemActionType.MENU,
        value: appSettings.episodes_order as string,
        menuOptions: [
          new MenuOption('asc', '正序'),
          new MenuOption('desc', '倒序')
        ],
        onChange: (value) => {
          appSettings.episodes_order = value as "asc" | "desc"
        }
      }),
      new CustomItemInfo({
        id: 'auto_sensor_rotate',
        title: '启用自动旋屏',
        subtitle: '跟随传感器自动切换半屏/全屏播放',
        type: ItemActionType.TOGGLE,
        value: appSettings.auto_sensor_rotate,
        onChange: (value) => {
          appSettings.auto_sensor_rotate = value as boolean
        }
      }),
      new CustomItemInfo({
        id: 'auto_play_next_episode',
        title: '自动播放下一集',
        subtitle: '视频结束后自动播放下一集',
        type: ItemActionType.TOGGLE,
        value: appSettings.auto_play_next_episode,
        onChange: (value) => {
          appSettings.auto_play_next_episode = value as boolean
        }
      }),
      new CustomItemInfo({
        id: 'auto_play_on_no_wifi',
        title: '非Wifi下自动播放',
        subtitle: '非Wifi环境下不再提醒，自动播放视频',
        type: ItemActionType.TOGGLE,
        value: appSettings.auto_play_on_no_wifi,
        onChange: (value) => {
          appSettings.auto_play_on_no_wifi = value as boolean
        }
      }),
      new CustomItemInfo({
        id: 'auto_pip_on_exit',
        title: '退出播放页自动小窗',
        subtitle: '返回、导航、后台时自动进入画中画小窗',
        type: ItemActionType.TOGGLE,
        value: appSettings.auto_pip_on_exit,
        onChange: (value) => {
          appSettings.auto_pip_on_exit = value as boolean
        }
      }),
      new CustomItemInfo({
        id: 'danmaku_enabled',
        title: '弹幕开关',
        subtitle: '通过弹弹play按标题自动匹配',
        type: ItemActionType.TOGGLE,
        value: appSettings.danmaku_enabled,
        onChange: (value) => {
          appSettings.danmaku_enabled = value as boolean
          // 联动弹幕配置入口可用态：重建列表刷新其置灰状态
          this.listVersion++
        }
      }),
      new CustomItemInfo({
        id: 'danmaku_config',
        title: '弹幕配置',
        subtitle: '不透明度、字体大小、滚动速度与显示区域',
        type: ItemActionType.ROUTER,
        enabled: appSettings.danmaku_enabled,
        onChange: () => {
          AnimeState.pageStack.pushPathByName("DanmakuSettingsPage", '')
        }
      }),

      // 更多组
      new CustomItemInfo({ id: 'group_more', title: '更多', type: ItemActionType.GROUP })
    ].concat(buildMoreGroupItems())
      .filter((item: CustomItemInfo) => {
        // 小窗播放仅支持部分播放器后端：选了不支持的后端时隐藏自动小窗开关
        if (item.id === 'auto_pip_on_exit') {
          return PiPManager.isPlayerSupported(appSettings.default_player)
        }
        // 窗口模式下"更多"组并入"我的"页底部更多卡片，设置列表内不再显示
        if (AnimeState.windowMode && (item.id === 'group_more' || MORE_GROUP_IDS.includes(item.id))) {
          return false
        }
        return true
      })
  }

  build() {
    SettingsGroupList({ items: this.itemList, version: this.listVersion, contentPadding: this.contentPadding })
  }
}
