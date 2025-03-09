
@Component
export default struct TitleBar {
  @State title: ResourceStr = ''
  @Consume('pageStack') pageStack: NavPathStack

  build() {
    Column() {
      Row() {
        Image($r('app.media.ic_arrow_left'))
          .width(24)
          .height(24)
          .margin({ left: 16 })
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.color_text_major'))
          .onClick(() => {
            this.pageStack.pop(true)
          })
        Text(this.title)
          .fontColor($r('app.color.color_text_major'))
          .fontSize(20)
          .fontWeight(500)
          .layoutWeight(1)
          .margin({ left: 16 })
          .align(Alignment.Start)
        Blank()
      }
      .height(56)
      .width('100%')
    }
  }
}