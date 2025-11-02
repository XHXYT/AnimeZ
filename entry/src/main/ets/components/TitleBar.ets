import { LengthMetrics } from "@kit.ArkUI"

@Component
export default struct TitleBar {
  @State title: ResourceStr = ''
  @State subtitle: ResourceStr = ''
  @State showBack: boolean = true
  @Consume('pageStack') pageStack: NavPathStack
  @BuilderParam button: () => void

  build() {
    Flex({
      direction: FlexDirection.Row,
      alignItems: ItemAlign.Center,
    })
    {
      Row({ space: 16 }) {
        if (this.showBack) {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(27)
            .fontColor([$r('app.color.color_text_major')])
            .onClick(() => {
              this.pageStack.pop(true)
            })
        }
        Column() {
          Text(this.title)
            .fontColor($r('app.color.color_text_major'))
            .fontSize(16)
            .maxLines(1)
            .fontWeight(500)
            .textOverflow({overflow: TextOverflow.Ellipsis})
            .textAlign(TextAlign.Start)
          if (this.subtitle.toString().length > 0) {
            Text(this.subtitle)
              .fontColor($r('app.color.color_text_major'))
              .fontSize(10)
              .maxLines(1)
              .textOverflow({overflow: TextOverflow.Ellipsis})
              .margin({top: 4})
              .textAlign(TextAlign.Start)
          }
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
      }
      .margin({ right: 24})
      Blank()
      if (this.button) {
        this.button()
      }
    }
    .height(56)
    .width('100%')
    .padding({left: 16, right: 16})
  }
}