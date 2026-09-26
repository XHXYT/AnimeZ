import { SymbolGlyphModifier } from "@kit.ArkUI";

/**
 * 功能按钮
 */
@ComponentV2
export struct ButtonBuilder {

  @Require @Param config: ButtonConfig
  @Param menuSelected: string | number = ''
  @Local selectedInner: string | number = ''

  aboutToAppear(): void {
    this.selectedInner = this.menuSelected
  }

  @Monitor('menuSelected')
  onMenuSelectedChange(): void {
    this.selectedInner = this.menuSelected
  }

  build() {
    Button({ type: this.config.type || ButtonType.Circle }) {
      ButtonContent(this.config)
    }
    .width(this.config.width || 36).height(this.config.height || 36)
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
            labelInfo: item.labelInfo,
            symbolEndIcon: (item.checked || (this.selectedInner == item.value && config.needCheckmark)) ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined,
            builder: this.hasChildren(item) ? (): void => {
              this.subMenu(item)
            } : undefined
          }).onClick(() => {
            // 有二级子菜单的项仅负责展开，不触发动作
            if (this.hasChildren(item)) {
              return
            }
            if (item.value != config.prohibitValue) {
              this.selectedInner = item.value
            }
            item.action?.()
          })
        })
      }
    }
  }

  private hasChildren(item: MenuItem): boolean {
    return item.children !== undefined && item.children.length > 0
  }

  // 二级子菜单（builder 内容必须以 Menu 为容器，否则渲染异常）
  @Builder
  subMenu(item: MenuItem) {
    Menu() {
      ForEach(item.children ?? [], (child: MenuItem) => {
        MenuItem({
          content: child.name,
          symbolStartIcon: child.symbolStart ? new SymbolGlyphModifier($r('sys.symbol.' + child.symbolStart)) : undefined,
          symbolEndIcon: child.checked ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
        }).onClick(() => {
          child.action?.()
        })
      }, (child: MenuItem): string => child.value.toString())
    }
  }

}

// 构建按钮内容（图标 + 文本）
@Builder
function ButtonContent(config: ButtonConfig) {
  // 如果有图标
  if (config.imageSrc || config.symbolSrc) {
    Row({space: 8}) {
      if (config.imageSrc || config.symbolSrc) {
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
      }
      // 如果同时有文本
      if (config.text) {
        Text(config.text)
          .fontColor(config.fontColor || Color.Transparent)
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
  needCheckmark?: boolean
  menuSelected?: string | number
  menuTitle?: ResourceStr
  menuItems?: MenuItem[]; // 绑定的菜单项列表
  prohibitValue?: string, // 禁止赋值的值

  // 样式属性
  type?: ButtonType; // 按钮类型，默认 ButtonType.Normal
  width?: Length; // 按钮宽度
  height?: Length // 按钮高度
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
  checked?: boolean; // 独立勾选态（优先于 menuSelected 单选勾选）
  labelInfo?: string; // 右侧标签信息（如当前值）
  children?: MenuItem[]; // 二级子菜单（存在时点击仅展开，不触发 action）
}
