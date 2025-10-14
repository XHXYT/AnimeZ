import { media } from "@kit.MediaKit"
import Logger from "../../utils/Logger";
import { IPlayer } from '../model/IPlayer';
import IPlayerManager, { PlayerStatus } from "../model/IPlayerManager";
import { BusinessError } from "@kit.BasicServicesKit";

/**
 * 封装media.AVPlayer
 */
export class AVPlayerWrapper {
  private readonly avPlayer: media.AVPlayer
  private surfaceId: string = ''
  private playUrl: string = ''

  constructor(avPlayer: media.AVPlayer) {
    this.avPlayer = avPlayer
  }

  async init(manager: IPlayerManager, surfaceId: string): Promise<void> {
    this.surfaceId = surfaceId
    this.bindState(this.avPlayer, manager)
    manager.init(this.getPlayer())
  }

  private getPlayer(): IPlayer {
    const thePlayer: IPlayer = {
      setDataSource: async (urlOrFd: string | media.AVFileDescriptor) => {
        try {
          // 处理本地文件描述符
          if (typeof urlOrFd !== 'string') {
            const fdUrl = `fd://${urlOrFd.fd}?offset=${urlOrFd.offset}&size=${urlOrFd.length}`;
            this.avPlayer.url = fdUrl;
            Logger.e('tips', 'setDataSource from FD: ' + fdUrl);
            return;
          }
          // 网络视频，统一使用 avPlayer.url
          Logger.d('setDataSource from URL (Official Way): ' + urlOrFd);
          this.playUrl = urlOrFd
          this.avPlayer.url = urlOrFd;
        } catch (error) {
          Logger.e('fail', 'set data source with MediaSource ', error);
          // 抛出错误
          throw error as Error;
        }
      },
      start: async () => {
        Logger.e('tips', 'setDataSource start')
        return this.avPlayer.play().catch(() => {
          console.log(`AVPlayer 视频播放失败`)
        })
      },
      prepare: async () => {
        // this.controller.prepareAsync()
        Logger.e('tips', 'setDataSource prepare (Clean Version)')
        try {
          // prepare 操作
          await this.avPlayer.prepare();
          console.warn('提示：', 'AVPlayer prepare succeeded.');
        } catch (err) {
          Logger.e('fail', `AVPlayer 视频第一次准备`, err)
          if ((err as BusinessError).code === 5411003) {
            Logger.w('warn', '检测到网络策略错误，尝试降级...');
            // 尝试重置并使用更简单的配置
            await this.avPlayer.reset();
            this.avPlayer.url = this.playUrl
          } else {
            throw err; // 其他错误继续抛出
          }
        }
      },
      pause: async () => {
        Logger.e('tips', 'setDataSource pause')
        return this.avPlayer.pause().catch(() => {
          console.log(`AVPlayer 视频暂停失败`)
        })
      },
      stop: async () => {
        Logger.e('tips', 'setDataSource stop')
        return this.avPlayer.stop().catch(() => {
          console.log(`AVPlayer 视频停止失败`)
        })
      },
      reset: async () => {
        Logger.e('tips', 'setDataSource reset')
        return this.avPlayer.reset().catch(() => {
          console.log(`AVPlayer 视频重置失败`)
        })
      },
      release: async () => {
        Logger.e('tips', 'setDataSource release')
        return this.avPlayer.release().catch(() => {
          console.log(`AVPlayer 资源释放失败`)
        })
      },
      seekTo: async (value: number) => {
        Logger.e('tips', 'setDataSource seekTo value=' + value)
        return this.avPlayer.seek(value as number)
      },
      setSpeed: (speed: media.PlaybackSpeed): Promise<void> => {
        return this.setSpeed(speed);
      }
    }
    return thePlayer
  }

