import { DanmakuViewV2 } from '@ohos/danmakuflamemaster'
import { DanmakuController } from './DanmakuController'

/**
 * 弹幕渲染层：包裹 DanmakuViewV2（TEXTURE 高性能模式），负责尺寸同步
 * 挂在 VideoPlayerController 根 Stack 最底层：视频之上、控制层之下
 */
@ComponentV2
export struct DanmakuLayer {
  @Require @Param controller: DanmakuController

  build() {
    Stack() {
      DanmakuViewV2({ model: this.controller.model })
    }
    .width('100%')
    .height('100%')
    .onAppear(() => {
      this.controller.onViewMounted()
    })
    .onDisAppear(() => {
      this.controller.onViewUnmounted()
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const w = newArea.width as number
      const h = newArea.height as number
      if (w > 0 && h > 0) {
        const uiContext = this.getUIContext()
        this.controller.model.setWidth(uiContext.vp2px(w))
        this.controller.model.setHeight(uiContext.vp2px(h))
        this.controller.onViewportChanged()
      }
    })
  }
}
