import IPlayerManager from '../entity/VideoPlayer/IPlayerManager';
import { IjkVideoPlayer } from './IJK/IjkVideoPlayer';
import { SystemVideoPlayer } from './Video/SystemVideoPlayer';
import { AVideoPlayer } from './AVPlayer/AVideoPlayer';
import Settings from '../utils/Settings';


/**
 * 支持多种视频播放器切换
 */
@Component
export struct MultiVideoPlayer {
  // 播放器
  @State playerType: number = 0
  @Link playerManager: IPlayerManager

  aboutToAppear() {
    if (!this.playerManager) {
      throw new Error('You must set playerManager firstly!')
    }
    this.playerType = Settings.getDefaultPlayerType()
  }

  build() {
    Stack() {
      if (this.playerType === 0) {
        SystemVideoPlayer({ playerManager: this.playerManager })
      } else if (this.playerType === 1) {
        IjkVideoPlayer({ playerManager: this.playerManager })
      } else {
        AVideoPlayer({ playerManager: this.playerManager })
      }
    }
    .width('100%')
  }
}