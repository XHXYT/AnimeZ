import { DEFAULT_DURATION } from "../utils/TransitionHelper";


/**
 * 通用面板
 */
@ComponentV2
export default struct CustomPanel {
  @Local showPanelInner: boolean = false
  @Local translateY: number = 0
  @Local panelOpacity: number = 0
  @Local panelHeight: number = 0
  @BuilderParam panelContent: () => void
  @Require @Param controller: PanelController

  aboutToAppear() {
    if (this.controller) {
      this.controller.setListener((show) => {
        this.onShowPanelChanged(show)
      })
    } else {
      throw new Error('You must set controller first!')
    }
  }

  build() {
    Stack() {
      if (this.showPanelInner) {
        Column()
          .backgroundColor('#80000000')
          .width('100%')
          .height('100%')
          .opacity(this.panelOpacity)
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close()
            }
          })
        Stack() {
          this.panelContent()
        }
        .translate({ y: this.translateY })
        .width('100%')
        .height('100%')
        .onClick(() => {})
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.showPanelInner ? HitTestMode.Default : HitTestMode.None)
    .onAreaChange((_, newArea) => {
      this.panelHeight = parseInt(newArea.height.toString())
      if (this.showPanelInner) {
        this.translateY = 0
      } else {
        this.translateY = this.panelHeight
      }
    })
    .onClick(() => {
      if (this.controller !== undefined) {
        this.controller.close()
      }
    })
  }

  onShowPanelChanged(show: boolean) {
    if (show) {
      if (!this.showPanelInner) {
        this.showPanelInner = true

        setTimeout(() => {
          animateTo({
            duration: DEFAULT_DURATION,
            curve: Curve.ExtremeDeceleration,
            iterations: 1,
            playMode: PlayMode.Normal
          }, () => {
            this.translateY = 0
            this.panelOpacity = 1
          })
        }, 10)
      }
    } else {
      if (this.showPanelInner) {
        animateTo({
          duration: DEFAULT_DURATION,
          curve: Curve.ExtremeDeceleration,
          iterations: 1,
          playMode: PlayMode.Normal,
          onFinish: () => {
            this.showPanelInner = false
          }
        }, () => {
          this.translateY = this.panelHeight
          this.panelOpacity = 0
        })
      }
    }
  }

}

/**面板控制器*/
export class PanelController {

  private listener: (show: boolean) => void = () => {}
  private toShow: boolean = false

  setListener(listener: (show: boolean) => void) {
    this.listener = listener
  }

  isShow() {
    return this.toShow;
  }

  close() {
    this.toShow = false
    if (this.listener) {
      this.listener(false)
    }
  }

  show() {
    this.toShow = true
    if (this.listener) {
      this.listener(true)
    }
  }

}
