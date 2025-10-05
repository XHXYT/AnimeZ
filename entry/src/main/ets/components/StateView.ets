
export enum ViewState {

  LOADING = 0,
  CONTENT,
  EMPTY,
  ERROR,
  CUSTOM
}

@Component
export default struct StateView {
  // @Consume('StateView') state: number
  @Link state: number
  @Link errorMessage: string
  @BuilderParam content: () => void;
  @BuilderParam custom: (key: string) => void;
  onRetry?: () => boolean;

  aboutToAppear(): void {
    console.log('stateview ', this.state)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.state == ViewState.LOADING) {
        Column() {
          // 加载中
          LoadingProgress().width(80).aspectRatio(1).color('#817977')
          Text('加载中...')
            .fontSize(14)
            .fontColor('#817977')
            .textAlign(TextAlign.Center)
            .constraintSize({ maxWidth: '80%' })
            .margin({ bottom: 60, top: 12 })
        }
      } else if (this.state == ViewState.CONTENT) {
        if (this.content) {
          this.content()
        }
      } else if (this.state == ViewState.EMPTY) {
        this.ImageWithText($r('app.media.ic_empty'), "暂无数据", this.errorMessage)
      } else if (this.state == ViewState.ERROR) {
        this.ImageWithText($r('app.media.ic_error'), "出错了，点击重试", this.errorMessage)
      } else if (this.state == ViewState.CUSTOM) {
        if (this.custom) {
          this.custom('key')
        }
      }
    }
    .backgroundColor($r('app.color.background_color_accent'))
    .width('100%')
    .height('100%')
  }

  @Builder ImageWithText(src: string | PixelMap | Resource, tips: string, message?: string) {
    Column() {
      Image(src)
        .width(120)
          // TODO 暗色模式下变暗
//        .brightness(getTheme(this.currentMode).isDarkTheme ? 0.8 : 1)
        .aspectRatio(1)
        .objectFit(ImageFit.Contain)
      if (message) {
        Text(message)
          .fontSize(12)
          .constraintSize({ maxWidth: '80%' })
          .fontColor($r('app.color.color_text_minor'))
          .margin({ top: 12 })
          .fontWeight(FontWeight.Normal)
      }

      Text(tips)
        .fontSize(14)
        .fontColor('#817977')
        .textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: '80%' })
        .margin({ bottom: 100, top: 12 })

    }
    .onClick(() => {
      if (this.onRetry) {
        this.state = ViewState.LOADING
        this.onRetry()
      }
    })
  }
}