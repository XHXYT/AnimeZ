
import { SettingGroup, SettingGroupType, SettingItem } from '../entity/SettingsData';
import { SettingRow } from './SettingsItem';

@Preview
@Component
export struct More {
  @Consume('pageStack') pageStack: NavPathStack
  /**
   * 更多列表数据
   */
  @Provide moreItemData: SettingGroup<boolean | string | number>[] = [
    {
      title: '更多',
      key: 'more',
      settings: [
        {
          title: '设置',
          settings_key: 'settings',
          icon: $r('app.media.gearshape'),
          onClick: (item, callback) => {
            this.pageStack.pushPathByName("SettingsPage", '')
            callback?.()
          }
        },
        {
          title: '免责声明',
          settings_key: 'disclaimer',
          icon: $r('app.media.ic_gitee'),
          onClick: (item, callback) => {
            this.pageStack.pushPathByName("WebPage", "disclaimer.html")
            callback?.()
          }
        },
        {
          title: '原开源仓库',
          settings_key: 'raw',
          info: 'https://github.com/Z-P-J/AnimeZ',
          icon: $r('app.media.ic_github'),
          onClick: (item, callback) => {
            this.pageStack.pushPathByName("WebPage", "https://github.com/Z-P-J/AnimeZ")
            callback?.()
          }
        },
        {
          title: '新开源仓库',
          settings_key: 'new',
          info: 'https://github.com/XHXYT/AnimeZ',
          icon: $r('app.media.ic_github'),
          onClick: (item, callback) => {
            this.pageStack.pushPathByName("WebPage", "https://github.com/XHXYT/AnimeZ")
            callback?.()
          }
        }
      ]
    }
  ];

  build() {
    Column() {
      ForEach(
        this.moreItemData,
        (group: SettingGroup<SettingGroupType>, index) => {
          Column() {
            if (group.title) {
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
                Blank()
              }
              .padding({ left: 16, top: 16, right: 16, bottom: 8 })
              .width('100%')
            }

            ForEach(
              group.settings,
              (setting: SettingItem<SettingGroupType>) => {
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
              },
              (setting: SettingItem<SettingGroupType>) => setting.title
            )
          }
          .backgroundColor($r('app.color.background_color'))
          .borderRadius(16)

          if (index < this.moreItemData.length - 1) {
            Blank().height(16)
          }
        },
        // 唯一键生成
        (group: SettingGroup<SettingGroupType>) => {
          return group.title || String(group.settings.length)
        }
      )
    }
    .margin({ left: 16, right: 16 })
  }
}

