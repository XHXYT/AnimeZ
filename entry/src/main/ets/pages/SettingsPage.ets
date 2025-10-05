
import TitleBar from '../components/TitleBar'
import { MenuItem, Preference, SettingGroup, SettingGroupType, SettingItem } from '../entity/SettingsData'
import { MenuSettingRow, SettingRow, ToggleSettingRow } from '../components/SettingsItem'
import { ColorModeManager } from '../utils/ColorModeManager'
import { common } from '@kit.AbilityKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { AppConfigs } from '../entryability/Settings'
import { dataSourceManager } from '../api/DataSourceManager'
import Logger from '../utils/Logger'
import { SOURCE_CHANGED_EVENT } from '../utils/EventBus'

// 系统路由
@Builder
export function SettingsPageBuilder(name: string, param: Object) {
  SettingsPage()
}

@Component
struct SettingsPage {

  @Consume('pageStack') pageStack: NavPathStack
  // 顶部避让高度
  @StorageProp('topRectHeight') topHeight: number = 0
  // 底部避让高度
  @StorageProp('bottomRectHeight') bottomHeight: number = 0
  // 应用设置
  @StorageLink('AppSettings') appSettings: AppConfigs = new AppConfigs()
  private context: common.UIAbilityContext = this.getUIContext().getHostContext()! as common.UIAbilityContext

