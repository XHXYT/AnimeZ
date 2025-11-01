
import TitleBar from '../components/TitleBar'
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SettingGroupType, SettingItem } from '../entity/SettingsData';
import { SettingRow } from '../components/SettingsItem';
import { ToastUtil } from '../utils/ToastUtils';
import { AppSettings } from '../entryability/Settings';

// 系统路由 - 应用信息
@Builder
export function AppInfoPageBuilder(name: string, param: Object) {
  AppInfoPage()
}

@Entry
@Component
struct AppInfoPage {

  @Consume('pageStack') pageStack: NavPathStack
  // 顶部避让高度
  @StorageProp('topRectHeight') topHeight: number = 0
  // 底部避让高度
  @StorageProp('bottomRectHeight') bottomHeight: number = 0
  @StorageLink('currentColorMode') currentMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT

  private appInfo: SettingItem<SettingGroupType>[] = [
    { title: '应用版本', settings_key: 'version', info: AppSettings.versionName, icon: $r('app.media.ic_version') },
    { title: '应用原始开发者', settings_key: 'raw_author', info: 'Z-P-J', icon: $rawfile('zpj.png'),
      onClick: () => {
        this.pageStack.pushPathByName("WebPage", "https://github.com/Z-P-J")
      }
    },
    { title: '开源仓库', settings_key: 'raw_repo', info: 'https://github.com/Z-P-J/AnimeZ', icon: $r('app.media.ic_github'),
      onClick: () => {
        this.pageStack.pushPathByName("WebPage", "https://github.com/Z-P-J/AnimeZ")
      }
    },
    { title: '应用维护者', settings_key: 'new_author', info: '小雅', icon: $rawfile('ya.png'),
      onClick: () => {
        this.pageStack.pushPathByName("WebPage", "https://github.com/XHXYT/")
      }
    },
    { title: '应用维护者', settings_key: 'new_author', info: 'SummerKaze', icon: $rawfile('summer_kaze.jfif'),
      onClick: () => {
        this.pageStack.pushPathByName("WebPage", "https://github.com/SummerKaze/")
      }
    },
    { title: '新开源仓库', settings_key: 'new_repo', info: 'https://github.com/XHXYT/AnimeZ', icon: $r('app.media.ic_github'),
      onClick: () => {
        this.pageStack.pushPathByName("WebPage", "https://github.com/XHXYT/AnimeZ")
      }
    },
    { title: '开源社区', settings_key: 'open_harmony', info: 'https://gitee.com/ohos-dev', icon: $r('app.media.ic_community'),
      onClick: () => {
        this.pageStack.pushPathByName("WebPage", "https://gitee.com/ohos-dev")
      }
    },
    { title: '鸿蒙交流群', settings_key: 'qq_group', info: '693903194', icon: $r('app.media.ic_qq'),
      onClick: () => {
        ToastUtil.showToast({message: '开发中'})
      }
    }
  ]

  build() {
    NavDestination() {
      TitleBar({title: '应用信息'})

      Scroll() {
        Column() {
          Image($r("app.media.Foreground"))
            .height(64)
            .width(64)
            .margin({top: 56})
            .borderRadius(100)
            .shadow({ radius: 12, color: this.currentMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#333333' : '#aaaaaa', offsetX: 6, offsetY: 6 })
          Text($r('app.string.EntryAbility_label'))
            .fontSize(18)
            .fontColor($r('app.color.color_text_major'))
            .fontWeight(500)
            .padding({ top: 12 })
          Text($r('app.string.module_desc'))
            .fontSize(14)
            .fontColor($r('app.color.color_text_minor'))
            .margin({ top: 8, bottom: 56 })
          ForEach(
            this.appInfo,
            (setting: SettingItem<SettingGroupType>, index) => {
              Column() {
                SettingRow({
                  icons: setting.icon,
                  title: setting.title,
                  subtitle: setting.info,
                  onCheck: () => {
                    if (setting.onClick) {
                      setting.onClick(
                        setting,
                        () => {},
                      )
                    }
                  }
                })
              }
              .backgroundColor($r('app.color.background_color'))
              .borderRadius({
                topLeft: index === 0 ? 16 : 0,
                topRight: index === 0 ? 16: 0,
                bottomLeft: index === this.appInfo.length - 1 ? 16: 0,
                bottomRight: index === this.appInfo.length - 1 ? 16: 0
              })
            },
            // 唯一键生成
            (setting: SettingItem<SettingGroupType>) => setting.settings_key
          )
        }
        .clip(true)
        .padding(16)
        .width('100%')
        .constraintSize({ minHeight: '100%' })
      }
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)

    }
    .padding({top: this.topHeight - 20, bottom: this.bottomHeight - 20})
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
  }

}