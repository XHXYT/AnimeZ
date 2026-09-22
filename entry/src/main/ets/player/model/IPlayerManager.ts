import media from '@ohos.multimedia.media';
import { IPlayer } from './IPlayer';
import EpisodeInfo from '../../entity/EpisodeInfo';

export enum PlayerStatus {
  IDLE = 0, // 加载中
  INITIALIZED = 1,
  PREPARED = 2,
  PLAY = 4,
  PAUSE = 5,
  STOP = 6,
  ERROR = 7,
  DONE = 8
}

export enum VideoFit {
  Contain,
  Cover,
  Fill,
  Fit_16_9,
  Fit_4_3,
  Fit_1_1,
}

export interface PlayerListener {

  onStatusChanged: (status: number) => void

//  onEpisodeChanged: (episode: EpisodeInfo) => void

  onEpisodeChanged: (episodeList: EpisodeInfo[], episodeIndex: number) => void

  onVideoSpeedChanged: (videoSpeed: number) => void

  onFullScreenChanged: (isFullScreen: boolean) => void

  onVideoFitChanged: (videoFit: VideoFit) => void

  onVideoSizeChange: (w: number, h: number) => void

  onProgressChange: (totalTime: number, currentTime: number) => void

  onBuffering: (type: media.BufferingInfoType, value: number) => void

}

export default interface IPlayerManager {

  init: (player: IPlayer) => void

  //  setEpisode: (episode: EpisodeInfo) => void

  //  playEpisode: (episode: EpisodeInfo) => Promise<void>

  //  getEpisode: () => EpisodeInfo

  //   getEpisodeList: () => EpisodeInfo[]

  playEpisodeList: (episodeList: EpisodeInfo[], episodeIndex?: number, startPos?: number) => Promise<void>

  /** 仅切换集数并通知监听者，不直接播放（由 ViewModel 监听后统一驱动播放） */
  selectEpisode: (index: number) => void

  //  playEpisodeAt: (episodeIndex: number) => Promise<void>

  //  setPlayerUrl: (url: string) => void

  start: () => Promise<void>

  pause: () => Promise<void>

  stop: () => Promise<void>

  seekTo: (value: number) => Promise<void>

  /** 设置播放倍速（实际倍率数值，如 0.75 / 1.0 / 2.0 / 3.0） */
  setSpeed: (speed: number) => Promise<void>

  /** 获取当前播放倍速（实际倍率数值） */
  getSpeed: () => number

  isPlaying: () => boolean

  setVideoFit: (videoFit: VideoFit) => void

  setStatus: (status: PlayerStatus) => void

  getStatus: () => PlayerStatus

  isPrepared: () => boolean;

  getDuration: () => number;

  getCurrentPosition: () => number;

  addListener: (listener: PlayerListener) => void

  removeListener: (listener: PlayerListener) => void

  destroy: () => void

  isFullScreen: () => boolean

  enterFullScreen: (sensorDriven?: boolean) => void

  exitFullScreen: () => void

  onVideoSizeChanged: (width: number, height: number) => void

  notifyDuration: (duration: number) => void

  notifyCurrentTime: (currentTime: number) => void

  notifyTime: (duration: number, currentTime: number) => void

  notifyBuffering: (type: media.BufferingInfoType, value: number) => void

  /** 底层播放器 seek 完成回调（AVPlayer seekDone / IJK onSeekComplete），用于关闭 seek 加载圈 */
  notifySeekDone: () => void

}


