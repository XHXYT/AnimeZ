import { ToastUtil } from '../../utils/ToastUtils';

/**
 * 通用可折叠节：标题行（色条随折叠竖直↔水平变形）+ 裁剪容器包裹的内容。
 * 折叠通过容器高度 0↔内容高度 动画实现，与色条变形在同一 animateTo 中同步；
 * title 为空串时为无名节：不渲染标题行、始终展开。
 */
@ComponentV2
export struct CollapsibleSection {

  /** 节标题；空串表示无名节（不渲染标题行、不可折叠） */
  @Param title: string = ''
  /** 标题行右侧自定义内容（排序开关、缓存全部等），默认为空 */
  @BuilderParam headerEnd: () => void = this.emptyBuilder
  /** 节内容 */
  @BuilderParam content: () => void = this.emptyBuilder

  /** 是否展开 */
  @Local expanded: boolean = true
  /** 内容自然高度（onAreaChange 测量），折叠动画的目标值；0 表示尚未测量（容器保持自适应） */
  @Local contentHeight: number = 0
  /** 折叠/展开动画进行中：容器高度被压缩，子内容测量值失真，期间不记录 */
  @Local collapsing: boolean = false

  private get collapsible(): boolean {
    return this.title != ''
  }

  @Builder emptyBuilder() {
  }

  build() {
    Column() {
      if (this.collapsible) {
        Row() {
          Row() {
            Row()
              .width(this.expanded ? 6 : 14)
              .height(this.expanded ? 14 : 6)
              .margin({ right: 2 })
              .borderRadius(4)
              .backgroundColor($r('app.color.primary_color'))
            Text(this.title)
              .fontColor($r('app.color.color_text_major'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
          }
          .layoutWeight(1)
          .onClick(() => {
            this.collapsing = true
            ToastUtil.animateTo({
              duration: 360,
              curve: Curve.ExtremeDeceleration,
              iterations: 1,
              playMode: PlayMode.Normal,
              onFinish: () => {
                this.collapsing = false
              }
            }, () => {
              this.expanded = !this.expanded
            })
          })
          this.headerEnd()
        }
        .padding({ left: 16, right: 16,  top: 16, bottom: 4 })
        .width('100%')
      }
      Column() {
        Column() {
          this.content()
        }
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          // 仅静止展开态记录：折叠态高度为 0 会把子内容压成 0 高，动画期间测量值随容器压缩失真
          if (this.expanded && !this.collapsing) {
            this.contentHeight = Number(newArea.height)
          }
        })
      }
      .clip(this.collapsible)
      // 未测量到高度前保持自适应，保证首帧内容自然布局并被测量；测量后 0↔contentHeight 动画
      .height(this.collapsible && this.contentHeight > 0 ? (this.expanded ? this.contentHeight : 0) : undefined)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
