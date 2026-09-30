import { ToastUtil } from '../../utils/ToastUtils';

/**
 * 通用可折叠节：标题行（色条随折叠竖直↔水平变形）+ 裁剪容器包裹的内容。
 * 折叠通过容器高度 0↔内容高度 动画实现，与色条变形在同一 animateTo 中同步；
 * 静止展开态容器高度自适应（不钳制内部测量，支持嵌套节与内容增长），仅动画期间定高。
 * title 为空串时为无名节：不渲染标题行、始终展开。
 */
@ComponentV2
export struct CollapsibleSection {

  /** 节标题；空串表示无名节（不渲染标题行、不可折叠） */
  @Param title: string = ''
  /** 标题行内边距；嵌入自带边距的容器（如源编辑页）时可覆盖以对齐内容 */
  @Param titlePadding: Padding = { left: 16, right: 16, top: 16, bottom: 4 }
  /** 标题行右侧自定义内容（排序开关、缓存全部等），默认为空 */
  @BuilderParam headerEnd: () => void = this.emptyBuilder
  /** 节内容 */
  @BuilderParam content: () => void = this.emptyBuilder

  /** 是否展开 */
  @Local expanded: boolean = true
  /** 内容自然高度（onAreaChange 测量），折叠/展开动画的目标值；静止展开态不使用（容器自适应） */
  @Local contentHeight: number = 0
  /** 折叠/展开动画进行中：容器高度被固定，子内容测量值失真，期间不记录 */
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
            if (this.expanded) {
              // 折叠：静止展开态高度为自适应（无数值起点无法动画），先用 1ms 动画把高度钉到测量值
              // （视觉无变化），该帧渲染完成后再启动真正的收缩动画
              ToastUtil.animateTo({
                duration: 1,
                onFinish: () => {
                  ToastUtil.animateTo({
                    duration: 360,
                    curve: Curve.ExtremeDeceleration,
                    iterations: 1,
                    playMode: PlayMode.Normal,
                    onFinish: () => {
                      if (!this.expanded) {
                        this.collapsing = false
                      }
                    }
                  }, () => {
                    this.expanded = false
                  })
                }
              }, () => {
                this.collapsing = true
              })
            } else {
              // 展开：当前高度为定值 0，直接动画到测量值；结束后恢复自适应以容纳内容增长
              ToastUtil.animateTo({
                duration: 360,
                curve: Curve.ExtremeDeceleration,
                iterations: 1,
                playMode: PlayMode.Normal,
                onFinish: () => {
                  if (this.expanded) {
                    this.collapsing = false
                  }
                }
              }, () => {
                this.collapsing = true
                this.expanded = true
              })
            }
          })
          this.headerEnd()
        }
        .padding(this.titlePadding)
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
      // 静止展开态高度自适应：不钳制内部测量，嵌套节展开/节内内容增长（更多字段、加卡片）都能生效；
      // 仅动画进行中（collapsing）固定为测量值，折叠态为 0
      .height(this.collapsible ? (this.expanded ? (this.collapsing ? this.contentHeight : undefined) : 0) : undefined)
      // 折叠态内容仍占布局且可命中（clip 只裁渲染不裁命中测试），隐形内容会拦截下方触摸，须禁用命中
      .hitTestBehavior(this.collapsible && !this.expanded ? HitTestMode.None : HitTestMode.Default)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
