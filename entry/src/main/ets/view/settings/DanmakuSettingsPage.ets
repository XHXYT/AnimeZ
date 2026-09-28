
import TitleBar from '../../components/TitleBar'
import { SettingsGroupList } from '../../components/SettingsGroupList'
import { CustomItemInfo, ItemActionType, MenuOption } from '../../entity/CusItemInfo'
import { appSettings } from '../../entryability/Settings'
import { AnimeState } from '../../entryability/AnimeState'

// 系统路由 - 弹幕配置
@Builder
export function DanmakuSettingsPageBuilder(name: string, param: Object) {
  DanmakuSettingsPage()
}

@ComponentV2
struct DanmakuSettingsPage {

  /** 列表版本号：页面重新可见时递增，作为列表重建前缀强制刷新选中态 */
  @Local private listVersion: number = 0

  /**
   * 设置项数据（getter 每次求值，读 appSettings 最新值保证选中态同步）
   */
  private get itemList(): CustomItemInfo[] {
    return [
      // 弹幕组
      new CustomItemInfo({ id: 'group_danmaku', title: '弹幕', type: ItemActionType.GROUP }),
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
      })
    ]
  }

  build() {
    NavDestination() {
      Column() {
        // 标题
        TitleBar({ title: '弹幕配置' })
        // 内容
        SettingsGroupList({ items: this.itemList, version: this.listVersion })
          .layoutWeight(1)
      }
      .layoutWeight(1)
      .padding({ top: AnimeState.topRectHeight, bottom: AnimeState.bottomRectHeight - 20 })
    }
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .onShown(() => {
      // 页面重新可见时重建列表，同步可能被修改的配置
      this.listVersion++
    })
    .width('100%')
    .height('100%')
  }

}
