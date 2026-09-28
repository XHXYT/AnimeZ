import { dataSourceManager } from '../../api/DataSourceManager';
import M3U8VideoInfo from '../../entity/m3u8/M3U8VideoInfo';
import DownloadTaskBuilder from '../download/DownloadTaskBuilder';
import DownloadTaskInfoRepository from '../download/DownloadTaskInfoRepository';
import M3U8Utils from './M3U8Utils';
import DownloadTaskInfo from '../download/DownloadTaskInfo';
import { FileDownloadTask, GroupDownloadTask } from '../download/FileDownloadTask';
import fs from '@ohos.file.fs';
import Logger from '../Logger';
import TaskManager from '../download/core/TaskManager';
import { Downloader } from '../download/Downloader';
import { CryptoJS } from '@ohos/crypto-js'
import Task from '../download/core/Task';
import { TaskStatus, TaskStatusObserver } from '../download/core/Task';
import { getWebResolveFns } from '../download/WebResolveRegistry';

class M3U8DownloadTaskBuilder extends DownloadTaskBuilder<M3U8DownloadTask> {

  pageLink: string
  coverUrl: string
  sourceKey: string

  setPageLink(pageLink: string) {
    this.pageLink = pageLink
    return this;
  }

  setCoverUrl(coverUrl: string) {
    this.coverUrl = coverUrl
    return this;
  }

  setSourceKey(sourceKey: string) {
    this.sourceKey = sourceKey
    return this;
  }


}

/**
 * m3u8下载器
 */
export default class M3U8Downloader extends Downloader<M3U8DownloadTask> {

  /**
   * 视频级串行队列：同一时刻仅一个视频任务处于 准备/下载 状态，
   * 其余任务自动排队（WAITING），前一个完成后由 startNext 接续；
   * 避免多视频并发把脆弱的解析源CDN打挂（分片级并发仍为3）
   */
  maxProcessingTaskCount = 1;

  with(url: string): M3U8DownloadTaskBuilder {
    return new M3U8DownloadTaskBuilder(this, url)
  }

  /**
   * 创建下载任务
   */
  createTask(taskInfo: DownloadTaskInfo): M3U8DownloadTask  {
    return new M3U8DownloadTask(this, taskInfo);
  }

  buildTask(builder: M3U8DownloadTaskBuilder): M3U8DownloadTask {
    let downloadTask = super.buildTask(builder)
    downloadTask.videoInfo.pageLink = builder.pageLink
    downloadTask.videoInfo.coverUrl = builder.coverUrl
    downloadTask.videoInfo.sourceKey = builder.sourceKey
    return downloadTask
  }
}

/**
 * m3u8下载任务
 */
export class M3U8DownloadTask extends GroupDownloadTask {
  private readonly taskDir
  readonly videoInfo: M3U8VideoInfo = new M3U8VideoInfo()
  /**
   * 强制重新初始化标志：网页解析源的播放地址为带签名的临时链接，
   * 分片下载报错（如403过期）后置位，下次 start 时清空已有分片并重新解析
   */
  private forceReInit: boolean = false

  constructor(manager: TaskManager, taskInfo: DownloadTaskInfo) {
    super(manager, new M3U8SegmentTaskManager(), taskInfo)
    this.taskDir = M3U8DownloadTask.resolveTaskDir(taskInfo)
    // 自监听状态：网页解析源出错后标记强制重新初始化
    this.statusManager.addObserver({
      onStatusChanged: (task: Task, oldStatus: TaskStatus, status: TaskStatus) => {
        if (status == TaskStatus.ERROR && this.isWebParseTask()) {
          this.forceReInit = true
        }
      }
    })
  }

  /**
   * 解析任务分片目录：优先使用可读的 剧集名_短哈希 目录；
   * 兼容旧任务——可读目录不存在而旧版 MD5 目录存在时沿用旧目录，避免已有文件失联
   */
  static resolveTaskDir(taskInfo: DownloadTaskInfo): string {
    const base: string = taskInfo.downloadDir
    const md5: string = CryptoJS.MD5(taskInfo.originalUrl).toString()
    const readable = base + M3U8DownloadTask.sanitizeDirName(taskInfo.taskName) + '_' + md5.substring(0, 8) + '/'
    const legacy = base + md5 + '/'
    try {
      if (!fs.accessSync(readable) && fs.accessSync(legacy)) {
        return legacy
      }
    } catch (e) {
      // 路径探测失败按新目录处理
    }
    return readable
  }

