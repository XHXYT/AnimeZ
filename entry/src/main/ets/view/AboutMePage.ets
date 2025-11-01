
import TitleBar from '../components/TitleBar'
import { SettingGroup, SettingGroupType, SettingItem } from '../entity/SettingsData';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { SettingRow } from '../components/SettingsItem';
import { ToastUtil } from '../utils/ToastUtils';

// 系统路由 - 关于作者
@Builder
export function AboutMePageBuilder(name: string, param: string) {
  AboutMePage()
}

@Component
struct AboutMePage {

  @Consume DarkModeImage: boolean
  @Consume('pageStack') pageStack: NavPathStack
  // 顶部避让高度
  @StorageProp('topRectHeight') topHeight: number = 0
  // 底部避让高度
  @StorageProp('bottomRectHeight') bottomHeight: number = 0

  private aboutMe: SettingGroup<boolean | string | number>[] = [
    {
      title: '原作者',
      name: 'Z-P-J',
      key: 'zpj',
      introduce: '开源鸿蒙应用开发爱好者，为开源鸿蒙应用生态作出微薄的贡献',
      image: $rawfile('zpj.png'),
      settings: [
        {
          title: 'Github主页',
          info: 'https://github.com/Z-P-J',
          icon: $r('app.media.ic_github'),
          settings_key: 'raw_author_github',
          onClick: (item, callback) => {
            this.pageStack.pushPathByName("WebPage", "https://github.com/Z-P-J")
            callback?.()
          }
        },
        {
          title: 'Gitee主页',
          info: 'https://gitee.com/z-p-j',
          settings_key: 'raw_author_gitee',
          icon: $r('app.media.ic_gitee'),
          onClick: (item, callback) => {
            this.pageStack.pushPathByName("WebPage", "https://gitee.com/z-p-j")
            callback?.()
          }
        },
        {
          title: '赞助作者',
          info: '赞助作者一杯咖啡',
          settings_key: 'support_raw_author',
          icon: $r('app.media.ic_java'),
          onClick: (item, callback) => {
            ToastUtil.showToast({message: '该功能暂未实现，感谢您的支持！'})
            callback?.()
          }
        },
      ]
    },
    {
      title: '维护者',
      name: '小雅',
      key: 'ya',
      introduce: '鸿蒙应用开发爱好者，一只代码小白',
      image: $rawfile('ya.png'),
      settings: [
        {
          title: 'Github主页',
          settings_key: 'new_author_github',
          info: 'https://github.com/XHXYT',
          icon: $r('app.media.ic_github'),
          onClick: (item, callback) => {
            this.pageStack.pushPathByName("WebPage", "https://github.com/XHXYT")
            callback?.()
          }
        },
        {
          title: 'Gitee主页',
          settings_key: 'new_author_gitee',
          info: 'https://gitee.com/DXHXYT',
          icon: $r('app.media.ic_gitee'),
          onClick: (item, callback) => {
            this.pageStack.pushPathByName("WebPage", "https://gitee.com/DXHXYT")
            callback?.()
          }
        },
        {
          title: '赞助作者',
          info: '赞助作者一杯咖啡',
          settings_key: 'support_new_author',
          icon: $r('app.media.ic_java'),
          onClick: (item, callback) => {
            ToastUtil.showToast({message: '该功能暂未实现，感谢您的支持！'})
            callback?.()
          }
        },
      ]
    },
    {
      title: '维护者',
      name: 'SummerKaze',
      key: 'summer',
      introduce: '鸿蒙应用开发爱好者',
      image: $rawfile('summer_kaze.jfif'),
      settings: [
        {
          title: 'Github主页',
          settings_key: 'new_author_github',
          info: 'https://github.com/SummerKaze',
          icon: $r('app.media.ic_github'),
          onClick: (item, callback) => {
            this.pageStack.pushPathByName("WebPage", "https://github.com/SummerKaze")
            callback?.()
          }
        },
        {
          title: 'Gitee主页',
          settings_key: 'new_author_gitee',
          info: 'https://gitee.com/SummerKaze',
          icon: $r('app.media.ic_gitee'),
          onClick: (item, callback) => {
            this.pageStack.pushPathByName("WebPage", "https://gitee.com/SummerKaze")
            callback?.()
          }
        },
        {
          title: '赞助作者',
          info: '赞助作者一杯咖啡',
          settings_key: 'support_new_author',
          icon: $r('app.media.ic_java'),
          onClick: (item, callback) => {
            ToastUtil.showToast({message: '该功能暂未实现，感谢您的支持！'})
            callback?.()
          }
        },
      ]
    }
  ]

  aboutToAppear() {

  }


  build() {
    NavDestination() {
      TitleBar({title: '关于作者'})

      Scroll() {
        Column({space: 5}) {
          // 关于作者详情
          ForEach(
            this.aboutMe,
            (group: SettingGroup<SettingGroupType>, index) => {
              Image(group.image)
                .height(64)
                .width(64)
                .margin({top: 56})
                .borderRadius(100)
                .shadow({ radius: 12, color: this.DarkModeImage ? '#333333' : '#aaaaaa', offsetX: 6, offsetY: 6 })
              Text(group.title)
                .fontSize(18)
                .fontColor($r('app.color.color_text_major'))
                .fontWeight(500)
                .padding({ top: 12 })
              Text(group.introduce)
                .fontSize(14)
                .fontColor($r('app.color.color_text_major'))
                .margin({ top: 8, bottom: 56 })
                .textAlign(TextAlign.Center)
                .constraintSize({
                  maxWidth: '80%'
                })
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
                  }, (setting: SettingItem<SettingGroupType>) => setting.settings_key)
              }
              .backgroundColor($r('app.color.background_color'))
              .borderRadius(16)

              if (index < this.aboutMe.length - 1) {
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