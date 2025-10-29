import IPlayerManager from './model/IPlayerManager';
import { IjkVideoPlayer } from './IJK/IjkVideoPlayer';
import { SystemVideoPlayer } from './Video/SystemVideoPlayer';
import { AVideoPlayer } from './AVPlayer/AVideoPlayer';
import { AppConfigs } from '../entryability/Settings';
import { RedVideoPlayer } from './REDPlayer/RedPlayer';
import { AbilityConstant, common } from '@kit.AbilityKit';


/**
 * 支持多种视频播放器切换
 */
@Component
export struct MultiVideoPlayer {

  // 应用设置
  @StorageLink('AppSettings') appSettings: AppConfigs = new AppConfigs()
  @Link playerManager: IPlayerManager
  @Link isFullScreen: boolean

  aboutToAppear() {
    if (!this.playerManager) {
      throw new Error('You must set playerManager firstly!')
    }

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
      if (this.appSettings.default_player === 'video') {
        // 系统Video组件
        SystemVideoPlayer({ playerManager: this.playerManager })
      } else if (this.appSettings.default_player === 'av') {
        // AVPlayer
        AVideoPlayer({ playerManager: this.playerManager })
      } else if (this.appSettings.default_player === 'red') {
        // 红薯播放器
        RedVideoPlayer({ playerManager: this.playerManager })
      } else {
        // IJK播放器
        IjkVideoPlayer({ playerManager: this.playerManager })
      }
    }
    .height(this.isFullScreen ? '100%' : undefined)
    .width('100%')
  }
}