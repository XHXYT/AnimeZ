import { AnimeState } from '../entryability/AnimeState'
import { ButtonBuilder, ButtonConfig, MenuItem } from './common/Button'

/**
 * 标题栏按钮配置（由 TitleBar 内部转换为 ButtonConfig 渲染）
 */
export interface TitleBarButton {
  /** Symbol 图标名（自动拼接 sys.symbol. 前缀） */
  symbol?: string
  /** 图片图标资源（优先于 symbol） */
  image?: ResourceStr
  /** 文字按钮文本 */
  text?: string
  /** 图标大小，默认 24vp */
  iconSize?: number
  /** 按钮宽度，默认 36vp */
  width?: Length
  /** 按钮高度，默认 36vp */
  height?: Length
  /** 图标/文字颜色，默认主文字色 */
  fontColor?: ResourceColor
  /** 背景色，默认透明 */
  backgroundColor?: ResourceColor
  /** 是否可用，默认 true */
  enabled?: boolean
  /** 点击事件 */
  action?: () => void
  /** 下拉菜单标题 */
  menuTitle?: ResourceStr
  /** 下拉菜单项列表 */
  menuItems?: MenuItem[]
  /** 下拉菜单当前选中值 */
  menuSelected?: string | number
  /** 菜单项是否显示对勾 */
  needCheckmark?: boolean
  /** 菜单禁止选中值 */
  prohibitValue?: string
}

/**
 * 通用标题栏：返回键 + 标题/副标题 + 可选搜索框 + 右侧按钮（最多渲染 4 个）
 */
@ComponentV2
export default struct TitleBar {
  @Param title: ResourceStr = ''
  @Param subtitle: ResourceStr = ''
  @Param showBack: boolean = true
  /** 搜索框占位符，非空时显示搜索框 */
  @Param searchPlaceholder: ResourceStr = ''
  /** 搜索框文本（用于外部同步） */
  @Param searchText: string = ''
  /** 右侧按钮，最多渲染 4 个 */
  @Param buttons: TitleBarButton[] = []
  /** 右侧内边距，>= 0 时覆盖默认值（用于 sheet 内避让系统关闭按钮） */
  @Param rightInset: number = -1
  /** 搜索框内容变化 */
  @Event onSearchChange: (value: string) => void = (): void => {
  }
  /** 搜索框内容提交 */
  @Event onSearchSubmit: (value: string) => void = (): void => {
  }

  @Local searchValue: string = ''

  aboutToAppear(): void {
    this.searchValue = this.searchText
  }

  @Monitor('searchText')
  onSearchTextChange(): void {
    if (this.searchText !== this.searchValue) {
      this.searchValue = this.searchText
    }
  }

  private get hasSearch(): boolean {
    return this.searchPlaceholder !== ''
  }

  private toButtonConfig(button: TitleBarButton): ButtonConfig {
    return {
      text: button.text,
      action: button.action,
      imageSrc: button.image,
      symbolSrc: button.symbol,
      iconSize: button.iconSize,
      width: button.width,
      height: button.height,
      backgroundColor: button.backgroundColor,
      fontColor: button.fontColor ?? $r('app.color.color_text_major'),
      enabled: button.enabled,
      menuTitle: button.menuTitle,
      menuItems: button.menuItems,
      menuSelected: button.menuSelected,
      needCheckmark: button.needCheckmark,
      prohibitValue: button.prohibitValue
    }
  }

  @Builder
  ButtonSlot(index: number) {
    ButtonBuilder({
      config: this.toButtonConfig(this.buttons[index]),
      menuSelected: this.buttons[index].menuSelected ?? ''
    })
  }

  build() {
    RelativeContainer() {
      // 左侧：返回键 + 标题/副标题（居左）
      Row({ space: 12 }) {
        if (this.showBack) {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(24)
            .fontColor([$r('app.color.color_text_major')])
            .onClick(() => {
              AnimeState.pageStack.pop(true)
            })
        }
        if (this.title !== '' || this.subtitle !== '') {
          Column() {
            Text(this.title)
              .fontColor($r('app.color.color_text_major'))
              .fontSize(16)
              .maxLines(1)
              .fontWeight(500)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Start)
            if (this.subtitle !== '') {
              Text(this.subtitle)
                .fontColor($r('app.color.color_text_major'))
                .fontSize(10)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 4 })
                .textAlign(TextAlign.Start)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .constraintSize({ maxWidth: '40%' })
        }
      }
      .id('titleBarLeft')
      .alignRules({
        left: { anchor: '__container__', align: HorizontalAlign.Start },
        center: { anchor: '__container__', align: VerticalAlign.Center }
      })

      // 中间：搜索框（占满左侧与按钮之间的剩余空间）
      if (this.hasSearch) {
        Search({ placeholder: this.searchPlaceholder, value: this.searchValue })
          .height(36)
          .margin({ left: 12, right: 6 })
          .backgroundColor($r('app.color.background_color'))
          .placeholderColor('#817977')
          .placeholderFont({ size: 14, weight: FontWeight.Normal })
          .fontColor($r('app.color.color_text_major'))
          .id('titleBarSearch')
          .alignRules({
            left: { anchor: 'titleBarLeft', align: HorizontalAlign.End },
            right: this.buttons.length > 0
              ? { anchor: 'titleBarRight', align: HorizontalAlign.Start }
              : { anchor: '__container__', align: HorizontalAlign.End },
            center: { anchor: '__container__', align: VerticalAlign.Center }
          })
          .onChange((value: string) => {
            this.searchValue = value
            this.onSearchChange(value)
          })
          .onSubmit((value: string) => {
            this.onSearchSubmit(value)
          })
      }

      // 右侧：按钮（居右，最多 4 个，无间距靠按钮自身内边距撑开）
      if (this.buttons.length > 0) {
        Row() {
          if (this.buttons.length > 0) {
            this.ButtonSlot(0)
          }
          if (this.buttons.length > 1) {
            this.ButtonSlot(1)
          }
          if (this.buttons.length > 2) {
            this.ButtonSlot(2)
          }
          if (this.buttons.length > 3) {
            this.ButtonSlot(3)
          }
        }
        .alignItems(VerticalAlign.Center)
        .id('titleBarRight')
        .alignRules({
          right: { anchor: '__container__', align: HorizontalAlign.End },
          center: { anchor: '__container__', align: VerticalAlign.Center }
        })
        .offset({
          y: AnimeState.windowMode && AnimeState.titleButtonCenter > 0 ? AnimeState.titleButtonCenter - 28 : 0
        })
      }
    }
    .height(56)
    .width('100%')
    .padding({
      left: 16,
      right: this.rightInset >= 0 ? this.rightInset :
        (AnimeState.windowMode ? Math.max(16, AnimeState.titleButtonWidth + 12) : 16)
    })
  }
}
