import { OnSelectChangeObserver, SelectionManager } from '../utils/SelectionManager';
import { TaskStatus, TaskStatusObserver } from '../utils/download/core/Task';
import { TaskManagerObserver } from '../utils/download/core/TaskManager';
import M3U8Downloader, { M3U8DownloadTask } from '../utils/m3u8/M3U8Downloader';
import { ZDownloader } from '../utils/download/ZDownloader';
import Logger from '../utils/Logger';
import { ViewState } from '../components/StateView';

const DOWNLOADER: M3U8Downloader = ZDownloader.get(M3U8Downloader)

/**
 * 下载管理 ViewModel（单例）
 * 包装 ZDownloader 单例：任务列表、聚合状态、选择模式；
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

  // 选择相关状态
  @Trace selectMode: boolean = false
  @Trace selectCount: number = 0
  @Trace hasSelectAll: boolean = false

  public readonly selectionManager: SelectionManager<M3U8DownloadTask> = new SelectionManager<M3U8DownloadTask>()

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
      this.tasks = this.tasks.filter((item) => {
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

  private readonly selectionObserver: OnSelectChangeObserver<M3U8DownloadTask> = {
    onSelectionModeChange: (isSelectionMode: boolean) => {
      this.selectMode = isSelectionMode
      if (!this.selectMode) {
        this.selectCount = 0
      }
    },
    onSelectChange: (item: M3U8DownloadTask, isSelected) => {
      this.selectCount = this.selectionManager.getSelectionCount()
      this.hasSelectAll = this.selectCount == this.tasks.length
    }
  }

  /**
   * 页面可见时挂载观察者（保持原 DownloadManagerPage.aboutToAppear 时序）
   */
  public attach() {
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
   * 全选/全不选
   */
  public toggleSelectAll() {
    if (this.hasSelectAll) {
      this.selectionManager.clearSelections()
    } else {
      this.selectionManager.selectItems(this.tasks)
    }
  }

  /**
   * 删除选中任务（原 DownloadManagerPage.EditToolBar 删除分支）
   */
  public deleteSelectedTasks() {
    this.selectionManager.getSelections().forEach((task) => {
      task.delete()
    })
    this.selectionManager.toggleSelectionMode()
  }

  /**
   * 全部暂停/全部开始
   */
  public toggleAll() {
    if (this.canPauseAll) {
      DOWNLOADER.pauseAll()
    } else {
      DOWNLOADER.startAll()
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
  }
}

export const downloadViewModel: DownloadViewModel = new DownloadViewModel()
