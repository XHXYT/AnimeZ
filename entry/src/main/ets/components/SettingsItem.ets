
import { MenuItem, Preference, SettingItem } from "../entity/SettingsData"
import { SymbolGlyphModifier } from "@kit.ArkUI"

/**
 * 普通设置行(可带跳转符号)
 */
@Component
export struct SettingRow {
  @State title: ResourceStr = ''
  @State subtitle: ResourceStr = ''
  @State icons: ResourceStr = ''
  @State infoRes: ResourceStr = ''
  @State isOnClick: boolean = false
  onCheck: () => void = () => {}

  aboutToAppear() {
  }

  build() {
    Row() {
      if (this.icons) {
        Image(this.icons)
          .width(32)
          .height(32)
          .borderRadius(100)
          .margin({ right: 16 })
          .objectFit(ImageFit.Contain)
      }

      Column() {
        Text(this.title)
          .fontSize(15)
          .fontWeight(450)
          .fontColor($r('app.color.color_text_major'))
          .align(Alignment.Start)
          .width('100%')
        if (this.subtitle) {
          Text(this.subtitle)
            .fontSize(12)
            .fontWeight(350)
            .margin({ top: 4 })
            .fontColor($r('app.color.color_text_minor'))
            .align(Alignment.Start)
            .width('100%')
        } else if (this.infoRes) {
          Text(this.infoRes)
            .fontSize(12)
            .fontWeight(350)
            .margin({ top: 4 })
            .fontColor($r('app.color.color_text_minor'))
            .align(Alignment.Start)
            .width('100%')
        }
      }
      .layoutWeight(1)
      if (this.isOnClick) {
        Image($r('app.media.ic_enter'))
          .width(18)
          .height(24)
          .objectFit(ImageFit.Contain)
      }
      Blank()
    }
    .padding(16)
    .width('100%')
    .onClick(() => {
      this.onCheck()
    })
  }
}

/**
 * 开关设置行
 */
@Component
export struct ToggleSettingRow {
  @State isOn: boolean = false
  @State title: ResourceStr = ''
  @State subtitle: ResourceStr = ''
  @State icons: ResourceStr = ''
  @State iconBlendColor: Color = Color.White
  @State rowWidth: number = 0
  @State toggleX: number = 0
  @State preference: Preference<boolean> = {
    key: "",
    type: "switch",
    defaultValue: false,
    menu: []
  }
  @BuilderParam toggle: () => void = this.defaultBuilder
  // 默认开关
  @Builder
  defaultBuilder() {
    Toggle({ type: ToggleType.Switch, isOn: this.isOn })
      .selectedColor($r('app.color.primary_color'))
      .hitTestBehavior(HitTestMode.Transparent)
      .responseRegion({
        x: -this.toggleX,
        y: 0,
        width: this.rowWidth,
        height: '100%'
      })
      .onAreaChange((_, newArea: Area) => {
        // Logger.e('tips', 'onAreaChange newArea=' + JSON.stringify(newArea))
        if (newArea.position.x !== undefined) {
          this.toggleX = parseInt(newArea.position.x.toString())
        }
      })
    .onChange((isOn) => {
      if (this.isOn == isOn || typeof this.preference.key !== 'string') {
        return
      }
      this.isOn = isOn
      // 执行已配置函数
      if (this.preference.onValueChange) {
        this.preference.onValueChange(this.preference.key, isOn)
      }
    })
  }

  build() {
    Row() {
      if (this.icons) {
        Image(this.icons)
          .width(24)
          .height(24)
          .margin({ right: 16 })
          .fillColor(this.iconBlendColor)
          .objectFit(ImageFit.Contain)
      }

      Column() {
        Text(this.title)
          .fontSize(15)
          .fontWeight(450)
          .fontColor($r('app.color.color_text_major'))
          .align(Alignment.Start)
          .width('100%')
        Text(this.subtitle)
          .fontSize(12)
          .fontWeight(350)
          .margin({ top: 4 })
          .fontColor($r('app.color.color_text_minor'))
          .align(Alignment.Start)
          .width('100%')
      }
      .layoutWeight(1)
      this.toggle()
      Blank()
    }
    .padding(16)
    .width('100%')
    .onAreaChange((_, newArea) => {
      // Logger.e('tips', 'onAreaChange newArea=' + JSON.stringify(newArea))
      this.rowWidth = parseInt(newArea.width.toString())
    })
  }
}

/**
 * 菜单设置行
 */
@Component
export struct MenuSettingRow {

