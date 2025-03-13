
@Component
export default struct TitleBar {
  @State title: ResourceStr = ''
  @State subtitle: ResourceStr = ''
  @Consume('pageStack') pageStack: NavPathStack
  @BuilderParam button: () => void

  build() {
    Column() {
      Row({space: 16}) {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(27)
          .fontColor([$r('app.color.color_text_major')])
          .onClick(() => {
            this.pageStack.pop(true)
          })
        Column() {
          Text(this.title)
            .fontColor($r('app.color.color_text_major'))
            .fontSize(16)
            .maxLines(1)
            .fontWeight(500)
            .textOverflow({overflow: TextOverflow.Ellipsis})
            .textAlign(TextAlign.Start)
          Text(this.subtitle)
            .fontColor($r('app.color.color_text_major'))
            .fontSize(10)
            .maxLines(1)
            .textOverflow({overflow: TextOverflow.Ellipsis})
            .margin({top: 4})
            .textAlign(TextAlign.Start)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Blank()
        if (this.button) {
          this.button()
        }
      }
      .height(56)
      .width('100%')
      .padding({left: 16, right: 16})
      .alignItems(VerticalAlign.Center)
    }
  }
}