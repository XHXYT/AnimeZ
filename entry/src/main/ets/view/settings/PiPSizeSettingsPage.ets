
import TitleBar from '../../components/TitleBar'
import { appSettings } from '../../entryability/Settings'
import { AnimeState } from '../../entryability/AnimeState'
import { PiPManager } from '../../player/PiPManager'
import { pipSizeLabel } from '../../entity/CusItemInfo'
import { VideoListColumnsCount } from '../../utils/breakpoint/BreakPoint'

// 系统路由
@Builder
export function PiPSizeSettingsPageBuilder(name: string, param: Object) {
  PiPSizeSettingsPage()
}

/** 骨架灰块颜色（半透明灰，深浅色模式下均呈现灰色骨架） */
const SKELETON_COLOR: string = '#66808080'

/**
 * 小窗默认尺寸设置页：四档滑块（较小/适中/较大/超大，默认适中），
 * 滑块下方预览区铺满剩余页面——主页同款卡片骨架网格（灰色，
 * 列数随断点、行数按剩余高度排满不溢出），叠加按档位缩放的小窗悬浮块，
 * 直观展示各档位小窗相对主页卡片的占比效果。
 */
@ComponentV2
struct PiPSizeSettingsPage {

  /** 当前选择的档位（预览实时联动，松手落盘） */
  @Local private currentLevel: number = appSettings.pip_default_size

  /** 预览区实测宽高（onAreaChange 测量，用于按剩余高度计算骨架行数） */
  @Local private previewW: number = 0
  @Local private previewH: number = 0

  /** 骨架网格列数（同主页视频列表：随窗口断点取列数） */
  private get gridColumns(): number {
    return VideoListColumnsCount(AnimeState.widthBp)
  }

  /** 骨架网格行索引：按预览区剩余高度排满一页（不溢出）；左右边距由外层内容区提供，与主页一致 */
  private get rowIndices(): number[] {
    const cols: number = this.gridColumns
    const cardW: number = (this.previewW - (cols - 1) * 8) / cols
    const cardH: number = cardW / 0.65
    const rows: number = Math.max(1, Math.floor((this.previewH - 32 + 8) / (cardH + 8)))
    const arr: number[] = []
    for (let i = 0; i < rows; i++) {
      arr.push(i)
    }
    return arr
  }

  /** 骨架网格列索引 */
  private get colIndices(): number[] {
    const arr: number[] = []
    for (let i = 0; i < this.gridColumns; i++) {
      arr.push(i)
    }
    return arr
  }

  /** 小窗悬浮块占预览区宽度的比例（整体放大一档） */
  private pipWidthPercent(): string {
    if (this.currentLevel <= 1) {
      return '44%'
    }
    if (this.currentLevel === 2) {
      return '56%'
    }
    if (this.currentLevel === 3) {
      return '68%'
    }
    return '80%'
  }

