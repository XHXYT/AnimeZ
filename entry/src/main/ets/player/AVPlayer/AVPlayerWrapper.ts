import { media } from "@kit.MediaKit"
import fs from '@ohos.file.fs'
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
  /** 本地文件句柄：AVPlayer播放本地文件时独占fd，需保持打开直至reset/release */
  private localFile: fs.File | null = null

  constructor(avPlayer: media.AVPlayer) {
    this.avPlayer = avPlayer
  }

  /** 关闭持有的本地文件句柄（播放器已reset/release后调用） */
  private closeLocalFile() {
    if (this.localFile) {
      try {
        fs.closeSync(this.localFile)
      } catch (e) {
        Logger.e('tips', 'closeLocalFile error: ' + JSON.stringify(e))
      }
      this.localFile = null
    }
  }

  async init(manager: IPlayerManager, surfaceId: string): Promise<void> {
    this.surfaceId = surfaceId
    this.bindState(this.avPlayer, manager)
    manager.init(this.getPlayer())
  }

  /** 释放底层 AVPlayer（重复释放由 catch 兜底） */
  async release(): Promise<void> {
    return this.avPlayer.release().catch(() => {
      console.log(`AVPlayer 资源释放失败`)
    })
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
          // 本地沙箱文件：AVPlayer仅支持fd://，需打开文件句柄（播放期间独占fd）
          if (urlOrFd.startsWith('/')) {
            this.closeLocalFile()
            const file = await fs.open(urlOrFd, fs.OpenMode.READ_ONLY)
            this.localFile = file
            this.playUrl = urlOrFd
            if (urlOrFd.endsWith('.m3u8')) {
              // 本地m3u8（官方指导-情况五）：fdUrl + APPLICATION_M3U8构造mediaSource。
              // 注意：官方场景为m3u8内引用在线分片；本地分片能否解析依赖系统能力，失败会走error状态
              const fdUrl = `fd://${file.fd}?offset=0&size=0`
              const headers: Record<string, string> = {}
              const mediaSource: media.MediaSource = media.createMediaSourceWithUrl(fdUrl, headers)
              mediaSource.setMimeType(media.AVMimeTypes.APPLICATION_M3U8)
              const playbackStrategy: media.PlaybackStrategy = { preferredBufferDuration: 20 }
              await this.avPlayer.setMediaSource(mediaSource, playbackStrategy)
              Logger.e('tips', 'setDataSource from local m3u8: ' + urlOrFd + ' -> ' + fdUrl)
              return
            }
            const fdUrl = `fd://${file.fd}`
            this.avPlayer.url = fdUrl
            Logger.e('tips', 'setDataSource from local file: ' + urlOrFd + ' -> ' + fdUrl)
            return
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
        return this.avPlayer.reset().then(() => {
          // reset后播放器不再占用本地fd，及时释放
          this.closeLocalFile()
        }).catch(() => {
          console.log(`AVPlayer 视频重置失败`)
        })
      },
      release: async () => {
        Logger.e('tips', 'setDataSource release')
        return this.avPlayer.release().then(() => {
          this.closeLocalFile()
        }).catch(() => {
          console.log(`AVPlayer 资源释放失败`)
        })
      },
      seekTo: async (value: number) => {
        Logger.e('tips', 'setDataSource seekTo value=' + value)
        return this.avPlayer.seek(value as number)
      },
      setSpeed: (speed: number): Promise<void> => {
        return this.setSpeed(speed);
      }
    }
    return thePlayer
  }

  async setSpeed(speed: number) {
    // AVPlayer 仅支持固定档位倍率（0.75/1.0/1.25/1.75/2.0），
    // 按最接近档位映射；超出 2x（如长按 3x 倍速）取最高档 2x
    let avSpeed: media.PlaybackSpeed
    if (speed < 0.875) {
      avSpeed = media.PlaybackSpeed.SPEED_FORWARD_0_75_X
    } else if (speed < 1.125) {
      avSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X
    } else if (speed < 1.5) {
      avSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_25_X
    } else if (speed < 1.875) {
      avSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_75_X
    } else {
      avSpeed = media.PlaybackSpeed.SPEED_FORWARD_2_00_X
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
          // 在 initialized 回调设置最小化的播放策略；
          // prepare 必须无条件执行：策略失败（如本地源/已随setMediaSource设置）时不能跳过，
          // 否则播放器停留在 INITIALIZED，界面永远显示"线路解析中"
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
          try {
            this.avPlayer.prepare()
          } catch (error) {
            Logger.e('fail', 'prepare in stateChange failed: ', error);
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
      manager.notifySeekDone()
    })
    avPlayer.on('videoSizeChange', (w: number, h: number) => {
      Logger.e('tips', 'AVPlayer videoSizeChange w = ' + w + ' h=' + h)
      manager.onVideoSizeChanged(w, h)
    })
    avPlayer.on('error', (error) => {
      Logger.e('fail', 'AVPlayer onError err = ', error)
      manager.setErrorMessage(`播放器错误（${error.code}）`)
      manager.setStatus(PlayerStatus.ERROR)
      this.avPlayer.reset();
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
    avPlayer.on('availableBitrates', (bitrates: Array<number>)=> {
      // 返回当前视频流的可选码率列表 -> 通过 avPlayer.setBitrate() 设置列表中的对应码率
      Logger.i('tips', 'availableBitrates: ', JSON.stringify(bitrates));
    })

  }

}