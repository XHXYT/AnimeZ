
import TitleBar from '../../components/TitleBar'
import { SettingsGroupList, SettingsListCardMode } from '../../components/SettingsGroupList';
import { CustomItemInfo, ItemActionType } from '../../entity/CusItemInfo';
import { AnimeState } from '../../entryability/AnimeState';

@Builder
export function ThirdPartyServicesPageBuilder(name: string, param: Object) {
  ThirdPartyServicesPage()
}

@ComponentV2
struct ThirdPartyServicesPage {

  private services: CustomItemInfo[] = [
    new CustomItemInfo({
      id: 'danmakuflamemaster',
      title: '@ohos/danmakuflamemaster',
      subtitle: '弹幕渲染引擎 · ^2.1.3',
      icon: $r('app.media.ic_community'),
      type: ItemActionType.NONE
    }),
    new CustomItemInfo({
      id: 'ijkplayer',
      title: '@ohos/ijkplayer',
      subtitle: 'IjkPlayer 视频播放 · ^2.0.11',
      icon: $r('app.media.ic_community'),
      type: ItemActionType.NONE
    }),
    new CustomItemInfo({
      id: 'redplayer',
      title: '@rte-xhs/redplayer',
      subtitle: 'RedPlayer 视频播放（小红书）· ^1.0.0',
      icon: $r('app.media.ic_community'),
      type: ItemActionType.NONE
    }),
    new CustomItemInfo({
      id: 'mpv_arkts',
      title: '@mpv-ohos/mpv-arkts',
      subtitle: 'MPV 视频播放 · ^1.0.0',
      icon: $r('app.media.ic_community'),
      type: ItemActionType.NONE
    }),
    new CustomItemInfo({
      id: 'webdav',
      title: '@ya520/webdav',
      subtitle: 'WebDAV 远程存储客户端 · ^1.0.1',
      icon: $r('app.media.ic_community'),
      type: ItemActionType.NONE
    })
  ]

  build() {
    NavDestination() {
      TitleBar({title: '三方服务'})

      Scroll() {
        Column() {
          Text('本应用使用了以下开源三方可信服务，感谢各开源团队的贡献')
            .fontSize(14)
            .fontColor($r('app.color.color_text_minor'))
            .textAlign(TextAlign.Center)
            .margin({ top: 28, bottom: 28 })
            .padding({ left: 16, right: 16 })
          SettingsGroupList({
            items: this.services,
            cardMode: SettingsListCardMode.CONNECTED,
            contentPadding: { left: 0, right: 0, top: 0, bottom: 0 },
            scrollable: false
          })
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
    .padding({top: AnimeState.topRectHeight, bottom: AnimeState.bottomRectHeight - 20})
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
  }

}
