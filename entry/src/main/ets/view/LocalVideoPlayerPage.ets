import IPlayerManager, { VideoFit } from '../player/model/IPlayerManager';
import PlayerManagerImpl from '../viewmodel/PlayerManagerImpl';
import EpisodeInfo from '../entity/EpisodeInfo';
import { IjkVideoPlayer } from '../player/IJK/IjkVideoPlayer';
import Logger from '../utils/Logger';
import router from '@ohos.router';
import { media } from '@kit.MediaKit';
import { MultiVideoPlayer } from '../player/MultiVideoPlayer';

// 系统路由 - 本地视频播放界面
@Builder
export function LocalVideoPlayerPageBuilder(name: string, param: Object) {
  LocalVideoPlayerPage()
}

/**
 * 本地视频播放页面
 * TODO 目前用IjkPlayer、AVPlayer、RedPlayer播放本地m3u8视频，Video控件播放不了(？)本地缓存的m3u8
 */
@Component
struct LocalVideoPlayerPage {

  @State isFullScreen: boolean = false
  @Consume('pageStack') pageStack: NavPathStack
  @State playerManager: IPlayerManager = new PlayerManagerImpl()

  aboutToAppear() {
    this.playerManager.addListener({
      onStatusChanged: (status: number) => {
      },
      onEpisodeChanged: (episodeList: EpisodeInfo[], episodeIndex: number) => {
      },
      onVideoSpeedChanged: (videoSpeed: media.PlaybackSpeed) => {
      },
      onVideoFitChanged: (videoFit: VideoFit) => {
      },
      onFullScreenChanged: (isFullScreen: boolean) => {
        // 处理全屏变化
        this.isFullScreen = isFullScreen
        // TODO 退出全屏时暂时直接退出
        if (!isFullScreen) {
          this.pageStack.pop(true)
        }
      },
      onVideoSizeChange: (w: number, h: number) => {
      },
      onProgressChange: (totalTime: number, currentTime: number) => {
      },
      onBuffering: (type, value) => {
      }
    })
    // TODO 暂时直接进入全屏模式
    this.playerManager.enterFullScreen()
  }

  aboutToDisappear() {
    this.playerManager.exitFullScreen()
    this.playerManager.destroy()
  }

  build() {
    NavDestination() {
      Stack() {
        MultiVideoPlayer({ playerManager: this.playerManager, isFullScreen: this.isFullScreen })
      }
      .height('100%')
      .width('100%')
    }
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
    .onReady((value) => {
      // 转换成Record类型，用来访问对象的属性
      let params = value.pathInfo.param as Record<string, EpisodeInfo>
      let episode: EpisodeInfo = params.episode as EpisodeInfo
      Logger.e('tips', 'aboutToAppear episode=' + JSON.stringify(episode))
      // TODO 本地文件转fd://
      //    if (episode.videoUrl && episode.videoUrl.startsWith('/')) {
      //      // 本地视频文件
      //      fs.open(episode.videoUrl, fs.OpenMode.READ_ONLY, (err, file) => {
      //        if (err) {
      //          this.playerManager.setStatus(PlayerStatus.ERROR)
      //        } else {
      //          episode.videoUrl = 'fd://' + file.fd
      //          Logger.e(this, 'open local video, uri=' + episode.videoUrl)
      //          this.playerManager.playEpisode(episode)
      //        }
      //      });
      //    } else {
      //      this.playerManager.playEpisode(episode)
      //    }
      this.playerManager.playEpisodeList([episode], 0)
    })
  }

}