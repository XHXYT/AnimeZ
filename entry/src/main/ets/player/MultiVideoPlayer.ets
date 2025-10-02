import IPlayerManager from '../entity/VideoPlayer/IPlayerManager';
import { IjkVideoPlayer } from './IJK/IjkVideoPlayer';
import { SystemVideoPlayer } from './Video/SystemVideoPlayer';
import { AVideoPlayer } from './AVPlayer/AVideoPlayer';
import { AppConfigs } from '../entryability/Settings';


/**
 * 支持多种视频播放器切换
 */
@Component
export struct MultiVideoPlayer {

  // 应用设置
  @StorageLink('AppSettings') appSettings: AppConfigs = new AppConfigs()
  @Link playerManager: IPlayerManager

  aboutToAppear() {
    if (!this.playerManager) {
      throw new Error('You must set playerManager firstly!')
    }
  }

  build() {
    Stack() {
      if (this.appSettings.default_player === 0) {
        SystemVideoPlayer({ playerManager: this.playerManager })
      } else if (this.appSettings.default_player === 1) {
        IjkVideoPlayer({ playerManager: this.playerManager })
      } else {
        AVideoPlayer({ playerManager: this.playerManager })
      }
    }
    .width('100%')
  }
}