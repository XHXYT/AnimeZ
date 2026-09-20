
import TitleBar from '../components/TitleBar'
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { CustomListItem } from '../components/CustomListItem';
import { CustomItemInfo, ItemActionType } from '../entity/CusItemInfo';
import { ToastUtil } from '../utils/ToastUtils';
import { AppSettings } from '../entryability/Settings';
import { GoToWeb } from '../utils/GoOutWeb';
import { AnimeState } from '../entryability/AnimeState';

// 系统路由 - 应用信息
@Builder
export function AppInfoPageBuilder(name: string, param: Object) {
  AppInfoPage()
}

@ComponentV2
struct AppInfoPage {

  private appInfo: CustomItemInfo[] = [
    new CustomItemInfo({
      id: 'version',
      title: '应用版本',
      subtitle: AppSettings.versionName,
      icon: $r('app.media.ic_version'),
      type: ItemActionType.NONE
    }),
    new CustomItemInfo({
      id: 'raw_author',
      title: '应用原始开发者',
      subtitle: 'Z-P-J',
      icon: $rawfile('zpj.png'),
      type: ItemActionType.NONE,
      onChange: () => {
        AnimeState.pageStack.pushPathByName("WebPage", "https://github.com/Z-P-J")
      }
    }),
    new CustomItemInfo({
      id: 'raw_repo',
      title: '开源仓库',
      subtitle: 'https://github.com/Z-P-J/AnimeZ',
      icon: $r('app.media.ic_github'),
      type: ItemActionType.NONE,
      onChange: () => {
        AnimeState.pageStack.pushPathByName("WebPage", "https://github.com/Z-P-J/AnimeZ")
      }
    }),
    new CustomItemInfo({
      id: 'new_author',
      title: '应用维护者',
      subtitle: '小雅',
      icon: $rawfile('ya.png'),
      type: ItemActionType.NONE,
      onChange: () => {
        AnimeState.pageStack.pushPathByName("WebPage", "https://github.com/XHXYT/")
      }
    }),
    new CustomItemInfo({
      id: 'new_author_summer',
      title: '应用维护者',
      subtitle: 'SummerKaze',
      icon: $rawfile('summer_kaze.jfif'),
      type: ItemActionType.NONE,
      onChange: () => {
        AnimeState.pageStack.pushPathByName("WebPage", "https://github.com/SummerKaze/")
      }
    }),
    new CustomItemInfo({
      id: 'new_repo',
      title: '新开源仓库',
      subtitle: 'https://github.com/XHXYT/AnimeZ',
      icon: $r('app.media.ic_github'),
      type: ItemActionType.NONE,
      onChange: () => {
        AnimeState.pageStack.pushPathByName("WebPage", "https://github.com/XHXYT/AnimeZ")
      }
    }),
    new CustomItemInfo({
      id: 'open_harmony',
      title: '开源社区',
      subtitle: 'https://gitee.com/ohos-dev',
      icon: $r('app.media.ic_community'),
      type: ItemActionType.NONE,
      onChange: () => {
        AnimeState.pageStack.pushPathByName("WebPage", "https://gitee.com/ohos-dev")
      }
    }),
    new CustomItemInfo({
      id: 'qq_group',
      title: '鸿蒙交流群',
      subtitle: '693903194',
      icon: $r('app.media.ic_qq'),
      type: ItemActionType.NONE,
      onChange: () => {
        GoToWeb('mqqapi://card/show_pslcard?src_type=internal&version=1&uin=693903194&card_type=group&source=qrcode',
        this.getUIContext().getHostContext()! as common.UIAbilityContext)
      }
    })
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
            .shadow({ radius: 12, color: AnimeState.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#333333' : '#aaaaaa', offsetX: 6, offsetY: 6 })
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
            (item: CustomItemInfo, index) => {
              Column() {
                CustomListItem({
                  item: item,
                  itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
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
            (item: CustomItemInfo) => item.id
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
    .padding({top: AnimeState.topRectHeight - 20, bottom: AnimeState.bottomRectHeight - 20})
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
  }

}
