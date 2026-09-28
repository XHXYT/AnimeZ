import { TaskStatus } from './core/Task';
import fs from '@ohos.file.fs'
import TaskManager from './core/TaskManager'
import DownloadTaskInfo from './DownloadTaskInfo'
import { AbsTask } from './core/Task'
import Logger from '../Logger'
import http from '@ohos.net.http'
import { DownloadUtils } from './DownloadUtils'
import util from '@ohos.util'

export class FileDownloadTask<T extends DownloadTaskInfo = DownloadTaskInfo> extends AbsTask<T> {
  protected redirectCount: number = 0
  protected currentRequest: http.HttpRequest = null

  constructor(manager: TaskManager, taskInfo: T) {
    super(manager, taskInfo)
  }

  getOriginalUrl(): string {
    return this.taskInfo.originalUrl
  }

  getUrl(): string {
    return this.taskInfo.url
  }

  getTaskName() {
    if (this.taskInfo.taskName) {
      return this.taskInfo.taskName
    }
    return null
  }

  getFilePath(): string {
    return this.taskInfo.downloadDir + '/' + this.taskInfo.fileName
  }

  getFileName() {
    if (this.taskInfo.fileName) {
      return this.taskInfo.fileName
    }
    return 'Unknown File'
  }

  getDownloadDir() {
    return this.taskInfo.downloadDir
  }

  getFormatTotalSize() {
    return DownloadUtils.formatFileSize(this.getTotalWorkload())
  }

  getFormatReceivedSize() {
    return DownloadUtils.formatFileSize(this.getCompleteWorkload())
  }

  getFormatProgress() {
    return DownloadUtils.formatProgress(this.getTaskProgress())
  }

  doInit() {
    Logger.w(this, 'doInit redirectCount=' + this.redirectCount)
    if (this.redirectCount > 10) {
      this.statusManager.onError('to many redirect!')
      return
    }

    let httpRequest = http.createHttp()
    httpRequest.request(this.taskInfo.url, {
      method: http.RequestMethod.HEAD,
      readTimeout: 20000,
      connectTimeout: 20000,
      header: { 'range': 'bytes=0-' },
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    }, (err, data) => {
      this.doPrepare(err, data)
    })
  }

  doPrepare(err, data) {
    if (data) {
      Logger.w(this, 'doInit data=' + JSON.stringify(data))
      let code = data.responseCode
      if (code < 300) {
        this.taskInfo.blockDownload = code === http.ResponseCode.PARTIAL
        let size = parseInt(data.header['content-length'])
        if (!isNaN(size)) {
          this.observerDispatcher.progressManager.onInitSize(size)
        }
        if (!this.taskInfo.fileName) {
          this.taskInfo.fileName = DownloadUtils.guessFileName(
            this.taskInfo.url, data.header['content-disposition'], data.header['content-type'])
        }
        this.taskInfo.prepared = true
        // HEAD 期间任务可能已被暂停/删除：保持 stopped 状态，下次 start 时因 prepared 直接续传
        if (this.getStatus() == TaskStatus.PREPARING) {
          this.manager.process(this)
        }
      } else if (code < 400) {
        // 重定向
        this.redirectCount++
        let location = data.header['location']
        this.taskInfo.url = location
        this.doInit()
      } else {
        // HEAD探测被服务器拒绝（部分CDN对HEAD返回5xx但GET正常）：跳过大小探测直接走GET下载，
        // 真实错误（如403签名过期）会在GET阶段再次出现并正常报错
        this.fallbackToDirectDownload('HEAD responseCode is ' + code)
      }
    } else {
      Logger.w(this, 'doInit err=' + JSON.stringify(err))
      // HEAD网络失败同样交由GET流程兜底
      this.fallbackToDirectDownload('HEAD request failed: ' + (err ? err.message : 'unknown'))
    }
  }

  /** HEAD 探测失败时跳过大小预取直接进入下载，大小改由 GET 响应头补报 */
  private fallbackToDirectDownload(reason: string) {
    Logger.w(this, 'doInit fallback to direct download, reason: ' + reason)
    if (!this.taskInfo.fileName) {
      this.taskInfo.fileName = DownloadUtils.guessFileName(this.taskInfo.url)
    }
    this.taskInfo.prepared = true
    if (this.getStatus() == TaskStatus.PREPARING) {
      this.manager.process(this)
    }
  }

  doWaiting() {
    // do nothing
    Logger.d(this, 'doWaiting')
  }

  doPause() {
    // 中断进行中的下载请求，停止接收数据
    if (this.currentRequest) {
      try {
        this.currentRequest.destroy()
      } catch (e) {
        Logger.d(this, 'doPause destroy failed! e=' + JSON.stringify(e))
      }
      this.currentRequest = null
    }
  }

