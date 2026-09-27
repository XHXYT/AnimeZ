import IPlayerManager, { PlayerListener, VideoFit } from '../player/model/IPlayerManager';
import PlayerManagerImpl from '../viewmodel/PlayerManagerImpl';
import EpisodeInfo from '../entity/EpisodeInfo';
import Logger from '../utils/Logger';
import M3U8Utils from '../utils/m3u8/M3U8Utils';
import { ToastUtil } from '../utils/ToastUtils';
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
 * 目前用IjkPlayer、AVPlayer、RedPlayer播放本地m3u8视频，Video控件播放不了本地缓存的 m3u8
 */
@ComponentV2
struct LocalVideoPlayerPage {

  @Local isFullScreen: boolean = false
  @Local playerManager: IPlayerManager = new PlayerManagerImpl()
  /** 当前播放的本地视频 */
  private currentEpisode: EpisodeInfo | null = null

  /** 页面级播放器监听：系统返回 pop 页面时先移除，避免销毁期的全屏回调再次 pop（双重回退） */
  private readonly pageListener: PlayerListener = {
    onStatusChanged: (status: number) => {
    },
    onEpisodeChanged: (episodeList: EpisodeInfo[], episodeIndex: number) => {
    },
    onVideoSpeedChanged: (videoSpeed: number) => {
    },
    onVideoFitChanged: (videoFit: VideoFit) => {
    },
    onFullScreenChanged: (isFullScreen: boolean) => {
      // 处理全屏变化（仅响应 true→false 转换，防止注册期误触发导致页面刚 push 即被 pop）
      const wasFullScreen = this.isFullScreen
      this.isFullScreen = isFullScreen
      // TODO 退出全屏时暂时直接退出
      if (wasFullScreen && !isFullScreen) {
        AnimeState.pageStack.pop(true)
      }
    },
    onVideoSizeChange: (w: number, h: number) => {
    },
    onProgressChange: (totalTime: number, currentTime: number) => {
    },
    onBuffering: (type, value) => {
    }
  }

  aboutToAppear() {
    this.playerManager.addListener(this.pageListener)
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
    // 先移除页面监听：系统返回 pop 页面时，exitFullScreen 的异步回调
    // 仍会触发 onFullScreenChanged(false)，若监听未移除会再次 pop 导致双重回退
    this.playerManager.removeListener(this.pageListener)
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
    .onReady(async (value) => {
      // 转换成Record类型，用来访问对象的属性
      let params = value.pathInfo.param as Record<string, EpisodeInfo>
      let episode: EpisodeInfo | undefined = params ? params.episode : undefined
      Logger.e('tips', 'aboutToAppear episode=' + JSON.stringify(episode))
      // 参数缺失或不完整时不能播放，直接退出避免播放器崩溃
      if (!episode || !episode.videoUrl) {
        Logger.e('fail', 'LocalVideoPlayerPage invalid episode param: ' + JSON.stringify(value.pathInfo.param))
        ToastUtil.showToast({ message: '视频信息无效，无法播放' })
        AnimeState.pageStack.pop(true)
        return
      }
      // 本地m3u8：AVPlayer等后端不支持播放本地HLS，单分片未加密时直接播放分片媒体文件
      const mediaFile = await M3U8Utils.resolveLocalPlayableFile(episode.videoUrl as string)
      if (mediaFile) {
        Logger.e('tips', 'LocalVideoPlayerPage play local media file: ' + mediaFile)
        const localEpisode: EpisodeInfo = {
          title: episode.title,
          desc: episode.desc,
          link: episode.link,
          videoUrl: mediaFile
        }
        this.currentEpisode = localEpisode
        this.playerManager.playEpisodeList([localEpisode], 0)
        return
      }
      this.currentEpisode = episode
      this.playerManager.playEpisodeList([episode], 0)
    })
  }

}
