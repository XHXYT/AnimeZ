import router from '@ohos.router'
import promptAction from '@ohos.promptAction'
import TitleBar from '../components/TitleBar'
import { OPTIONS_TRANSITION_POP, OPTIONS_TRANSITION_PUSH } from '../utils/TransitionHelper';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SettingGroup, SettingGroupType, SettingItem } from '../components/common/Constants';
import { SettingRow } from '../components/common/Common';

// 系统路由
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

  private appInfo: SettingGroup<boolean | string | number>[] = [
    {
      settings: [
        { title: '应用版本', info: '1.0.2', icon: $r('app.media.ic_version') },
        { title: '应用原始开发者', info: 'Z-P-J', icon: $rawfile('zpj.png'),
          onClick: () => {
            this.pageStack.pushPathByName("AboutMePage", '')
          }
        },
        { title: '开源仓库', info: 'https://github.com/Z-P-J/AnimeZ', icon: $r('app.media.ic_github'),
          onClick: () => {
            this.pageStack.pushPathByName("WebPage", "https://github.com/Z-P-J/AnimeZ")
          }
        },
        { title: '应用维护者', info: '小雅', icon: $rawfile('ya.png'),
          onClick: () => {
            this.pageStack.pushPathByName("WebPage", "https://github.com/XHXYT/")
          }
        },
        { title: '新开源仓库', info: 'https://github.com/XHXYT/AnimeZ', icon: $r('app.media.ic_github'),
          onClick: () => {
            this.pageStack.pushPathByName("WebPage", "https://github.com/XHXYT/AnimeZ")
          }
        },
        { title: '开源社区', info: 'https://gitee.com/ohos-dev', icon: $r('app.media.ic_community'),
          onClick: () => {
            router.pushUrl({url: 'pages/WebPage', params: {url: 'https://gitee.com/ohos-dev'}})
          }
        },
        { title: '开源社区交流群', info: '752399947', icon: $r('app.media.ic_qq'),
          onClick: () => {
            promptAction.showToast({message: '开发中'})
          }
        }
      ]
    }
  ]

  aboutToAppear() {

  }

  pageTransition() {
    PageTransitionEnter(OPTIONS_TRANSITION_PUSH).slide(SlideEffect.Right)
    PageTransitionEnter(OPTIONS_TRANSITION_POP).slide(SlideEffect.Left)
    PageTransitionExit(OPTIONS_TRANSITION_PUSH).slide(SlideEffect.Left)
    PageTransitionExit(OPTIONS_TRANSITION_POP).slide(SlideEffect.Right)
  }

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

              if (index < this.appInfo.length - 1) {
                Blank().height(16)
              }
            },
            // 唯一键生成
            (group: SettingGroup<SettingGroupType>) => {
              return group.title || String(group.settings.length)
            }
          )
        }
        .padding(16)
        .width('100%')
        .constraintSize({
          minHeight: '100%'
        })
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