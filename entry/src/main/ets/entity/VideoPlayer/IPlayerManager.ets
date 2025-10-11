import media from '@ohos.multimedia.media';
import { IPlayer } from './IPlayer';
import EpisodeInfo from '../EpisodeInfo';

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

  onVideoSpeedChanged: (videoSpeed: media.PlaybackSpeed) => void

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

  playEpisodeList: (episodeList: EpisodeInfo[], episodeIndex?: number) => Promise<void>

  //  playEpisodeAt: (episodeIndex: number) => Promise<void>

  //  setPlayerUrl: (url: string) => void

  start: () => Promise<void>

  pause: () => Promise<void>

  stop: () => Promise<void>

  seekTo: (value: number) => Promise<void>

  setSpeed: (speed: media.PlaybackSpeed) => Promise<void>

  getSpeed: () => media.PlaybackSpeed

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

  enterFullScreen: () => void

  exitFullScreen: () => void

  onVideoSizeChanged: (width: number, height: number) => void

  notifyDuration: (duration: number) => void

  notifyCurrentTime: (currentTime: number) => void

  notifyTime: (duration: number, currentTime: number) => void

  notifyBuffering: (type: media.BufferingInfoType, value: number) => void

}