  doDelete() {
    this.doPause()
    fs.unlink(this.getFilePath())
      .then(() => {
        Logger.d(this, 'doDelete success')
      })
      .catch((e) => {
        // TODO error
        Logger.d(this, 'doDelete failed! e=' + JSON.stringify(e))
      })
  }

  doStart() {
    let range = 'bytes=' + this.getCompleteWorkload() + '-'
    Logger.d(this, 'doStart redirectCount=' + this.redirectCount + ' range=' + range)
    this.taskInfo.header = { 'range': range }
    this.download()
      .then((result) => {
        if (result && this.getStatus() == TaskStatus.PROCESSING) {
          this.statusManager.setStatus(TaskStatus.COMPLETE)
        }
      })
      .catch((e) => {
        Logger.d(this, 'doStart download failed! e=' + JSON.stringify(e))
        if (this.getStatus() == TaskStatus.PROCESSING) {
          this.statusManager.onError(this.getErrorMessage(e))
        }
      })
  }

  protected getErrorMessage(e): string {
    if (e instanceof Error && e.message) {
      return e.message
    }
    if (e && e.message) {
      return e.message
    }
    return JSON.stringify(e)
  }

  /**
   * 流式下载：requestInStream分块接收并写入磁盘，避免大文件一次性读入内存
   * （request接口响应默认上限5MB，大文件会报2300023错误）
   */
  async download(): Promise<boolean> {
    if (this.redirectCount > 10) {
      this.statusManager.onError('to many redirect!')
      return false
    }

    const httpRequest = http.createHttp()
    this.currentRequest = httpRequest
    const startOffset = this.getCompleteWorkload()
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      // readTimeout为请求总时长（含DNS、连接、传输），大文件需要更长的超时时间
      readTimeout: 600000,
      connectTimeout: 20000
    }
    if (startOffset > 0 && this.taskInfo.header) {
      // 断点续传
      options.header = this.taskInfo.header
    }
    Logger.d(this, 'download url=' + this.taskInfo.url + ' startOffset=' + startOffset)

