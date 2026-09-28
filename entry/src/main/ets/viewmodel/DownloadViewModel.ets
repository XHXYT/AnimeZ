import { OnSelectChangeObserver, SelectionManager } from '../utils/SelectionManager';
import { TaskStatus } from '../utils/download/core/Task';
import { TaskManagerObserver } from '../utils/download/core/TaskManager';
import M3U8Downloader, { M3U8DownloadTask } from '../utils/m3u8/M3U8Downloader';
import { ZDownloader } from '../utils/download/ZDownloader';
import Logger from '../utils/Logger';
import { ViewState } from '../components/StateView';
import { common } from '@kit.AbilityKit';
import { DownloadDirHelper } from '../utils/DownloadDirHelper';

const DOWNLOADER: M3U8Downloader = ZDownloader.get(M3U8Downloader)

/**
 * 番剧下载分组：同一番剧（同一 downloadDir）的下载任务聚合为一行展示
 */
@ObservedV2
export class AnimeDownloadGroup {
  /** 番剧任务共用的下载目录（分组键） */
  readonly dir: string
  /** 番剧名（取自下载目录名） */
  title: string = ''
  /** 封面（取组内第一个有封面的任务） */
  coverUrl: string = ''
  /** 组内任务（重建时整体刷新，供删除分组等操作使用） */
  readonly tasks: M3U8DownloadTask[] = []
  @Trace taskCount: number = 0
  @Trace completeCount: number = 0
  @Trace errorCount: number = 0
  /** 下载/准备中任务数 */
  @Trace runningCount: number = 0
  /** 排队中任务数 */
  @Trace waitingCount: number = 0

  constructor(dir: string) {
    this.dir = dir
    this.title = AnimeDownloadGroup.dirTitle(dir)
  }

  /** 从目录路径提取番剧名（末段目录名） */
  static dirTitle(dir: string): string {
    let d = dir
    if (d.endsWith('/')) {
      d = d.substring(0, d.length - 1)
    }
    const index = d.lastIndexOf('/')
    return index >= 0 ? d.substring(index + 1) : d
  }
}

/**
 * 下载管理 ViewModel（单例）
 * 包装 ZDownloader 单例：任务列表、番剧分组、聚合状态、分组选择模式；
 * TaskManagerObserver 与 SelectionManager 的 OnSelectChangeObserver 落到 VM 层，
 * 由页面的 attach()/detach() 保持原有 add/remove 观察者时序。
 */
@ObservedV2
export class DownloadViewModel {

  @Trace state: number = ViewState.LOADING
  @Trace errorMessage: string = ''
  @Trace tasks: M3U8DownloadTask[] = []
  @Trace taskCount: number = 0
  @Trace isAllComplete: boolean = false
  @Trace canPauseAll: boolean = false

  // 番剧分组列表
  @Trace groups: AnimeDownloadGroup[] = []

  // 分组选择相关状态
  @Trace selectMode: boolean = false
  @Trace selectCount: number = 0
  @Trace hasSelectAll: boolean = false

  public readonly selectionManager: SelectionManager<AnimeDownloadGroup> =
    new SelectionManager<AnimeDownloadGroup>()

  /** 分组对象缓存：按 dir 复用实例，避免重建导致 SelectionManager 按引用丢失选中态 */
  private readonly groupMap: Map<string, AnimeDownloadGroup> = new Map<string, AnimeDownloadGroup>()

  /** 下载根目录上下文（attach 时由页面传入，用于任务目录归并到番剧级目录） */
  private context: common.UIAbilityContext | null = null

  private readonly observer: TaskManagerObserver<M3U8DownloadTask> = {
    onTaskLoaded: (tasks: M3U8DownloadTask[]) => {
      this.tasks = this.tasks.concat(tasks).reverse()
      Logger.d(this, 'onMissionLoaded tasks len=' + tasks.length)
      this.onTasksChanged()
    },
    onTaskCreateFailed: (task: M3U8DownloadTask, error: Error) => {
      Logger.d(this, 'onMissionCreateFailed id=' + task.getTaskId() + " error=" + JSON.stringify(error))
    },
    onTaskAdd: (task: M3U8DownloadTask) => {
      Logger.d(this, 'onMissionAdd id=' + task.getTaskId())
      this.tasks.push(task)
      this.onTasksChanged()
    },
    onTaskRemove: (task: M3U8DownloadTask) => {
      this.tasks = this.tasks.filter((item: M3U8DownloadTask): boolean => {
        return item.getTaskId() != task.getTaskId()
      })
      this.onTasksChanged()
    },
    onTaskComplete: (task: M3U8DownloadTask) => {
      Logger.d(this, 'onMissionFinished id=' + task.getTaskId())
      this.onTasksChanged()
    },
    onTaskStatusChanged: (task: M3U8DownloadTask, oldStatus: TaskStatus, newStatus: TaskStatus) => {
      this.onTasksChanged()
    }
  }

  private readonly selectionObserver: OnSelectChangeObserver<AnimeDownloadGroup> = {
    onSelectionModeChange: (isSelectionMode: boolean) => {
      this.selectMode = isSelectionMode
      if (!this.selectMode) {
        this.selectCount = 0
      }
    },
    onSelectChange: (item: AnimeDownloadGroup, isSelected) => {
      this.selectCount = this.selectionManager.getSelectionCount()
      this.hasSelectAll = this.selectCount == this.groups.length
    }
  }

