import IPlayerManager from './model/IPlayerManager';
import { IjkVideoPlayer } from './IJK/IjkVideoPlayer';
import { SystemVideoPlayer } from './Video/SystemVideoPlayer';
import { AVideoPlayer } from './AVPlayer/AVideoPlayer';
import { appSettings } from '../entryability/Settings';
import { RedVideoPlayer } from './REDPlayer/RedPlayer';
import { MpvVideoPlayer } from './MPV/MpvVideoPlayer';
import { AbilityConstant, common } from '@kit.AbilityKit';


/**
 * 支持多种视频播放器切换
 */
@ComponentV2
export struct MultiVideoPlayer {

  @Require @Param playerManager: IPlayerManager
  @Require @Param isFullScreen: boolean
  /** 播放器区域为全高（左右分栏等）时撑满容器，控制层可利用上下黑边空间 */
  @Param fillHeight: boolean = false

  aboutToAppear() {
    // 开启应用接续 -> 在播放的页面才打开
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    context.setMissionContinueState(AbilityConstant.ContinueState.ACTIVE, (result) => {
      console.log(`setMissionContinueState: ${JSON.stringify(result)}`)
    })
  }

  aboutToDisappear(): void {
    // 关闭应用接续
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    context.setMissionContinueState(AbilityConstant.ContinueState.INACTIVE, (result) => {
      console.log(`setMissionContinueState: ${JSON.stringify(result)}`)
    })
  }

  build() {
    Stack() {
      if (appSettings.default_player === 'video') {
        // 系统Video组件
        SystemVideoPlayer({ playerManager: this.playerManager, fillHeight: this.fillHeight })
      } else if (appSettings.default_player === 'av') {
        // AVPlayer
        AVideoPlayer({ playerManager: this.playerManager, fillHeight: this.fillHeight })
      } else if (appSettings.default_player === 'red') {
        // 红薯播放器
        RedVideoPlayer({ playerManager: this.playerManager, fillHeight: this.fillHeight })
      } else if (appSettings.default_player === 'mpv') {
        // MPV播放器
        MpvVideoPlayer({ playerManager: this.playerManager, fillHeight: this.fillHeight })
      } else {
        // IJK播放器
        IjkVideoPlayer({ playerManager: this.playerManager, fillHeight: this.fillHeight })
      }
    }
    .height(this.isFullScreen || this.fillHeight ? '100%' : undefined)
    .width('100%')
  }
}
