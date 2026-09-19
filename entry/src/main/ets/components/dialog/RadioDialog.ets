@ComponentV2
export struct RadioDialog {
  @Param title: ResourceStr = ''
  @Param values: string[] = []
  @Param initialIndex: number = 0
  @Local checkIndex: number = 0
  @Event onSelect: (index: number) => void = () => {}
  @Event onClose: () => void = () => {}

  aboutToAppear(): void {
    this.checkIndex = this.initialIndex
  }

  build() {
    Column() {
      Text(this.title)
        .fontSize(18)
        .fontColor($r('app.color.color_text_major'))
        .fontWeight(FontWeight.Medium)
        .margin({ left: 16, top: 16 })
        .alignSelf(ItemAlign.Start)

      Column() {
        ForEach(this.values, (item: string, i) => {
          Row() {
            Radio({ value: item, group: 'radioGroup' })
              .checked(this.checkIndex === i)
              .height(20)
              .width(20)
              .onChange((isChecked: boolean) => {
                if (isChecked) {
                  this.checkIndex = i
                }
              })
            Text(item).fontSize(14)
              .fontColor($r('app.color.color_text_major'))
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          .onClick(() => {
            this.checkIndex = i
          })
        })
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
            this.onSelect(this.checkIndex)
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