  async setSpeed(speed: media.PlaybackSpeed) {
    let avSpeed: media.PlaybackSpeed
    switch (speed) {
      case media.PlaybackSpeed.SPEED_FORWARD_0_75_X:
        avSpeed = media.PlaybackSpeed.SPEED_FORWARD_0_75_X
        break
      case media.PlaybackSpeed.SPEED_FORWARD_1_25_X:
        avSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_25_X
        break
      case media.PlaybackSpeed.SPEED_FORWARD_1_75_X:
        avSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_75_X
        break
      case media.PlaybackSpeed.SPEED_FORWARD_2_00_X:
        avSpeed = media.PlaybackSpeed.SPEED_FORWARD_2_00_X
        break
      case media.PlaybackSpeed.SPEED_FORWARD_1_00_X:
      default:
        avSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X
        break
    }
    return this.avPlayer.setSpeed(avSpeed)
  }

  private bindState(avPlayer: media.AVPlayer, manager: IPlayerManager) {
    avPlayer.on('stateChange', async (state: media.AVPlayerState) => {
      Logger.e('tips', 'AVPlayer stateChange state = ' + state)
      switch (state) {
        case 'idle':
          break;
        case 'initialized':
          if (!avPlayer.surfaceId) {
            avPlayer.surfaceId = this.surfaceId;
          }
          if (!avPlayer.surfaceId) {
            avPlayer.surfaceId = this.surfaceId;
          }
          // 在 initialized 回调设置最小化的播放策略
          try {
            await avPlayer.setPlaybackStrategy({
              preferredBufferDurationForPlaying: 0.3,
              preferredBufferDuration: 20,
            });
            console.log('提示：', 'Minimal PlaybackStrategy set successfully in stateChange.');
          } catch (error) {
            Logger.e('fail', 'Failed to set PlaybackStrategy in stateChange: ', error);
            // 不抛出错误，让播放器尝试不带策略继续
          }
          manager.setStatus(PlayerStatus.INITIALIZED)
          break;
        case 'prepared':
          avPlayer.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_FIT;
          manager.setStatus(PlayerStatus.PREPARED)
          break;
        case 'playing':
          manager.setStatus(PlayerStatus.PLAY)
          break;
        case 'paused':
          manager.setStatus(PlayerStatus.PAUSE)
          break;
        case 'completed':
          manager.setStatus(PlayerStatus.DONE)
          break;
        case 'stopped':
          manager.setStatus(PlayerStatus.STOP)
          break;
        case 'released':
          manager.setStatus(PlayerStatus.IDLE)
          break;
        case 'error':
          manager.setStatus(PlayerStatus.ERROR)
          break;
        default:
          break;
      }
    });
    avPlayer.on('timeUpdate', (time: number) => {
      Logger.e('tips', 'AVPlayer timeUpdate time = ' + time)
      manager.notifyCurrentTime(time)
    });
    avPlayer.on('durationUpdate', (time: number) => {
      Logger.e('tips', 'AVPlayer durationUpdate time = ' + time)
      manager.notifyDuration(time)
    });
    avPlayer.on('seekDone', (value: number) => {
      Logger.e('tips', 'v seekDone value = ' + value)
    })
    avPlayer.on('videoSizeChange', (w: number, h: number) => {
      Logger.e('tips', 'AVPlayer videoSizeChange w = ' + w + ' h=' + h)
      manager.onVideoSizeChanged(w, h)
    })
    avPlayer.on('error', (error) => {
      Logger.e('fail', 'AVPlayer onError err = ', error)
      manager.setStatus(PlayerStatus.ERROR)
    })
    avPlayer.on('bufferingUpdate', (infoType: media.BufferingInfoType, value: number) => {
      switch (infoType) {
        case media.BufferingInfoType.BUFFERING_START:
          Logger.w('Buffering', '缓冲开始，视频可能会卡顿...');
          break;
        case media.BufferingInfoType.BUFFERING_END:
          Logger.w('Buffering', '缓冲结束，视频继续播放.');
          break;
        case media.BufferingInfoType.BUFFERING_PERCENT:
          Logger.i('Buffering', `缓冲进度: ${value}%`);
          break;
      }
      manager.notifyBuffering(infoType, value)
    })
  }

}