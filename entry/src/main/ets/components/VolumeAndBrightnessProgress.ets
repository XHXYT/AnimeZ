/**
 * @projectName:    AnimeZ 
 * @fileName:      VolumeAndBrightnessProgress
 * @author:     SummerKaze
 * @description:  音量和亮度进度条组件
 * @date:    2025/10/20 22:45
 * @version:    1.0
 */

@Component
export struct  VolumeAndBrightnessProgress {
  /** @description 是否是音量状态 */
  @Prop isVolume: boolean = true

  /** @description 音量 */
  @Prop volumeIcon: ResourceStr = $r('app.media.ic_volume')
  @Prop volumeMuteIcon: ResourceStr = $r('app.media.ic_volume_mute')
  @Prop volumeProgress: number = 0

  /** @description 亮度 */
  @Prop brightnessIcon: ResourceStr = $r('app.media.ic_lightbulb')
  @Prop brightnessLowIcon: ResourceStr = $r('app.media.ic_lightbulb_low')
  @Prop brightnessProgress: number = 0

  // TODO 设置主题色

  build() {
    Column({ space: 16 }) {
      Image(
        this.isVolume ?
         this.volumeProgress > 0 ? this.volumeIcon : this.volumeMuteIcon : // 音量
        this.brightnessProgress > 0 ? this.brightnessIcon : this.brightnessLowIcon // 亮度
      )
        .width(48)
        .aspectRatio(1)
        .fillColor(Color.White)

      Progress({ 
        value: this.isVolume ? this.volumeProgress : this.brightnessProgress, 
        total: 100,
        type: ProgressType.Linear 
      })
        .width('100%')
        .color($r('app.color.primary_color'))
    }
    .padding(16)
    .width(160)
    .backgroundColor('#cc000000')
    .borderRadius(16)
  }
}