  /**
   * 页面可见时挂载观察者（保持原 DownloadManagerPage.aboutToAppear 时序）
   */
  public attach(context: common.UIAbilityContext) {
    this.context = context
    DOWNLOADER.addObserver(this.observer)
    DOWNLOADER.loadTasks()
    this.selectionManager.addObserver(this.selectionObserver)
    this.selectMode = this.selectionManager.isSelectionMode()
  }

  /**
   * 页面离开时摘除观察者（保持原 DownloadManagerPage.aboutToDisappear 时序）
   */
  public detach() {
    this.selectionManager.removeObserver(this.selectionObserver)
    DOWNLOADER.removeObserver(this.observer)
  }

  /**
   * 全选/全不选分组
   */
  public toggleSelectAll() {
    if (this.hasSelectAll) {
      this.selectionManager.clearSelections()
    } else {
      this.selectionManager.selectItems(this.groups)
    }
  }

  /**
   * 删除选中分组（组内全部任务）
   */
  public deleteSelectedGroups() {
    this.selectionManager.getSelections().forEach((group: AnimeDownloadGroup) => {
      group.tasks.slice().forEach((task: M3U8DownloadTask) => {
        task.delete()
      })
    })
    this.selectionManager.toggleSelectionMode()
  }

  /**
   * 全部开始：仅开始已暂停或失败的任务
   */
  public startAll() {
    this.tasks.forEach((task: M3U8DownloadTask) => {
      let status = task.getStatus()
      if (status == TaskStatus.PAUSED || status == TaskStatus.ERROR) {
        task.start()
      }
    })
  }

  /**
   * 全部暂停
   */
  public pauseAll() {
    DOWNLOADER.pauseAll()
  }

  /**
   * 重试所有失败任务
   */
  public retryAllFailedTasks() {
    this.tasks.forEach((task: M3U8DownloadTask) => {
      if (task.getStatus() == TaskStatus.ERROR) {
        task.start()
      }
    })
  }

  /**
   * 清空所有下载任务
   */
  public clearAllTasks() {
    DOWNLOADER.tasks.slice().forEach((task: M3U8DownloadTask) => {
      task.delete()
    })
    if (this.selectionManager.isSelectionMode()) {
      this.selectionManager.toggleSelectionMode()
    }
  }

  private onTasksChanged() {
    Logger.d(this, 'onTasksChanged len=' + this.tasks.length)
    if (this.tasks.length > 0) {
      this.state = ViewState.CONTENT
    } else {
      this.state = ViewState.EMPTY
    }
    this.taskCount = DOWNLOADER.tasks.length
    this.isAllComplete = DOWNLOADER.isComplete()
    this.canPauseAll = DOWNLOADER.canPauseAll()
    this.rebuildGroups()
  }

  /**
   * 将任务下载目录归并到番剧级目录（去掉"区分剧集路线"产生的线路子目录）。
   * 任务目录总是 下载根目录/番剧名/[线路名/]，取根目录后第一段即番剧名；
   * 无法识别根目录前缀时原样返回（保持原分组行为）
   */
  private animeDirOf(dir: string): string {
    if (!dir || !this.context) {
      return dir
    }
    const bases: string[] = [
      DownloadDirHelper.getPublicDownloadDir(this.context) + '/',
      this.context.filesDir + '/download/'
    ]
    for (let base of bases) {
      if (dir.startsWith(base)) {
        let rel = dir.substring(base.length)
        if (rel.endsWith('/')) {
          rel = rel.substring(0, rel.length - 1)
        }
        const slash = rel.indexOf('/')
        const first = slash >= 0 ? rel.substring(0, slash) : rel
        return first ? base + first + '/' : dir
      }
    }
    return dir
  }

  /**
   * 按番剧目录将任务聚合为番剧分组；分组对象按 dir 复用（保持选中态），
   * 计数字段为 @Trace，重建时原地更新以驱动 UI 刷新
   */
  private rebuildGroups() {
    const nextGroups: AnimeDownloadGroup[] = []
    const seen = new Set<string>()
    for (let task of this.tasks) {
      const dir: string = this.animeDirOf(task.taskInfo.downloadDir)
      if (!dir) {
        continue
      }
      let group = this.groupMap.get(dir)
      if (!group) {
        group = new AnimeDownloadGroup(dir)
        this.groupMap.set(dir, group)
      }
      if (!seen.has(dir)) {
        seen.add(dir)
        group.tasks.splice(0, group.tasks.length)
        group.taskCount = 0
        group.completeCount = 0
        group.errorCount = 0
        group.runningCount = 0
        group.waitingCount = 0
        group.coverUrl = ''
        nextGroups.push(group)
      }
      group.tasks.push(task)
      group.taskCount++
      const status = task.getStatus()
      if (status == TaskStatus.COMPLETE) {
        group.completeCount++
      } else if (status == TaskStatus.ERROR) {
        group.errorCount++
      } else if (status == TaskStatus.PROCESSING || status == TaskStatus.PREPARING) {
        group.runningCount++
      } else if (status == TaskStatus.WAITING) {
        group.waitingCount++
      }
      if (!group.coverUrl && task.videoInfo.coverUrl) {
        group.coverUrl = task.videoInfo.coverUrl
      }
    }
    this.groups = nextGroups
    // 回收已无任务的分组对象
    this.groupMap.forEach((group: AnimeDownloadGroup, dir: string) => {
      if (!seen.has(dir)) {
        this.groupMap.delete(dir)
      }
    })
  }
}

export const downloadViewModel: DownloadViewModel = new DownloadViewModel()
