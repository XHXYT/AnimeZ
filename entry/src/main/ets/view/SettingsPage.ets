
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

// 系统路由
@Builder
export function SettingsPageBuilder(name: string, param: Object) {
  SettingsPage()
}

@ComponentV2
struct SettingsPage {

  private context: common.UIAbilityContext = this.getUIContext().getHostContext()! as common.UIAbilityContext

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

      // 播放组
      new CustomItemInfo({ id: 'group_play', title: '播放', type: ItemActionType.GROUP }),
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
    ]
  }

  /** 分组结果（供 ForEach 与间距判断复用） */
  private get groups(): ItemGroupData[] {
    return makeItemGroups(this.itemList)
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
              // 唯一键生成
              (group: ItemGroupData) => group.group?.id ?? String(group.items.length)
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
