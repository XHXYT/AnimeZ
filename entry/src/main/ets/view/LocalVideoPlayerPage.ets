import IPlayerManager, { VideoFit } from '../player/model/IPlayerManager';
import PlayerManagerImpl from '../viewmodel/PlayerManagerImpl';
import EpisodeInfo from '../entity/EpisodeInfo';
import Logger from '../utils/Logger';
import { media } from '@kit.MediaKit';
import { MultiVideoPlayer } from '../player/MultiVideoPlayer';
import { AnimeState } from '../entryability/AnimeState';
import { PLAYER_SWITCH_EVENT } from '../utils/EventBus';
import emitter from '@ohos.events.emitter';

// 系统路由 - 本地视频播放界面
@Builder
export function LocalVideoPlayerPageBuilder(name: string, param: Object) {
  LocalVideoPlayerPage()
}

/**
 * 本地视频播放页面
 * TODO 目前用IjkPlayer、AVPlayer、RedPlayer播放本地m3u8视频，Video控件播放不了(？)本地缓存的m3u8
 */
@ComponentV2
struct LocalVideoPlayerPage {

  @Local isFullScreen: boolean = false
  @Local playerManager: IPlayerManager = new PlayerManagerImpl()
  /** 当前播放的本地视频 */
  private currentEpisode: EpisodeInfo | null = null

  aboutToAppear() {
    this.playerManager.addListener({
      onStatusChanged: (status: number) => {
      },
      onEpisodeChanged: (episodeList: EpisodeInfo[], episodeIndex: number) => {
      },
      onVideoSpeedChanged: (videoSpeed: number) => {
      },
      onVideoFitChanged: (videoFit: VideoFit) => {
      },
      onFullScreenChanged: (isFullScreen: boolean) => {
        // 处理全屏变化
        this.isFullScreen = isFullScreen
        // TODO 退出全屏时暂时直接退出
        if (!isFullScreen) {
          AnimeState.pageStack.pop(true)
        }
      },
      onVideoSizeChange: (w: number, h: number) => {
      },
      onProgressChange: (totalTime: number, currentTime: number) => {
      },
      onBuffering: (type, value) => {
      }
    })
    // 控制面板切换播放器后端：以当前进度重播当前视频
    PLAYER_SWITCH_EVENT.on((data: emitter.EventData) => {
      const resumePos = data.data ? data.data['resumePos'] as number : -1
      this.onPlayerSwitch(resumePos)
    })
    // TODO 暂时直接进入全屏模式
    this.playerManager.enterFullScreen()
  }

  /** 播放器后端切换：等待新播放器组件挂载注册后，以切换前进度重播 */
  private async onPlayerSwitch(resumePos: number) {
    if (!this.currentEpisode) {
      return
    }
    Logger.e('tips', `LocalVideoPlayerPage onPlayerSwitch resumePos=${resumePos}`)
    await new Promise<void>(resolve => setTimeout(resolve, 500))
    this.playerManager.playEpisodeList([this.currentEpisode], 0, resumePos > 0 ? resumePos : -1)
  }

  aboutToDisappear() {
    PLAYER_SWITCH_EVENT.off()
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
      this.currentEpisode = episode
      this.playerManager.playEpisodeList([episode], 0)
    })
  }

}
