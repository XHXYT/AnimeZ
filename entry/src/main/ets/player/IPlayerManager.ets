import media from '@ohos.multimedia.media';
import { IPlayer } from './IPlayer';
import EpisodeInfo from '../entity/EpisodeInfo';

export enum PlayerStatus {
  IDLE = 0,
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

// TODO 优化监听回调，改为on('xxxx', (x) => void)
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

  init(player: IPlayer): void

//  setEpisode(episode: EpisodeInfo): void

//  playEpisode(episode: EpisodeInfo): Promise<void>

//  getEpisode(): EpisodeInfo

//  getEpisodeList(): EpisodeInfo[]

  playEpisodeList(episodeList: EpisodeInfo[], episodeIndex?: number): Promise<void>

//  playEpisodeAt(episodeIndex: number): Promise<void>

//  setPlayerUrl(url: string): void

  start(): Promise<void>

  pause(): Promise<void>

  stop(): Promise<void>

  seekTo(value: string): Promise<void>

  setSpeed(speed: media.PlaybackSpeed): Promise<void>

  getSpeed(): media.PlaybackSpeed

  isPlaying(): boolean

  setVideoFit(videoFit: VideoFit): void

  setStatus(status: PlayerStatus): void

  getStatus(): PlayerStatus

  isPrepared(): boolean

  getDuration(): number

  getCurrentPosition(): number

  addListener(listener: PlayerListener): void

  removeListener(listener: PlayerListener): void

  destroy(): void

  isFullScreen(): boolean

  enterFullScreen(): void

  exitFullScreen(): void

  onVideoSizeChanged(width: number, height: number): void

  notifyDuration(duration: number): void

  notifyCurrentTime(currentTime: number): void

  notifyDuration(duration: number): void

  notifyTime(duration: number, currentTime: number): void

  notifyBuffering(type: media.BufferingInfoType, value: number): void

}

// IPlayerManager空对象
export class NullPlayerManager implements IPlayerManager {
  init(player: IPlayer): void {}
  playEpisodeList(episodeList: EpisodeInfo[], episodeIndex?: number): Promise<void> {
    return Promise.resolve();
  }
  start(): Promise<void> {
    return Promise.resolve();
  }
  pause(): Promise<void> {
    return Promise.resolve();
  }
  stop(): Promise<void> {
    return Promise.resolve();
  }
  seekTo(value: string): Promise<void> {
    return Promise.resolve();
  }
  setSpeed(speed: media.PlaybackSpeed): Promise<void> {
    return Promise.resolve();
  }
  getSpeed(): media.PlaybackSpeed {
    return {} as media.PlaybackSpeed;
  }
  isPlaying(): boolean {
    return false;
  }
  setVideoFit(videoFit: VideoFit): void {}
  setStatus(status: PlayerStatus): void {}
  getStatus(): PlayerStatus {
    return PlayerStatus.IDLE;
  }
  isPrepared(): boolean {
    return false;
  }
  getDuration(): number {
    return 0;
  }
  getCurrentPosition(): number {
    return 0;
  }
  addListener(listener: PlayerListener): void {}
  removeListener(listener: PlayerListener): void {}
  destroy(): void {}
  isFullScreen(): boolean {
    return false;
  }
  enterFullScreen(): void {}
  exitFullScreen(): void {}
  onVideoSizeChanged(width: number, height: number): void {}
  notifyDuration(duration: number): void {}
  notifyCurrentTime(currentTime: number): void {}
  notifyTime(duration: number, currentTime: number): void {}
  notifyBuffering(type: media.BufferingInfoType, value: number): void {}
}

