
import TitleBar from '../components/TitleBar'
import { CustomListItem } from '../components/CustomListItem'
import { CustomItemInfo, ItemActionType, ItemGroupData, MenuOption, makeItemGroups } from '../entity/CusItemInfo'
import { ColorModeManager } from '../utils/ColorModeManager'
import { common } from '@kit.AbilityKit'
import { appSettings } from '../entryability/Settings'
import { dataSourceManager } from '../api/DataSourceManager'
import Logger from '../utils/Logger'
import { SOURCE_CHANGED_EVENT } from '../utils/EventBus'
import { AnimeState } from '../entryability/AnimeState'
import { PiPManager } from '../player/PiPManager'
import { DownloadDirHelper, DownloadLocationType } from '../utils/DownloadDirHelper'
import { ToastUtil } from '../utils/ToastUtils'

// 系统路由
@Builder
export function SettingsPageBuilder(name: string, param: Object) {
  SettingsPage()
}

@ComponentV2
struct SettingsPage {

  private context: common.UIAbilityContext = this.getUIContext().getHostContext()! as common.UIAbilityContext

  /** 列表版本号：页面重新可见时递增，作为 ForEach key 前缀强制重建列表以刷新选中态 */
  @Local private listVersion: number = 0

  /** 分组结果（@Local 持有，aboutToAppear / onShown 时重建） */
  @Local private groups: ItemGroupData[] = []

  aboutToAppear(): void {
    this.groups = makeItemGroups(this.itemList)
  }

  /**
   * 设置项数据（getter 每次求值，读 appSettings 最新值保证选中态同步）
   */
  private get itemList(): CustomItemInfo[] {
    const sourceViews: ResourceStr[] = dataSourceManager.getHomepageSourceTitles()
    const sourceValues: string[] = dataSourceManager.getHomepageSourceKeys()
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
          new MenuOption('sandbox', '应用沙箱目录'),
          new MenuOption('public', '公共下载目录')
        ],
        onChange: (value) => {
          if (value === DownloadLocationType.PUBLIC) {
            if (DownloadDirHelper.ensurePublicDir(this.context)) {
              appSettings.download_location = DownloadLocationType.PUBLIC
              ToastUtil.showToast({ message: '新任务将下载到公共下载目录(Download/应用包名)' })
            } else {
              ToastUtil.showToast({ message: '公共下载目录不可用，仍使用应用沙箱目录' })
            }
          } else {
            appSettings.download_location = DownloadLocationType.SANDBOX
            ToastUtil.showToast({ message: '新任务将下载到应用沙箱目录' })
          }
          // 刷新列表选中态（公共目录不可用时回显沙箱）
          this.listVersion++
          this.groups = makeItemGroups(this.itemList)
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
          new MenuOption('video', 'VideoPlayer'),
        ],
        onChange: (value) => {
          appSettings.default_player = value as string
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
        }
      }),
      new CustomItemInfo({
        id: 'danmaku_opacity',
        title: '弹幕不透明度',
        type: ItemActionType.MENU,
        value: String(appSettings.danmaku_opacity),
        menuOptions: [
          new MenuOption('0.25', '25%'),
          new MenuOption('0.5', '50%'),
          new MenuOption('0.75', '75%'),
          new MenuOption('1', '100%')
        ],
        onChange: (value) => {
          appSettings.danmaku_opacity = Number(value)
        }
      }),
      new CustomItemInfo({
        id: 'danmaku_font_scale',
        title: '弹幕字体大小',
        type: ItemActionType.MENU,
        value: String(appSettings.danmaku_font_scale),
        menuOptions: [
          new MenuOption('0.5', '50%'),
          new MenuOption('0.75', '75%'),
          new MenuOption('1', '100%'),
          new MenuOption('1.25', '125%'),
          new MenuOption('1.5', '150%')
        ],
        onChange: (value) => {
          appSettings.danmaku_font_scale = Number(value)
        }
      }),
      new CustomItemInfo({
        id: 'danmaku_speed',
        title: '弹幕滚动速度',
        type: ItemActionType.MENU,
        value: String(appSettings.danmaku_speed),
        menuOptions: [
          new MenuOption('0.5', '0.5x'),
          new MenuOption('1', '1x'),
          new MenuOption('1.5', '1.5x'),
          new MenuOption('2', '2x')
        ],
        onChange: (value) => {
          appSettings.danmaku_speed = Number(value)
        }
      }),
      new CustomItemInfo({
        id: 'danmaku_area',
        title: '弹幕显示区域',
        type: ItemActionType.MENU,
        value: String(appSettings.danmaku_area),
        menuOptions: [
          new MenuOption('1', '全部'),
          new MenuOption('0.75', '3/4'),
          new MenuOption('0.5', '半屏'),
          new MenuOption('0.25', '1/4')
        ],
        onChange: (value) => {
          appSettings.danmaku_area = Number(value)
        }
      }),

      // 更多组
      new CustomItemInfo({ id: 'group_more', title: '更多', type: ItemActionType.GROUP }),
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
      })
    ].filter((item: CustomItemInfo) => {
      // 小窗播放仅支持部分播放器后端：选了不支持的后端时隐藏自动小窗开关
      if (item.id === 'auto_pip_on_exit') {
        return PiPManager.isPlayerSupported(appSettings.default_player)
      }
      return true
    })
  }

  build() {
    NavDestination() {
      // 标题
      TitleBar({ title: '设置' })
      // 内容
      Column() {
        Scroll() {
          Column() {
            ForEach(
              this.groups,
              (group: ItemGroupData, index) => {
                Column() {
                  if (group.group) {
                    this.GroupHeader(group.group.title)
                  }
                  // 设置项
                  ForEach(
                    group.items,
                    (item: CustomItemInfo) => {
                      CustomListItem({
                        item: item,
                        itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
                      })
                    },
                    (item: CustomItemInfo) => item.id
                  )
                }
                .backgroundColor($r('app.color.background_color'))
                .borderRadius(16)

                if (index < this.groups.length - 1) {
                  Blank().height(16)
                }
              },
              // 唯一键生成（带版本前缀：listVersion 变化时强制重建所有分组以刷新选中态）
              (group: ItemGroupData) => `${this.listVersion}_${group.group?.id ?? String(group.items.length)}`
            )
          }
          .padding({ left: 16, right: 16, top: 4, bottom: 16 })
          .width('100%')
          .constraintSize({
            minHeight: '100%'
          })
        }.scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }.layoutWeight(1)

      Text('本应用仅供学习交流！')
        .fontSize(16)
        .fontColor($r('app.color.color_text_major'))
        .padding(8)

    }
    .padding({top: AnimeState.topRectHeight - 20, bottom: AnimeState.bottomRectHeight - 20})
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .onShown(() => {
      // 页面重新可见时重建列表，同步在视频源页可能被修改的首页源选中态
      this.listVersion++
      this.groups = makeItemGroups(this.itemList)
    })
    .width('100%')
    .height('100%')
  }

  /**
   * 分组标题（保持原色条视觉）
   */
  @Builder
  GroupHeader(title: ResourceStr) {
    Row() {
      Row()
        .backgroundColor($r('app.color.primary_color'))
        .height(14)
        .width(6)
        .margin({ right: 2 })
        .borderRadius(4)
      Text(title)
        .fontColor($r('app.color.color_text_major'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
    }
    .padding({ left: 16, top: 16, right: 16, bottom: 8 })
    .width('100%')
  }

}