  /**
   * 剧集名转安全的文件夹名：替换文件系统非法字符，压缩空白，限长，空名回退
   */
  static sanitizeDirName(name: string): string {
    const sanitized = (name ?? '').replace(/[\\/:*?"<>|\r\n\t]/g, '_').replace(/\s+/g, ' ').trim().replace(/^\.+$/, '_')
    if (!sanitized) {
      return 'video'
    }
    return sanitized.length > 80 ? sanitized.substring(0, 80) : sanitized
  }

  /** 是否为需要WebView网页解析的视频源（原始链接形如 'rawLink_|_js'） */
  private isWebParseTask(): boolean {
    return this.taskInfo.originalUrl.includes('_|_')
  }

  /**
   * 覆写：强制重新初始化时视为未准备完成，使 start 走重新解析流程
   */
  isPrepared(): boolean {
    return !this.forceReInit && this.taskInfo.prepared
  }

  /**
   * 清空已有分片子任务（内存队列、数据库行、已下载分片文件）并重置父任务累计进度
   */
  private clearChildTasks(): void {
    const children: Task[] = this.childTaskManager.tasks.splice(0, this.childTaskManager.tasks.length)
    for (let child of children) {
      // 分片文件与数据库行异步清理，不阻塞重新解析
      child.doDelete()
      this.childTaskManager.taskInfoRepository.delete(child.taskInfo)
        .then((result) => {
          Logger.d(this, 'clearChildTasks delete info result=' + result)
        })
        .catch((e) => {
          Logger.d(this, 'clearChildTasks delete info failed! e=' + JSON.stringify(e))
        })
    }
    // 子任务进度会沿父任务逐级累加，必须一并重置
    this.taskInfo.totalWorkload = 0
    this.taskInfo.completeWorkload = 0
    this.taskInfo.taskProgress = 0
    this.videoInfo.m3u8 = null
  }

  doDelete() {
    // 同一 originalUrl 的重复任务共享同一分片目录（taskDir 由 剧集名+链接短哈希 决定），
    // 仍有其他任务占用该目录时只删数据库记录，保留分片文件
    const sharedByOther = this.manager && this.manager.tasks.some((t) =>
      t instanceof M3U8DownloadTask
      && t.getTaskId() != this.getTaskId()
      && t.taskInfo.originalUrl == this.taskInfo.originalUrl
      && t.taskInfo.downloadDir == this.taskInfo.downloadDir)
    if (!sharedByOther && fs.accessSync(this.taskDir)) {
      fs.rmdir(this.taskDir)
        .then(() => {
          Logger.d(this, 'doDelete remove taskDir success')
          this.tryRecycleAnimeDir()
        })
        .catch((e) => {
          Logger.d(this, 'doDelete remove taskDir failed! e=' + JSON.stringify(e))
        })
    } else {
      this.tryRecycleAnimeDir()
    }
  }

  /**
   * 回收任务下载目录（可能为番剧名目录或其下的线路子目录）及其已空的上级番剧名目录。
   * 注意：fs.rmdir 是递归删除语义，非 POSIX 的"仅空目录"，
   * 必须先用 listFileSync 确认目录已空，否则会误删整个番剧的已下载文件
   */
  private tryRecycleAnimeDir(): void {
    try {
      const dir = this.getDownloadDir()
      if (fs.accessSync(dir) && fs.listFileSync(dir).length == 0) {
        fs.rmdirSync(dir)
        Logger.d(this, 'doDelete recycle empty dir: ' + dir)
        // "区分剧集路线"时 dir 为线路子目录，回收后继续尝试回收已空的番剧名目录
        this.tryRecycleParentDir(dir)
      }
    } catch (e) {
      // 目录不存在或无权限：保留
    }
  }

  /**
   * 尝试回收 dir 的已空上级目录；上级为下载根目录时跳过
   * （沙箱根 .../files/download/、公共根 .../Download/包名/）
   */
  private tryRecycleParentDir(dir: string): void {
    try {
      const trimmed = dir.endsWith('/') ? dir.substring(0, dir.length - 1) : dir
      const index = trimmed.lastIndexOf('/')
      if (index <= 0) {
        return
      }
      const parent = trimmed.substring(0, index)
      const parentName = trimmed.substring(index + 1)
      const grandIndex = parent.lastIndexOf('/')
      const grandName = grandIndex >= 0 ? parent.substring(grandIndex + 1) : ''
      if (parentName.toLowerCase() == 'download' || grandName.toLowerCase() == 'download') {
        return
      }
      const parentDir = parent + '/'
      if (fs.accessSync(parentDir) && fs.listFileSync(parentDir).length == 0) {
        fs.rmdirSync(parentDir)
        Logger.d(this, 'doDelete recycle empty parent dir: ' + parentDir)
      }
    } catch (e) {
      // 目录不存在或无权限：保留
    }
  }

  getLocalM3U8Path(): string {
    return this.taskDir + 'index.m3u8'
  }

  /**
   * 从本地恢复下载任务
   */
  async doRestore(): Promise<void> {
    Logger.d(this, 'doRestore')
    let infoPath = this.taskDir + 'video.info'
    Logger.d(this, 'doRestore infoPath=' + infoPath + ' exists=' + fs.accessSync(infoPath))

    if (!fs.accessSync(infoPath)) {
      if (this.taskInfo.prepared) {
        this.taskInfo.prepared = false
      }
      return
    }

    let text = await fs.readText(infoPath, { encoding: 'utf-8' })
    Logger.d(this, 'doRestore text=' + text)
    let info = JSON.parse(text);
    this.videoInfo.pageLink = info.pageLink
    this.videoInfo.coverUrl = info.coverUrl
    this.videoInfo.sourceKey = info.sourceKey
    this.videoInfo.m3u8 = info.m3u8
    Logger.d(this, 'doRestore videoInfo=' + JSON.stringify(this.videoInfo))
    // 网页解析源上次运行出错（如签名链接过期）：恢复时直接标记强制重新解析
    if (this.isWebParseTask() && this.taskInfo.status == TaskStatus.ERROR) {
      this.forceReInit = true
    }
  }

  /**
   * 初始化
   */
  doInit() {
    Logger.d(this, 'doInit taskInfo=' + JSON.stringify(this.taskInfo))
    this.initTask()
      .then((result) => {
        Logger.d(this, 'doInit initM3u8 result=' + result)
        // 初始化完成
        this.taskInfo.prepared = true;
        // 初始化期间任务可能已被暂停或删除（网页解析耗时较长），此时不再自动继续
        if (this.getStatus() == TaskStatus.PREPARING) {
          // 继续下载任务
          this.process()
        }
      })
      .catch((e) => {
        Logger.d(this, 'M3U8Utils e=' + JSON.stringify(e))
        this.statusManager.onError(this.getErrorMessage(e))
      })
  }

  private async saveVideoInfo(): Promise<number> {
    let file = await fs.open(this.taskDir + 'video.info', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
    // 保存m3u8信息
    return fs.write(file.fd, JSON.stringify(this.videoInfo), { encoding: 'utf-8' })
  }

  /**
   * 初始化任务
   */
  private async initTask(): Promise<number> {

    Logger.d(this, 'initTask taskDir=' + this.taskDir + ' exists=' + fs.accessSync(this.taskDir))
    if (!fs.accessSync(this.taskDir)) {
      fs.mkdirSync(this.taskDir, true)
    }

    // 上次出错（如签名链接403过期）后的重试：清空已有分片并跳过缓存强制重新解析
    const skipCache = this.forceReInit
    if (this.forceReInit) {
      Logger.d(this, 'initTask forceReInit: clear child tasks and re-resolve url')
      this.forceReInit = false
      this.taskInfo.prepared = false
      this.clearChildTasks()
    }

    let result = await this.saveVideoInfo()
    Logger.d(this, 'initTask saveVideoInfo result=' + result)

    // 解析真实的m3u8链接
    this.taskInfo.url = await dataSourceManager.parseVideoUrl(this.taskInfo.originalUrl, this.videoInfo.sourceKey)
    Logger.d(this, 'initTask url=' + this.taskInfo.url)
    if (this.taskInfo.url) {
      if (this.taskInfo.url.includes('_|_')) {
        // 网页交互解析源：经全局WebView（WebVideoResolver）解析出真实播放地址，失败原样抛错
        Logger.d(this, 'initTask resolve web video url, skipCache=' + skipCache)
        this.taskInfo.url = await getWebResolveFns().resolveWebVideoUrl(this.taskInfo.url, skipCache)
        Logger.d(this, 'initTask resolved url=' + this.taskInfo.url)
      }
      // 初始化m3u8信息
      return await this.initM3u8()
    }
    throw new Error('init task failed! originalUrl: ' + this.taskInfo.originalUrl)
  }

  /**
   * 初始化并保存m3u8信息到本地
   */
  private async initM3u8(): Promise<number> {
    if (this.taskInfo.prepared) {
      return 0
    }
    // 探测内容类型：m3u8播放列表 或 直链媒体文件（mp4等）
    let content = await M3U8Utils.fetchM3U8Content(this.taskInfo.url)
    if (content != null) {
      // m3u8解析
      this.videoInfo.m3u8 = await M3U8Utils.parse(null, this.taskInfo.url, content)
    } else {
      // 直链媒体文件：构造单分片m3u8，复用分片下载与本地播放链路
      this.videoInfo.m3u8 = M3U8Utils.buildSingleSegmentM3u8(this.taskInfo.url)
    }
    Logger.d(this, 'initM3u8 videoInfo=' + JSON.stringify(this.videoInfo))

    if (!this.videoInfo.m3u8 || this.videoInfo.m3u8.segmentList.length == 0) {
      throw new Error('m3u8 parse failed!')
    }

    Logger.d(this, 'initM3u8 taskDir exists=' + fs.accessSync(this.taskDir))
    // 保存m3u8信息
    let result = await this.saveVideoInfo()

    Logger.d(this, 'save m3u8 result=' + result)

    // 将m3u8信息转换为本地m3u8，并保存至本地
    result = await M3U8Utils.saveM3U8LocalInfo(this.videoInfo.m3u8, this.getLocalM3U8Path())
    Logger.d(this, 'initM3u8 saveM3U8LocalInfo result=' + result)
    // 将m3u8原始信息保存至本地
    result = await M3U8Utils.saveM3U8OriginInfo(this.videoInfo.m3u8, this.taskDir + 'index_origin.m3u8')
    Logger.d(this, 'initM3u8 saveM3U8OriginInfo result=' + result)

    return result
  }

  /**
   * 开始下载
   */
  doStart() {
    Logger.d(this, 'doStart')
    this.prepare()
      .then(() => {
        this.childTaskManager.startAll()
      })
      .catch((e) => {
        this.statusManager.onError(this.getErrorMessage(e))
      })
  }

  /**
   * 准备分片下载任务
   */
  private async prepare() {
    Logger.d(this, 'prepare')
    if (!this.videoInfo.m3u8) {
      let infoPath = this.taskDir + 'video.info'
      Logger.d(this, 'prepare infoPath=' + infoPath)
      let text = await fs.readText(infoPath, { encoding: 'utf-8' })
      Logger.d(this, 'prepare text=' + text)
      this.videoInfo.m3u8 = JSON.parse(text)
    }
    if (this.childTaskManager.tasks.length == 0) {
      let keyUrls = new Set<string>()
      for (let seg of this.videoInfo.m3u8.segmentList) {
        let taskInfo = new DownloadTaskInfo(this.childTaskManager.generateTaskId(), this.childTaskManager.getParentTaskId())
        taskInfo.taskName = seg.name
        taskInfo.fileName = seg.name
        taskInfo.originalUrl = seg.url
        taskInfo.url = seg.url
        taskInfo.downloadDir = this.taskDir
        Logger.d(this, "init segment task : " + JSON.stringify(taskInfo))
        // 添加分片下载子任务
        this.childTaskManager.addTask(new FileDownloadTask(this.childTaskManager, taskInfo))

        // 下载key密钥文件
        if (seg.hasKey && seg.keyUrl) {
          if (keyUrls.has(seg.keyUrl)) {
            continue
          }
          keyUrls.add(seg.keyUrl)
          let taskInfo = new DownloadTaskInfo(this.childTaskManager.generateTaskId(), this.childTaskManager.getParentTaskId())
          taskInfo.originalUrl = seg.keyUrl
          taskInfo.url = seg.keyUrl
          taskInfo.fileName = seg.keyName
          taskInfo.taskName = seg.keyName
          taskInfo.downloadDir = this.taskDir
          // 添加密钥下载子任务
          this.childTaskManager.addTask(new FileDownloadTask(this.childTaskManager, taskInfo))
        }
      }
    }
  }
}

/**
 * m3u8分片下载任务管理
 */
class M3U8SegmentTaskManager extends TaskManager<FileDownloadTask, FileDownloadTask> {
  constructor(parentTask: FileDownloadTask = null) {
    super(parentTask, new DownloadTaskInfoRepository());
  }

  /**
   * 创建m3u8分片下载任务
   */
  createTask(taskInfo: DownloadTaskInfo): FileDownloadTask  {
    return new FileDownloadTask(this, taskInfo);
  }

}