  build() {
    NavDestination() {
      // 标题
      TitleBar({ title: '设置' })
      // 内容
      Column() {
        Scroll() {
          Column() {
            ForEach(
              this.getSettings(),
              (group: SettingGroup<SettingGroupType>, index) => {
                Column() {
                  if (group.title) {
                    // 标题行
                    Row() {
                      Row()
                        .backgroundColor($r('app.color.primary_color'))
                        .height(14)
                        .width(6)
                        .margin({ right: 2 })
                        .borderRadius(4)
                      Text(group.title)
                        .fontColor($r('app.color.color_text_major'))
                        .fontSize(16)
                        .fontWeight(FontWeight.Bold)
                    }
                    .padding({ left: 16, top: 16, right: 16, bottom: 8 })
                    .width('100%')
                  }
                  // 设置项
                  ForEach(
                    group.settings,
                    (setting: SettingItem<SettingGroupType>) => {
                      if (setting.preference?.type === 'switch') {
                        ToggleSettingRow({
                          isOn: setting.preference.defaultValue as boolean,
                          title: setting.title,
                          subtitle: setting.info,
                          preference: setting.preference as Preference<boolean>
                        })
                      } else if (setting.preference?.type === 'radio') {

                      } else if (setting.preference?.type === 'menu') {
                        MenuSettingRow({
                          selected: setting.preference.defaultValue as string,
                          title: setting.title,
                          icons: setting.icon,
                          info: setting.info as string,
                          preference: setting.preference as Preference<string>
                        })
                      } else {
                        SettingRow({
                          icons: setting.icon,
                          title: setting.title,
                          subtitle: setting.info,
                          onCheck: () => {
                            if (setting.onClick) {
                              setting.onClick(
                                setting,
                                () => { },
                              )
                            }
                          }
                        })
                      }
                    },
                    (setting: SettingItem<SettingGroupType>) => setting.settings_key
                  )
                }
                .backgroundColor($r('app.color.background_color'))
                .borderRadius(16)

                if (index < this.getSettings().length - 1) {
                  Blank().height(16)
                }
              },
              // 唯一键生成
              (group: SettingGroup<SettingGroupType>) => {
                return group.key || String(group.settings.length)
              }
            )
          }
          .padding(16)
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
    .padding({top: this.topHeight - 20, bottom: this.bottomHeight - 20})
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
  }

  getSettings(): SettingGroup<SettingGroupType>[] {
    return [
      {
        title: '界面',
        key: 'appearance',
        settings: [
          { title: '颜色主题', info: '自动',
            settings_key: 'color_mode',
            preference: {
              type: 'menu',
              defaultValue: this.appSettings.color_mode.toString(),
              menu: [
                {
                  view: '自动',
                  value: '0'
                },
                {
                  view: '白天',
                  value: '1'
                },
                {
                  view: '夜晚',
                  value: '2'
                }
              ],
              onValueChange: (value) => {
                this.appSettings.color_mode = Number(value)
                ColorModeManager.switchColorMode(this.context, this.appSettings.color_mode)
              }
            }
          }
        ]
      },
      {
        title: '数据',
        key: 'source',
        settings: [
          { title: '首页数据源',
            settings_key: 'homepage_source',
            preference: {
              type: 'menu',
              defaultValue: dataSourceManager.getKey(),
              menu: this.getSourcesMenu(dataSourceManager.getTotalSourceTitle(), dataSourceManager.getTotalKey()),
              onValueChange: (value) => {
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
            }
          },
        ]
      },
      {
        title: '播放',
        key: 'play',
        settings: [
          { title: '默认播放器', info: 'AVPlayer',
            settings_key: 'default_player',
            preference: {
              type: 'menu',
              defaultValue: this.appSettings.default_player,
              menu: [
                {
                  view: 'VideoPlayer',
                  value: 'video'
                },
                {
                  view: 'AVPlayer',
                  value: 'av'
                },
                {
                  view: 'RedPlayer',
                  value: 'red'
                },
                {
                  view: 'IjkPlayer',
                  value: 'ijk'
                }
              ],
              onValueChange: (value) => {
                this.appSettings.default_player = value as string
              }
            }
          },
          {
            title: '启用自动旋屏',
            info: '跟随传感器自动切换半屏/全屏播放',
            settings_key: 'auto_sensor_rotate',
            preference: {
              type: 'switch',
              menu: [],
              defaultValue: this.appSettings.auto_sensor_rotate
            }
          },
          {
            title: '自动播放下一集',
            info: '视频结束后自动播放下一集',
            settings_key: 'auto_play_next_episode',
            preference: {
              type: 'switch',
              menu: [],
              defaultValue: this.appSettings.auto_play_next_episode
            }
          },
          {
            title: '非Wifi下自动播放',
            info: '非Wifi环境下不再提醒，自动播放视频',
            settings_key: 'auto_play_on_no_wifi',
            preference: {
              type: 'switch',
              menu: [],
              defaultValue: this.appSettings.auto_play_on_no_wifi
            }
          }
        ]
      },
      /* {
         title: '下载',
         settings: [
           {
             title: '自动恢复下载',
             info: 'Wifi环境下软件启动后自动恢复未完成的下载任务',
             preference: {
               key: Settings.KEY_AUTO_RESUME_DOWNLOAD_ON_WIFI,
               type: 'switch',
               defaultValue: false
             }
           },
           { title: '最大同时下载任务数', info: '' + Settings.getMaxDownloadingCount(),
             onClick: (item, callback) => {
               let controller = new CustomDialogController({
                 builder: SliderDialog({
                   select: (value) => {
                     if (callback) {
                       item.info = '' + value
                       callback()
                     }
                   },
                   onClose: () => {
                     controller.close()
                   }
                 }),
                 cancel: () => {
                   console.log("cancel")
                 },
                 autoCancel: true,
                 customStyle: true
               });
               controller.open()
             }
           }
         ]
       },*/
      {
        title: '更多',
        key:'more',
        settings: [
          /* { TODO 检查更新
             title: '检查更新',
             info: '1.0.1',
             settings_key: 'update',
             iconBlendColor: Color.Black,
             onClick: () => {

             }
           },*/
          {
            title: '应用信息',
            info: $r('app.string.module_desc'),
            settings_key: 'app_info',
            onClick: () => {
              this.pageStack.pushPathByName("AppInfoPage", '')
            }
          },
          {
            title: '关于作者',
            info: '这人很懒，什么都没有写！',
            settings_key: 'author_info',
            onClick: () => {
              this.pageStack.pushPathByName("AboutMePage", '')
            }
          }
        ]
      }
    ]
  }

  /**
   * 获取Source菜单
   * @param views name 数组
   * @param values key 数组
   * @returns 合并后的 MenuItem 数组
   */
  getSourcesMenu(views: ResourceStr[], values: string[]): MenuItem[] {
    // 使用 map 遍历 views 数组，同时获取 index
    return views.map((view, index) => {
      const value = values[index];
      return { view: view, value: value } as MenuItem
    })
  }

}