import IPlayerManager, { NullPlayerManager } from './IPlayerManager';
import { IjkVideoPlayer } from './IjkVideoPlayer';
import { SystemVideoPlayer } from './SystemVideoPlayer';
import { AVideoPlayer } from './AVideoPlayer';
import Settings from '../utils/Settings';


/**
 * 支持多种视频播放器切换
 */
@Component
export struct MultiVideoPlayer {
  @State playerType: number = 0
  @State playerManager: IPlayerManager = new NullPlayerManager()

  aboutToAppear() {
    if (!this.playerManager) {
      throw new Error('You must set playerManager firstly!')
    }
    this.playerType = Settings.getDefaultPlayerType()
  }

  build() {
    Stack() {
      if (this.playerType == 1) {
        SystemVideoPlayer({ playerManager: this.playerManager })
      } else if (this.playerType == 2) {
        IjkVideoPlayer({ playerManager: this.playerManager })
      } else {
        AVideoPlayer({ playerManager: this.playerManager })
      }
    }
    .width('100%')
  }
}