    return new Promise<boolean>((resolve, reject) => {
      let settled = false
      let fd = -1
      let openPromise: Promise<void> = null
      let writeChain: Promise<void> = Promise.resolve()
      let writeOffset = startOffset
      let writtenCounted = 0
      let progressAdjusted = false
      let location = ''
      let responseCode = -1
      let codeKnown = false
      let receiveEnded = false

      // 回退本次会话已计入的进度（用于失败或重定向时）
      const rollbackProgress = () => {
        if (writtenCounted > 0) {
          this.taskInfo.completeWorkload = Math.max(0, this.taskInfo.completeWorkload - writtenCounted)
          writtenCounted = 0
        }
      }

      // 请求结束后释放资源：等待写盘完成、关闭文件、销毁请求
      const release = (): Promise<void> => {
        return writeChain
          .then(() => {
            return openPromise ? openPromise : Promise.resolve()
          })
          .catch(() => {
          })
          .then(() => {
            if (fd >= 0) {
              const closeFd = fd
              fd = -1
              fs.close(closeFd).catch((e) => {
                Logger.d(this, 'download close file failed! e=' + JSON.stringify(e))
              })
            }
            if (this.currentRequest === httpRequest) {
              this.currentRequest = null
            }
            try {
              httpRequest.off('headersReceive')
              httpRequest.off('dataReceive')
              httpRequest.off('dataEnd')
              httpRequest.destroy()
            } catch (e) {
              Logger.d(this, 'download destroy request failed! e=' + JSON.stringify(e))
            }
          })
      }

      const settle = (ok: boolean, error?: Error) => {
        if (settled) {
          return
        }
        settled = true
        release()
          .then(() => {
            if (error) {
              reject(error)
            } else {
              resolve(ok)
            }
          })
          .catch((e) => {
            reject(new Error(this.getErrorMessage(e)))
          })
      }

      // 响应码与数据接收都完成后才能得出结论（兼容promise先返回或后返回两种时序）
      const trySettle = () => {
        if (settled || !codeKnown || !receiveEnded) {
          return
        }
        if (responseCode < 300
          || (responseCode == 416 && startOffset > 0)) {
          // 416：请求的Range起点已超出文件末尾，说明文件已下载完成
          settle(true)
        } else if (responseCode < 400) {
          // 重定向
          this.redirectCount++
          if (location && location !== '') {
            rollbackProgress()
            settled = true
            release()
              .then(() => {
                this.taskInfo.url = location
                return this.download()
              })
              .then((result: boolean) => {
                resolve(result)
              })
              .catch((e) => {
                reject(new Error(this.getErrorMessage(e)))
              })
          } else {
            rollbackProgress()
            settle(false, new Error('request error! responseCode is ' + responseCode))
          }
        } else {
          rollbackProgress()
          if (this.getStatus() != TaskStatus.PROCESSING) {
            // 已暂停或删除导致的中断，不作为错误处理
            settle(false)
          } else {
            settle(false, new Error('request error! responseCode is ' + responseCode))
          }
        }
      }

      // 订阅响应头：识别断点续传（content-range）与重定向地址
      httpRequest.on('headersReceive', (header: Object) => {
        const headers = header as Record<string, string>
        location = headers['location'] ?? ''
        // HEAD探测被跳过时大小未知：从GET响应头补报总大小（content-range 总长优先，其次 content-length）
        // totalWorkload==0 表示本次会话尚未计入大小（HEAD已计入、或断点续传前已持久化的场景不会重复计数）
        if (!location && this.taskInfo.totalWorkload == 0 && this.observerDispatcher.progressManager) {
          let size = -1
          const contentRange = headers['content-range']
          if (contentRange && contentRange.toLowerCase().indexOf('bytes') >= 0) {
            const total = parseInt(contentRange.split('/')[1])
            if (!isNaN(total)) {
              size = total
            }
          }
          if (size < 0) {
            const length = parseInt(headers['content-length'])
            if (!isNaN(length)) {
              size = length
            }
          }
          if (size >= 0) {
            Logger.d(this, 'download report size from GET header: ' + size)
            this.observerDispatcher.progressManager.onInitSize(size)
          }
        }
        if (startOffset > 0 && !progressAdjusted) {
          const contentRange = headers['content-range']
          if (contentRange && contentRange.toLowerCase().indexOf('bytes') >= 0) {
            // 服务器支持断点续传，从startOffset继续写入
            Logger.d(this, 'download resume from ' + startOffset)
          } else {
            // 服务器不支持Range请求，返回了完整内容：从头写入并回退已计入的进度
            progressAdjusted = true
            writeOffset = 0
            this.taskInfo.completeWorkload = Math.max(0, this.taskInfo.completeWorkload - startOffset)
            Logger.d(this, 'download range not supported, restart from 0')
          }
        }
      })

      // 分块接收数据并顺序写盘
      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        if (settled) {
          return
        }
        if (this.getStatus() != TaskStatus.PROCESSING) {
          // 任务已暂停或删除，中断接收
          settle(false)
          return
        }
        const chunk = data
        if (!openPromise) {
          openPromise = fs.open(this.getFilePath(), fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY)
            .then((file) => {
              fd = file.fd
            })
        }
        writeChain = writeChain
          .then(() => {
            return openPromise
          })
          .then(() => {
            if (this.getStatus() != TaskStatus.PROCESSING || fd < 0) {
              return
            }
            return fs.write(fd, chunk, { offset: writeOffset, length: chunk.byteLength })
              .then((result: number) => {
                writeOffset += result
                writtenCounted += result
                if (this.observerDispatcher.progressManager) {
                  this.observerDispatcher.progressManager.onReceived(result)
                }
              })
          })
          .catch((e) => {
            rollbackProgress()
            settle(false, new Error(this.getErrorMessage(e)))
          })
      })

      // 数据接收完毕
      httpRequest.on('dataEnd', () => {
        receiveEnded = true
        trySettle()
      })

      httpRequest.requestInStream(this.taskInfo.url, options)
        .then((code: number) => {
          responseCode = code
          codeKnown = true
          trySettle()
        })
        .catch((e) => {
          if (settled) {
            return
          }
          rollbackProgress()
          if (this.getStatus() != TaskStatus.PROCESSING) {
            // 暂停或删除导致请求中断，不作为错误处理
            settle(false)
          } else {
            settle(false, new Error(this.getErrorMessage(e)))
          }
        })
    })
  }
}

export abstract class GroupDownloadTask<T extends DownloadTaskInfo = DownloadTaskInfo> extends FileDownloadTask<T> {
  readonly childTaskManager: TaskManager

  constructor(manager: TaskManager, childTaskManager: TaskManager, taskInfo: T) {
    super(manager, taskInfo)
    this.childTaskManager = childTaskManager
    this.childTaskManager.parentTask = this
    // TODO 开始时加载子任务
    this.childTaskManager.loadTasks()
  }

  doStart() {
    // this.initChildTasks()
    this.childTaskManager.startAll()
  }

  doWaiting() {
    this.childTaskManager.waitingAll()
  }

  doPause() {
    this.childTaskManager.pauseAll()
  }

  // TODO
  //    protected abstract initChildTasks(emitter)

  //    protected abstract initChildTasks()

}

export abstract class ChildDownloadTask<T extends DownloadTaskInfo> extends FileDownloadTask<T> {
  constructor(manager: TaskManager, taskInfo: T) {
    super(manager, taskInfo)
  }

  getFilePath(): string {
    if (this.manager.parentTask instanceof FileDownloadTask) {
      return this.manager.parentTask.getFilePath()
    }
    return super.getFilePath()
  }
}