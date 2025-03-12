import IPlayerManager, { VideoFit } from '../entity/VideoPlayer/IPlayerManager';
import PlayerManagerImpl from '../entity/VideoPlayer/PlayerManagerImpl';
import EpisodeInfo from '../entity/EpisodeInfo';
import { IjkVideoPlayer } from '../player/IJK/IjkVideoPlayer';
import Logger from '../utils/Logger';
import router from '@ohos.router';
import { media } from '@kit.MediaKit';

// 系统路由
@Builder
export function LocalVideoPlayerPageBuilder(name: string, param: Object) {
  LocalVideoPlayerPage()
}

/**
 * 本地视频播放页面
 * TODO 暂时只能用IjkPlayer播放本地m3u8视频，AVPlayer和Video控件目前播放不了本地缓存的m3u8
 */
@Component
struct LocalVideoPlayerPage {
  @State playerManager: IPlayerManager = new PlayerManagerImpl()

  aboutToAppear() {
    // 转换成Record类型，用来访问对象的属性
    let params = router.getParams() as Record<string, EpisodeInfo>
    let episode: EpisodeInfo = params.episode as EpisodeInfo
    Logger.e(this, 'aboutToAppear episode=' + JSON.stringify(episode))
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
        if (!isFullScreen) {
          // 退出全屏模式时关闭当前页面
          router.back()
        }
      },
      onVideoSizeChange: (w: number, h: number) => {
      },
      onProgressChange: (totalTime: number, currentTime: number) => {
      },
      onBuffering: (type, value) => {
      }
    })

    // 直接进入全屏模式
    this.playerManager.enterFullScreen()

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
  }

  aboutToDisappear() {
    this.playerManager.exitFullScreen()
    this.playerManager.destroy()
  }

  build() {
    Stack() {
      IjkVideoPlayer({ playerManager: $playerManager })
    }
    .backgroundColor($r('app.color.background_color_accent'))
    .height('100%')
    .width('100%')
  }
}