
@Component
export default struct TitleBar {
  @State title: ResourceStr = ''
  @Consume('pageStack') pageStack: NavPathStack

  build() {
    Column() {
      Row({space: 16}) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(28)
          .fontColor(['#817977'])
          .onClick(() => {
            this.pageStack.pop(true)
          })
        Text(this.title)
          .fontColor($r('app.color.color_text_major'))
          .fontSize(20)
          .fontWeight(500)
          .layoutWeight(1)
          .align(Alignment.Start)
        Blank()
      }
      .height(56)
      .width('100%')
      .padding({left: 16})
    }
  }
}