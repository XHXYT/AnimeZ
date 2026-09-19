import { appSettings } from '../../entryability/Settings';

@ComponentV2
export struct SliderDialog {
  @Local value: number = 3
  @Event select: (value: number) => void = () => {}
  @Event onClose: () => void = () => {}

  aboutToAppear(): void {
    this.value = appSettings.max_downloading_count
  }

  build() {
    Column() {
      Text('最大下载数')
        .fontSize(18)
        .fontColor($r('app.color.color_text_major'))
        .fontWeight(FontWeight.Medium)
        .margin({ left: 16, top: 16 })
        .alignSelf(ItemAlign.Start)
      Row() {
        Slider({
          value: this.value,
          min: 1,
          max: 5,
          step: 1,
          style: SliderStyle.OutSet
        })
          .showSteps(true)
          .layoutWeight(1)
          .onChange((value: number, mode: SliderChangeMode) => {
            this.value = value
          })
        Text(this.value.toFixed(0))
          .fontSize(14)
          .fontColor($r('app.color.color_text_minor'))
          .margin({right: 6})
      }
      .margin(16)

      Row() {
        Text("取消")
          .height("100%")
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .fontSize(14)
          .fontColor($r('app.color.color_text_normal'))
          .onClick(() => {
            this.onClose()
          })
        Row()
          .size({ width: 1.5, height: 14 })
          .backgroundColor("#80cccccc")
        Text("确定")
          .textAlign(TextAlign.Center)
          .fontSize(14)
          .fontColor("#317ef5")
          .height("100%")
          .layoutWeight(1)
          .onClick(() => {
            appSettings.max_downloading_count = this.value
            this.select(this.value)
            this.onClose()
          })
      }
      .height(46)
      .width('100%')
    }
    .backgroundColor($r('app.color.background_color'))
    .borderRadius(16)
    .width('80%')
  }
}
