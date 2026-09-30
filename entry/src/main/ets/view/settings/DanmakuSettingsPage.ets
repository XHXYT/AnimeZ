
import TitleBar from '../../components/TitleBar'
import { SettingsGroupList } from '../../components/SettingsGroupList'
import { CustomItemInfo, ItemActionType, MenuOption, SliderConfig } from '../../entity/CusItemInfo'
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

  /** 构建百分比滑块配置（对象字面量无法直接对应类类型，需逐字段赋值） */
  private static percentSlider(min: number, max: number, step: number): SliderConfig {
    const config = new SliderConfig()
    config.min = min
    config.max = max
    config.step = step
    config.unit = '%'
    config.showControl = true
    return config
  }

  /**
   * 设置项数据（getter 每次求值，读 appSettings 最新值保证选中态同步）
   */
  private get itemList(): CustomItemInfo[] {
    return [
      // 弹幕样式组
      new CustomItemInfo({ id: 'group_style', title: '弹幕样式', type: ItemActionType.GROUP }),
      new CustomItemInfo({
        id: 'danmaku_opacity',
        title: '不透明度',
        type: ItemActionType.SLIDER,
        value: appSettings.danmaku_opacity * 100,
        sliderConfig: DanmakuSettingsPage.percentSlider(25, 100, 5),
        onChange: (value) => {
          appSettings.danmaku_opacity = Number(value) / 100
        }
      }),
      new CustomItemInfo({
        id: 'danmaku_font_scale',
        title: '字体大小',
        type: ItemActionType.SLIDER,
        value: appSettings.danmaku_font_scale * 100,
        sliderConfig: DanmakuSettingsPage.percentSlider(50, 150, 5),
        onChange: (value) => {
          appSettings.danmaku_font_scale = Number(value) / 100
        }
      }),
      new CustomItemInfo({
        id: 'danmaku_speed',
        title: '滚动速度',
        subtitle: '越大越快',
        type: ItemActionType.SLIDER,
        value: appSettings.danmaku_speed * 100,
        sliderConfig: DanmakuSettingsPage.percentSlider(100, 200, 10),
        onChange: (value) => {
          appSettings.danmaku_speed = Number(value) / 100
        }
      }),
      new CustomItemInfo({
        id: 'danmaku_bold',
        title: '弹幕加粗',
        type: ItemActionType.TOGGLE,
        value: appSettings.danmaku_bold,
        onChange: (value) => {
          appSettings.danmaku_bold = value as boolean
        }
      }),
      new CustomItemInfo({
        id: 'danmaku_area',
        title: '显示区域',
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
      }),
      // 弹幕屏蔽组
      new CustomItemInfo({ id: 'group_block', title: '弹幕屏蔽', type: ItemActionType.GROUP }),
      new CustomItemInfo({
        id: 'danmaku_block_scroll',
        title: '屏蔽滚动弹幕',
        type: ItemActionType.TOGGLE,
        value: appSettings.danmaku_block_scroll,
        onChange: (value) => {
          appSettings.danmaku_block_scroll = value as boolean
        }
      }),
      new CustomItemInfo({
        id: 'danmaku_block_fixed',
        title: '屏蔽固定弹幕',
        subtitle: '顶部/底部弹幕',
        type: ItemActionType.TOGGLE,
        value: appSettings.danmaku_block_fixed,
        onChange: (value) => {
          appSettings.danmaku_block_fixed = value as boolean
        }
      }),
      new CustomItemInfo({
        id: 'danmaku_block_color',
        title: '屏蔽彩色弹幕',
        type: ItemActionType.TOGGLE,
        value: appSettings.danmaku_block_color,
        onChange: (value) => {
          appSettings.danmaku_block_color = value as boolean
        }
      }),
      new CustomItemInfo({
        id: 'danmaku_hide_duplicate',
        title: '隐藏重复弹幕',
        subtitle: '相同内容短时间内仅显示首条',
        type: ItemActionType.TOGGLE,
        value: appSettings.danmaku_hide_duplicate,
        onChange: (value) => {
          appSettings.danmaku_hide_duplicate = value as boolean
        }
      }),
      new CustomItemInfo({
        id: 'danmaku_block_words',
        title: '弹幕屏蔽词',
        subtitle: '多个屏蔽词用逗号或空格分隔',
        type: ItemActionType.INPUT,
        value: appSettings.danmaku_block_words,
        onChange: (value) => {
          appSettings.danmaku_block_words = String(value)
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
