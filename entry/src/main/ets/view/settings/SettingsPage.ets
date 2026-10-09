
import TitleBar from '../../components/TitleBar'
import { SettingsContent } from '../../components/SettingsContent'
import { AnimeState } from '../../entryability/AnimeState'

// 系统路由
@Builder
export function SettingsPageBuilder(name: string, param: Object) {
  SettingsPage()
}

@ComponentV2
struct SettingsPage {

  build() {
    NavDestination() {
      // 标题
      TitleBar({ title: '设置' })
      // 内容（选中态刷新由 SettingsContent 内部 @AnimeState.onShow 监听处理）
      SettingsContent()
        .layoutWeight(1)

      Text('本应用仅供学习交流！')
        .fontSize(16)
        .fontColor($r('app.color.color_text_major'))
        .padding(8)

    }
    .padding({top: AnimeState.topRectHeight, bottom: AnimeState.bottomRectHeight - 20})
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
  }

}
