
import TitleBar, { TitleBarButton } from '../../components/TitleBar'
import { SettingsGroupList } from '../../components/SettingsGroupList'
import {
  CustomItemInfo,
  ItemActionType,
  MenuOption,
  makeSeekSecondsOptions
} from '../../entity/CusItemInfo'
import { appSettings } from '../../entryability/Settings'
import { AnimeState } from '../../entryability/AnimeState'
import { ToastUtil } from '../../utils/ToastUtils'
import Logger from '../../utils/Logger'
import { VideoFit } from '../../player/model/IPlayerManager'
import { SHORTCUT_DEFS, ShortcutDef, PlayerShortcuts, findShortcutConflict } from '../../utils/PlayerShortcuts'
import { KeyCode } from '@kit.InputKit'

// 系统路由
@Builder
export function PlayerControlSettingsPageBuilder(name: string, param: Object) {
  PlayerControlSettingsPage()
}

@ComponentV2
struct PlayerControlSettingsPage {

  /** 列表版本号：配置变化时递增，作为列表重建前缀强制刷新选中态 */
  @Local private listVersion: number = 0

  /** 正在捕获按键的快捷键 action，空串表示非捕获状态 */
  @Local private capturingAction: string = ''

  /**
   * 设置项数据（getter 每次求值，读 appSettings / 快捷键配置最新值保证选中态同步）
   */
  private get itemList(): CustomItemInfo[] {
    const items: CustomItemInfo[] = [
      // 手势组
      new CustomItemInfo({ id: 'group_gesture', title: '手势', type: ItemActionType.GROUP }),
      new CustomItemInfo({
        id: 'video_fit',
        title: '画面尺寸',
        type: ItemActionType.MENU,
        value: String(appSettings.video_fit),
        menuOptions: [
          new MenuOption(String(VideoFit.Contain), '适应'),
          new MenuOption(String(VideoFit.Cover), '填充'),
          new MenuOption(String(VideoFit.Fill), '拉伸'),
          new MenuOption(String(VideoFit.Fit_16_9), '16:9'),
          new MenuOption(String(VideoFit.Fit_4_3), '4:3'),
          new MenuOption(String(VideoFit.Fit_1_1), '1:1')
        ],
        onChange: (value) => {
          appSettings.video_fit = Number(value) as VideoFit
        }
      }),
      new CustomItemInfo({
        id: 'double_tap_seek_forward',
        title: '双击快进秒数',
        subtitle: '双击播放器右侧区域快进的秒数',
        type: ItemActionType.MENU,
        value: String(appSettings.double_tap_seek_forward),
        menuOptions: makeSeekSecondsOptions(),
        onChange: (value) => {
          appSettings.double_tap_seek_forward = Number(value)
        }
      }),
      new CustomItemInfo({
        id: 'double_tap_seek_rewind',
        title: '双击快退秒数',
        subtitle: '双击播放器左侧区域快退的秒数',
        type: ItemActionType.MENU,
        value: String(appSettings.double_tap_seek_rewind),
        menuOptions: makeSeekSecondsOptions(),
        onChange: (value) => {
          appSettings.double_tap_seek_rewind = Number(value)
        }
      }),

      // 键盘快捷键组
      new CustomItemInfo({ id: 'group_shortcuts', title: '键盘快捷键', type: ItemActionType.GROUP })
    ]
    for (const def of SHORTCUT_DEFS) {
      items.push(new CustomItemInfo({
        id: `shortcut_${def.action}`,
        title: def.label,
        subtitle: def.hold ? '按住生效，松开结束' : '',
        type: ItemActionType.TEXT,
        value: PlayerShortcuts.getShortcutLabel(def.action),
        onChange: () => {
          this.capturingAction = def.action
          this.requestCaptureFocus()
        }
      }))
    }
    return items
  }

  /** 正在捕获按键的动作显示名 */
  private get capturingDefLabel(): string {
    const def: ShortcutDef | undefined =
      SHORTCUT_DEFS.find((d: ShortcutDef): boolean => d.action === this.capturingAction)
    return def ? def.label : ''
  }

  /** 重建列表（配置变化后刷新选中态） */
  private refreshList(): void {
    this.listVersion++
  }

  /** 请求页面根节点获得焦点（捕获按键依赖焦点接收键盘事件） */
  private requestCaptureFocus(): void {
    try {
      this.getUIContext().getFocusController().requestFocus('playerControlSettingsRoot')
    } catch (e) {
      Logger.e('fail', 'requestFocus playerControlSettingsRoot', e)
    }
  }

  /** 捕获模式下拦截全部按键：ESC 取消，其它键校验冲突后写入绑定 */
  private handleCaptureKeyEvent(event: KeyEvent): boolean {
    if (this.capturingAction === '') {
      return false
    }
    if (event.type !== KeyType.Down) {
      return true
    }
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      this.capturingAction = ''
      return true
    }
    const conflict: ShortcutDef | undefined = findShortcutConflict(event.keyCode, this.capturingAction)
    if (conflict) {
      ToastUtil.showToast({ message: `该按键已被「${conflict.label}」占用` })
    } else {
      PlayerShortcuts.setShortcutKeyCode(this.capturingAction, event.keyCode)
      this.refreshList()
      ToastUtil.showToast({ message: '快捷键已更新' })
    }
    this.capturingAction = ''
    return true
  }

  /** 标题栏按钮配置 */
  private get titleBarButtons(): TitleBarButton[] {
    return [
      {
        symbol: 'arrow_2_circlepath',
        action: (): void => {
          PlayerShortcuts.resetShortcuts()
          this.refreshList()
          ToastUtil.showToast({ message: '快捷键已恢复默认' })
        }
      }
    ]
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          // 标题
          TitleBar({ title: '播放控制', buttons: this.titleBarButtons })
          // 内容
          SettingsGroupList({ items: this.itemList, version: this.listVersion, contentEndOffset: 56 })
            .layoutWeight(1)
        }
        .layoutWeight(1)
        .padding({ top: AnimeState.topRectHeight, bottom: AnimeState.bottomRectHeight - 20 })
        // 按键捕获遮罩
        if (this.capturingAction !== '') {
          this.CaptureOverlay()
        }
      }
      .width('100%')
      .height('100%')
      .id('playerControlSettingsRoot')
      .focusable(true)
      .focusOnTouch(true)
      .onKeyEventDispatch((event: KeyEvent): boolean => this.handleCaptureKeyEvent(event))
    }
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .onShown(() => {
      // 页面重新可见时重建列表，同步可能被修改的配置
      this.refreshList()
    })
    .width('100%')
    .height('100%')
  }

  /** 按键捕获遮罩：提示按下新按键，ESC 或点击空白处取消 */
  @Builder
  CaptureOverlay() {
    Column() {
      Column({ space: 12 }) {
        Text('设置快捷键')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.color_text_major'))
        Text(`请为「${this.capturingDefLabel}」按下新的按键`)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
        Text('按 ESC 或点击空白处取消')
          .fontSize(12)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .padding(32)
      .borderRadius(24)
      .backgroundColor($r('app.color.background_color'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#66000000')
    .onClick(() => {
      this.capturingAction = ''
    })
  }

}
