import { ButtonBuilder } from "../common/Button";

@Component
export struct InputCustomDialog {

  @Prop title: string = ''
  @Prop textValue: string = ''
  @Prop placeholder: string = ''

  close: () => void = () => {}
  onValueChange: (value: string) => void = () => {}

  build() {
    Column({space: 13}) {
      Text(this.title).fontSize(20).margin({ top: 10, bottom: 10 })
      TextArea({ placeholder: this.placeholder, text: this.textValue })
        .width('90%')
        .id('textInput')
        .constraintSize({ minHeight: 36 })
        .backgroundColor($r('app.color.background_color'))
        .onChange((value: string) => {
          this.textValue = value
        })
      Row({space: 12}) {
        ButtonBuilder({
          config: {
            text: '取消',
            width: '50%',
            fontColor: $r('app.color.primary_color_accent'),
            type: ButtonType.Capsule,
            action: () => {
              this.close()
            }
          }
        })
        ButtonBuilder({
          config: {
            text: '确定',
            width: '50%',
            fontColor: $r('app.color.primary_color'),
            type: ButtonType.Capsule,
            action: () => {
              this.onValueChange(this.textValue)
              this.close()
            }
          }
        })
      }
    }
    .width(400)
    .padding(5)
    .borderRadius(32)
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor($r('app.color.start_window_background'))
    .onAppear(() => {
      // 设置指定组件id获得焦点
      try {
        this.getUIContext().getFocusController().requestFocus('textInput')
      } catch (error) {
        console.error(`弹窗输入框textInput获焦失败，message：${error.message}`)
      }
    })
  }
}