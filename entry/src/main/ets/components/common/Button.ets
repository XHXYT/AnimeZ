import { SymbolGlyphModifier } from "@kit.ArkUI";

/**
 * 功能按钮
 */
@Component
export struct  ButtonBuilder {

  @Prop config: ButtonConfig
  @Prop menuSelected: string | number

  build() {
    Button({ type: this.config.type || ButtonType.Normal }) {
      ButtonContent(this.config)
    }
    .width(this.config.size).height(this.config.size)
    .backgroundColor(this.config.backgroundColor ?? Color.Transparent)
    .enabled(this.config.enabled ?? true) // 使用 ?? 处理 undefined，默认为 true
    .onClick(() => {
      this.config.action?.();
    })
    .bindMenu(this.config.menuItems && this.config.menuItems.length > 0 ? this.buttonMenu(this.config) : undefined)
  }

  // 构建下拉菜单
  @Builder
  buttonMenu(config: ButtonConfig) {
    Menu() {
      MenuItemGroup({ header: config.menuTitle }) {
        ForEach(config.menuItems, (item: MenuItem) => {
          MenuItem({
            content: item.name,
            startIcon: item.startIconSrc ? item.startIconSrc : undefined, // MenuItem 的 icon 属性
            symbolStartIcon: item.symbolStart ? new SymbolGlyphModifier($r('sys.symbol.' + item.symbolStart)) : undefined,
            symbolEndIcon: this.menuSelected == item.value ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
          }).onClick(() => {
            this.menuSelected = item.value
            item.action?.()
          })
        })
      }
    }
  }

}

// 构建按钮内容（图标 + 文本）
@Builder
function ButtonContent(config: ButtonConfig) {
  // 如果有图标
  if (config.imageSrc || config.symbolSrc) {
    Row() {
      // 优先使用 Image 图标
      if (config.imageSrc) {
        Image(config.imageSrc)
          .width(config.iconSize || 24)
          .height(config.iconSize || 24)
          .fillColor(config.fontColor || Color.Transparent)
      }
      // 否则使用 Symbol 图标
      else if (config.symbolSrc) {
        SymbolGlyph($r('sys.symbol.' + config.symbolSrc))
          .fontSize(config.iconSize || 24)
          .fontColor([config.fontColor || Color.Transparent])
      }
      // 如果同时有文本，添加间距
      if (config.text) {
        Text(config.text)
          .fontColor(config.fontColor || Color.Transparent)
          .margin({ left: 8 })
      }
    }
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }
  // 如果没有图标，只有文本
  else if (config.text) {
    Text(config.text)
      .fontColor(config.fontColor || undefined)
  }
}

/**
 * 按钮配置接口
 */
export interface ButtonConfig {
  // 基础属性
  text?: string; // 按钮文本
  action?: () => void; // 点击事件

  // 图标属性 (image 和 symbol 互斥，优先使用 image)
  imageSrc?: ResourceStr; // 图片图标资源 (如: $r('app.media.ic_settings'))
  symbolSrc?: ResourceStr; // Symbol图标资源 (如: $r('app.symbol.settings'))
  iconSize?: number; // 图标大小，默认 24vp

  // 菜单属性
  menuSelected?: string | number
  menuTitle?: ResourceStr
  menuItems?: MenuItem[]; // 绑定的菜单项列表

  // 样式属性
  type?: ButtonType; // 按钮类型，默认 ButtonType.Normal
  size?: number; // 按钮大小，
  backgroundColor?: ResourceColor; // 背景色
  fontColor?: ResourceColor; // 文本和图标颜色
  enabled?: boolean; // 是否可用，默认 true
}

/**
 * 菜单项接口
 */
export interface MenuItem {
  name: string; // 菜单项文本
  value: string | number
  action?: () => void; // 菜单项点击事件
  symbolStart?: string
  startIconSrc?: ResourceStr; // 菜单项图标 (可选)
}