  @State selected: string = ''
  @State title: ResourceStr = ''
  @State tips?: ResourceStr = ''
  @State info: string = ''
  @State icons: ResourceStr = ''
  @State iconBlendColor: Color = Color.White
  @State rowWidth: number = 0
  @State toggleX: number = 0
  @State isShowMenu: boolean = false
  @Prop preference: Preference<string>
  // 菜单
  @BuilderParam menu: () => void = this.defaultMenuBuilder
  // 默认菜单
  @Builder
  defaultMenuBuilder() {
    Menu() {
      ForEach(this.preference.menu, (menuItem: MenuItem) => {
        MenuItem({
          content: menuItem.view,
          symbolEndIcon: this.selected === menuItem.value ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
        })
          .selected(this.selected === menuItem.value)
          .onChange((selected) => {
            if (this.selected === menuItem.value || typeof this.preference.key !== 'string') {
              return
            }
            this.selected = menuItem.value
            this.tips = menuItem.view
            if (this.preference.onValueChange) {
              this.preference.onValueChange(this.preference.key, menuItem.value)
            }
            this.isShowMenu = false
          })
      }, (menuItem: MenuItem) => menuItem.value)
    }
  }

  aboutToAppear() {
    console.log('#MenuSettingRow menu：', JSON.stringify(this.preference.menu))
    this.tips = this.preference.menu.find(item => item.value === this.selected)?.view
    console.log('#MenuSettingRow selected值：', this.selected)
  }

  build() {
    Row() {
      if (this.icons) {
        Image(this.icons)
          .width(24)
          .height(24)
          .margin({ right: 16 })
          .fillColor(this.iconBlendColor)
          .objectFit(ImageFit.Contain)
      }
      Text(this.title)
        .fontSize(15)
        .fontWeight(450)
        .fontColor($r('app.color.color_text_major'))
        .align(Alignment.Start)
        .width('100%')
        .layoutWeight(1)
      // 菜单
      Row() {
        Text(this.tips !== '' ? this.tips : this.info)
          .fontSize(12)
          .fontWeight(350)
          .margin({ right: 4 })
          .fontColor($r('app.color.color_text_minor'))
          .align(Alignment.Start)
        SymbolGlyph($r('sys.symbol.arrowtriangle_down_fill'))
          .fontSize(14)
          .margin({left: 5, right: 8})
          .fontColor([$r('app.color.color_text_minor')])
      }
      .bindContextMenu(this.isShowMenu, this.menu(), {
        onDisappear: () => {
          this.isShowMenu = false
        }
      })
      .responseRegion({
        x: -this.toggleX,
        y: 0,
        width: this.rowWidth,
        height: '100%'
      })
    }
    .padding(16)
    .width('100%')
    .onClick(() => {
      if (this.isShowMenu)
        return
      this.isShowMenu = true
    })
    .onAreaChange((_, newArea) => {
      // Logger.e('tips', 'onAreaChange newArea=' + JSON.stringify(newArea))
      this.rowWidth = parseInt(newArea.width.toString())
    })
  }
}

/*@Component
export struct RadioSettingRow {
  @StorageLink('currentColorMode') currentMode: number = 1
  @State index: number = 0
  @State title: ResourceStr = ''
  @State subtitle: ResourceStr = ''
  @State prefKey: string = ''
  @State icons: ResourceStr = ''
  @State iconBlendColor: Color = Color.White
  @State values: string[] = []
  private onSelect: (index: number) => void = (index: number) => {}

  // 创建一个选择controller
  private sourceController: CustomDialogController = new CustomDialogController({
    builder: RadioDialog({
      title: this.title,
      prefKey: this.prefKey,
      values: this.values,
      onSelect: (index) => {
        if (this.index == index) {
          return
        }
        this.index = index
        DataStore.set(this.prefKey, index)
        if (this.values) {
          this.subtitle = this.values[this.index]
        }
        if (this.onValueChange) {
          this.preference.onValueChange(this.preference.key, this.index)
        }
        this.onSelect(index)
      }
    }),
    cancel: () => {
      console.log("cancel")
    },
    autoCancel: true,
    customStyle: true
  })



  build() {
    Row() {
      if (this.icons) {
        Image(this.icons)
          .width(24)
          .height(24)
          .margin({ right: 16 })
          .fillColor(this.iconBlendColor)
          .objectFit(ImageFit.Contain)
      }

      Column() {
        Text(this.title)
          .fontSize(15)
          .fontWeight(450)
          .fontColor($r('app.color.color_text_major'))
          .align(Alignment.Start)
          .width('100%')
        Text(this.subtitle)
          .fontSize(12)
          .fontWeight(350)
          .margin({ top: 4 })
          .fontColor($r('app.color.color_text_minor'))
          .align(Alignment.Start)
          .width('100%')
      }
      .layoutWeight(1)

      Image($r('app.media.ic_enter'))
        .width(18)
        .height(24)
        .objectFit(ImageFit.Contain)

      Blank()
    }
    .padding(16)
    .width('100%')
    .onClick(() => {
      this.sourceController.open()
    })
  }
}*/
