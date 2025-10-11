
/**
 * 标题头模板
 */
@Builder
export function Header(title: string, onClick?: () => void, showMore: boolean = false) {
  Row() {
    Row()
      .height(14)
      .width(6)
      .margin({ right: 2 })
      .borderRadius(4)
      .backgroundColor($r('app.color.primary_color'))
    Text(title)
      .fontColor($r('app.color.color_text_major'))
      .fontSize(16)
      .fontWeight(500)
    Blank()
    if (showMore) {
      Text('更多')
        .fontColor($r('app.color.color_text_major'))
        .fontSize(14)
    }
    Image($r("app.media.ic_enter"))
      .width(24)
      .height(24)
      .fillColor('#817977')
      .objectFit(ImageFit.Contain)
  }
  .width('100%')
  .padding({ left: 16, top: 16, right: 16, bottom: 4 })
  .onClick(() => {
    if (onClick)
      onClick()
  })
}