  /** 预览档位切换：动画过渡，不同档位间尺寸平滑连贯变化 */
  private setPreviewLevel(level: number): void {
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
      this.currentLevel = level
    })
  }

  /** 档位提交：写入配置并使缓存的 PiP 控制器失效，下次小窗按新档位创建 */
  private commitLevel(level: number): void {
    this.setPreviewLevel(level)
    if (appSettings.pip_default_size === level) {
      return
    }
    appSettings.pip_default_size = level
    PiPManager.invalidateController()
  }

  build() {
    NavDestination() {
      Column() {
        // 标题
        TitleBar({ title: '小窗默认尺寸' })
        // 内容
        Column() {
          // 滑块卡片
          Column() {
            Slider({ value: this.currentLevel, min: 1, max: 4, step: 1, style: SliderStyle.OutSet })
              .selectedColor($r('app.color.primary_color'))
              .trackColor($r('app.color.background_color_accent'))
              .blockColor($r('app.color.primary_color'))
              .showSteps(true)
              .width('100%')
              .onChange((value: number, mode: SliderChangeMode) => {
                const level: number = Math.round(value)
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                  // 松手/点击才落盘（避免拖动过程中反复持久化）
                  this.commitLevel(level)
                } else {
                  // 拖动过程仅联动预览（带过渡动画）
                  this.setPreviewLevel(level)
                }
              })
            Row() {
              Text('较小')
                .layoutWeight(1)
                .fontSize(12)
                .fontWeight(this.currentLevel === 1 ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.currentLevel === 1 ? $r('app.color.primary_color') : $r('sys.color.font_secondary'))
                .textAlign(TextAlign.Center)
              Text('适中')
                .layoutWeight(1)
                .fontSize(12)
                .fontWeight(this.currentLevel === 2 ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.currentLevel === 2 ? $r('app.color.primary_color') : $r('sys.color.font_secondary'))
                .textAlign(TextAlign.Center)
              Text('较大')
                .layoutWeight(1)
                .fontSize(12)
                .fontWeight(this.currentLevel === 3 ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.currentLevel === 3 ? $r('app.color.primary_color') : $r('sys.color.font_secondary'))
                .textAlign(TextAlign.Center)
              Text('超大')
                .layoutWeight(1)
                .fontSize(12)
                .fontWeight(this.currentLevel === 4 ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.currentLevel === 4 ? $r('app.color.primary_color') : $r('sys.color.font_secondary'))
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .margin({ top: 2 })
            Text(`当前档位：${pipSizeLabel(this.currentLevel)}，进入小窗后仍可拖拽调整窗口大小`)
              .fontSize(11)
              .fontColor($r('sys.color.font_tertiary'))
              .margin({ top: 8 })
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor($r('app.color.background_color'))

          // 预览区：主页同款卡片骨架网格 + 按档位缩放的小窗悬浮块
          Stack({ alignContent: Alignment.BottomEnd }) {
            // 主页卡片骨架网格（列数随断点，行数排满一页）
            Column({ space: 8 }) {
              ForEach(this.rowIndices, (rowIndex: number) => {
                Row({ space: 8 }) {
                  ForEach(this.colIndices, (colIndex: number) => {
                    this.SkeletonCard()
                  }, (colIndex: number) => `c_${colIndex}`)
                }
                .width('100%')
              }, (rowIndex: number) => `r_${rowIndex}`)
            }
            .width('100%')
            .height('100%')
            .padding({ top: 16, bottom: 16 })
            .clip(true)

            // 小窗悬浮块（按档位缩放）
            Column() {
              SymbolGlyph($r('sys.symbol.play_fill'))
                .fontSize(24)
                .fontColor([Color.White])
            }
            .width(this.pipWidthPercent())
            .aspectRatio(16 / 9)
            .borderRadius(12)
            .backgroundColor('#D9000000')
            .clip(true)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .shadow({ radius: 16, color: '#66000000', offsetX: 4, offsetY: 8 })
            .margin(12)
          }
          .layoutWeight(1)
          .width('100%')
          .margin({ top: 12 })
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            const w = newArea.width as number
            const h = newArea.height as number
            if (w > 0 && h > 0) {
              this.previewW = w
              this.previewH = h
            }
          })
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .padding({ top: AnimeState.topRectHeight, bottom: AnimeState.bottomRectHeight - 20 })
    }
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
  }

  /** 主页卡片骨架：灰色封面块 + 居中标题灰条（比例/圆角同主页卡片） */
  @Builder
  SkeletonCard() {
    Column() {
      // 封面骨架
      Column()
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(SKELETON_COLOR)
      // 标题骨架（双行居中灰条，占位同主页卡片标题区）
      Column({ space: 5 }) {
        Column()
          .width('86%')
          .height(9)
          .borderRadius(4)
          .backgroundColor(SKELETON_COLOR)
        Column()
          .width('52%')
          .height(9)
          .borderRadius(4)
          .backgroundColor(SKELETON_COLOR)
      }
      .width('100%')
      .height(40)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1)
    .aspectRatio(0.65)
    .borderRadius(12)
    .backgroundColor($r('app.color.background_color'))
    .clip(true)
  }
}
