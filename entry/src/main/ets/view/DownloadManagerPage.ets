import EpisodeInfo from '../entity/EpisodeInfo';
import { OnSelectChangeObserver, SelectionManager } from '../utils/SelectionManager';
import { TaskStatus, TaskStatusObserver } from '../download/core/Task';
import TaskObserver from '../download/core/TaskObserver';
import M3U8Downloader, { M3U8DownloadTask } from '../utils/m3u8/M3U8Downloader';
import { TaskManagerObserver } from '../download/core/TaskManager';
import Logger from '../utils/Logger';
import { ZDownloader } from '../download/ZDownloader';
import StateView, { ViewState } from '../components/StateView';
import TitleBar from '../components/TitleBar';
import { ToastUtil } from '../utils/ToastUtils';

const DOWNLOADER: M3U8Downloader = ZDownloader.get(M3U8Downloader)

// 系统路由 - 下载管理页
@Builder
export function DownloadManagerPageBuilder(name: string, param: string) {
  DownloadManagerPage()
}

/**
 * 下载管理页
 */
@Entry
@Component
struct DownloadManagerPage {

  @Consume DarkModeImage: boolean
  @State state: number = ViewState.LOADING
  @State errorMessage: string = ''
  @State selectMode: boolean = false
  @State selectCount: number = 0
  @State hasSelectAll: boolean = false
  @State tasks: M3U8DownloadTask[] = []
  @State taskCount: number = 0
  @State isAllComplete: boolean = false
  @State canPauseAll: boolean = false

  // 顶部避让高度
  @StorageProp('topRectHeight') topHeight: number = 0
  // 底部避让高度
  @StorageProp('bottomRectHeight') bottomHeight: number = 0

  private readonly selectionManager: SelectionManager<M3U8DownloadTask> = new SelectionManager<M3U8DownloadTask>()
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

  aboutToAppear() {
    DOWNLOADER.addObserver(this.observer)
    DOWNLOADER.loadTasks()
    this.selectionManager.addObserver(this.selectionObserver)
    this.selectMode = this.selectionManager.isSelectionMode()
  }

  aboutToDisappear() {
    this.selectionManager.removeObserver(this.selectionObserver)
    DOWNLOADER.removeObserver(this.observer)
  }

  onBackPress() {
    if (this.selectionManager.isSelectionMode()) {
      this.selectionManager.toggleSelectionMode()
      return true
    }
    return false
  }

  build() {
    NavDestination() {
      Column() {
        // 标题栏
        TitleBar({
          title: '下载管理',
          button: () => {
            this.editButton()
          }
        })
        if (this.state == ViewState.CONTENT) {
          // 功能行
          this.FunctionBar()
          // 下载列表
          DownloadManagerList({ tasks: $tasks, selectionManager: this.selectionManager })
            .layoutWeight(1)
          if (this.selectMode) {
            this.EditToolBar()
          }
        } else {
          StateView({
            state: $state,
            errorMessage: $errorMessage,
            content: undefined,
            custom: undefined,
            onRetry: () => {
              this.loadDownloadItems()
              return true;
            }
          })
            .width('100%')
            .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
    }
    .padding({top: this.topHeight - 20, bottom: this.bottomHeight - 20})
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
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

  private loadDownloadItems() {
  }

  @Builder
  editButton() {
    if (this.state == ViewState.CONTENT) {
      Image(this.selectMode ? $r('app.media.ic_edit_cancel') : $r('app.media.ic_edit'))
        .width(24)
        .height(24)
        .margin({ right: 16 })
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.color_text_major'))
        .onClick(() => {
          this.selectionManager.toggleSelectionMode()
        })
    }
  }

  @Builder
  FunctionBar() {
    Row() {
      if (this.isAllComplete) {
        Text() {
          Span(`${this.taskCount} `)
            .fontSize(14)
            .fontColor($r('app.color.primary_color'))
          Span('已缓存')
            .fontSize(14)
            .fontColor($r('app.color.color_text_major'))
        }
        .height(32)
      } else {
        Row() {
          Text(this.canPauseAll ? '全部暂停' : '全部开始')
            .margin({ right: 4 })
            .fontSize(12)
            .fontColor(this.selectMode ? $r('app.color.color_text_minor') : $r('app.color.color_text_major') )
          Image(this.canPauseAll ? $r('app.media.ic_pause') : $r('app.media.ic_download2'))
            .width(26)
            .height(26)
            .fillColor(this.selectMode ? $r('app.color.color_text_minor') : $r('app.color.color_text_major') )
        }
        .padding({ top: 8, bottom: 8 })
        .onClick(() => {
          if (this.selectMode) {
            return
          }
          if (this.canPauseAll) {
            DOWNLOADER.pauseAll()
          } else {
            DOWNLOADER.startAll()
          }
        })
      }
    }
    .justifyContent(FlexAlign.End)
    .padding({ left: 16, right: 16 })
    .width('100%')
  }

  @Builder
  EditToolBar() {
    Row() {
      Row() {
        Image(this.hasSelectAll ? $r('app.media.ic_selection_selected') : $r('app.media.ic_selection_none'))
          .width(24)
          .height(24)
          .fillColor(this.hasSelectAll ? $r('app.color.primary_color_accent') : $r('app.color.color_text_minor'))
        Text(this.hasSelectAll ? '全不选' : '全选')
          .fontColor($r('app.color.color_text_major'))
          .fontSize(14)
          .margin({ left: 8 })
      }
      .margin({ left: 16 })
      .onClick(() => {
        if (this.hasSelectAll) {
          this.selectionManager.clearSelections()
        } else {
          this.selectionManager.selectItems(this.tasks)
        }
      })
      Blank()
      Text(`删除(${this.selectCount})`)
        .fontColor(this.selectCount == 0 ? $r('app.color.color_text_minor') : Color.Red)
        .fontSize(14)
        .margin({ right: 16 })
        .onClick(() => {
          if (this.selectCount == 0) {
            return
          }
          ToastUtil.showAlertDialog(
            {
              title: '移除下载任务',
              message: `确认移除选中的${this.selectCount}项下载任务？`,
              primaryButton: {
                value: '取消',
                action: () => {
                }
              },
              secondaryButton: {
                value: '确定',
                fontColor: Color.Red,
                action: () => {
                  this.selectionManager.getSelections().forEach((task) => {
                    task.delete()
                  })
                  this.selectionManager.toggleSelectionMode()
                }
              }
            })
        })
    }
    .width('100%')
    .height(42)
  }

}

/**
 * 下载项
 */
@Component
struct DownloadItem {

  @Consume DarkModeImage: boolean
  @Prop selectionManager: SelectionManager<M3U8DownloadTask>
  @Prop task: M3U8DownloadTask
  @State taskName: string | null = '';
  @State info: string = '已创建';
  @State isFinished: boolean = false;
  @State status: number = TaskStatus.CREATED
  @State canPause: boolean = false;
  @State progress: number = 0;
  @State progressScale: number = 0;
  @State selectionMode: boolean = false
  @State isSelected: boolean = false
  @State selectionIconMargin: number = 0
  @State selectionIconSize: number = 0

  // 选择观察
  private readonly selectionObserver: OnSelectChangeObserver<M3U8DownloadTask> = {
    onSelectionModeChange: (isSelectionMode: boolean) => {
      if (isSelectionMode) {
        this.selectionMode = true
        ToastUtil.animateTo({
          duration: 360,
          curve: Curve.ExtremeDeceleration,
          iterations: 1,
          playMode: PlayMode.Normal
        }, () => {
          this.selectionIconSize = 24
          this.selectionIconMargin = 16
        })
      } else {
        ToastUtil.animateTo({
          duration: 360,
          curve: Curve.ExtremeDeceleration,
          iterations: 1,
          playMode: PlayMode.Normal,
          onFinish: () => {
            this.selectionMode = false
          }
        }, () => {
          this.selectionIconSize = 0
          this.selectionIconMargin = 0
        })
      }
    },
    onSelectChange: (item: M3U8DownloadTask, isSelected) => {
      if (this.task && this.task.getTaskId() == item.getTaskId()) {
        Logger.d(this, 'onSelectChange isSelect=' + isSelected)
        this.isSelected = isSelected
      }
    }
  }
  // 任务观察
  private readonly observer: TaskObserver = {
    onPreparing: () => {
      Logger.d(this, "download onPreparing");
    },
    onStart: () => {
      Logger.d(this, "download onStart");
    },
    onWaiting: () => {
      Logger.d(this, "download onWaiting");
    },
    onPaused: () => {
      Logger.d(this, "download onPaused");
    },
    onProgress: (totalWorkload: number, completeWorkload: number, progress: number) => {
      let childTasks = this.task.childTaskManager.tasks
      if (childTasks.length > 0) {
        let completeCount = 0
        childTasks.forEach((task) => {
          if (task.isComplete()) {
            completeCount++
          }
        })
        this.progress = completeCount / childTasks.length * 100
      } else {
        this.progress = progress
      }
      Logger.d(this, "download onProgress total: " + totalWorkload + " received: " + completeWorkload + " progress: " + progress);
      this.info = this.getTaskInfo();
      this.showProgressAnim()
    },
    onError: (errorMessage) => {
      Logger.d(this, "download onError: " + errorMessage);
    },
    onComplete: () => {
      Logger.d(this, "download onFinished");
    },
  }
  // 状态监视器
  private statusObserver: TaskStatusObserver = {
    onStatusChanged: (task, oldStatus, status) => {
      Logger.d(this, "download onStatusChanged status=" + status);
      this.info = this.getTaskInfo();
      this.canPause = task.canPause()
      this.status = status
    }
  }

  aboutToAppear() {
    Logger.d(this, 'aboutToAppear')
    this.selectionManager.addObserver(this.selectionObserver)
    this.isSelected = this.selectionManager.isSelect(this.task)

    this.status = this.task.getStatus()
    this.canPause = this.task.canPause()
    this.info = this.getTaskInfo();
    this.isFinished = this.task.isComplete();
    if (this.task.getTaskName()) {
      this.taskName = this.task.getTaskName()
    } else {
      this.taskName = this.task.getFileName()
    }
    this.progress = this.task.getTaskProgress();

    this.task.addObserver(this.observer)
    this.task.addStatusObserver(this.statusObserver)
  }

  aboutToDisappear() {
    Logger.d(this, 'aboutToDisappear')
    this.selectionManager.removeObserver(this.selectionObserver)
    this.task.removeObserver(this.observer)
    this.task.removeStatusObserver(this.statusObserver)
  }

  build() {
    Stack() {
      if (this.status != TaskStatus.COMPLETE) {
        Row()
          .backgroundColor($r('app.color.background_color_accent'))
          .width('100%')
          .height('100%')
          .scale({ x: this.progressScale, centerX: 0 })
          .onAppear(() => {
            this.showProgressAnim(500)
          })
      }
      Row() {
        Image(this.isSelected ? $r('app.media.ic_selection_selected') : $r('app.media.ic_selection_none'))
          .width(this.selectionIconSize)
          .height(this.selectionIconSize)
          .margin({ left: this.selectionIconMargin })
          .visibility(this.selectionMode ? Visibility.Visible : Visibility.None)
          .fillColor(this.isSelected ? $r('app.color.primary_color') : $r('app.color.color_text_minor'))
        Image(this.task.videoInfo.coverUrl)
          .alt($r('app.media.pic_load_failed'))
          .height('100%')
          .aspectRatio(1.6)
          .borderRadius(8)
          .margin({ left: 16, right: 16 })
          .objectFit(ImageFit.Cover)
          .shadow({ radius: 12, color: this.DarkModeImage ? '#333333' : '#aaaaaa', offsetX: 6, offsetY: 6 })

        Column() {
          Text(this.taskName)
            .fontSize(14)
            .fontColor($r('app.color.color_text_major'))
            .fontWeight(FontWeight.Bold)
            .align(Alignment.Start)
            .width('100%')
          Text(this.info)
            .fontSize(10)
            .fontColor($r('app.color.color_text_minor'))
            .align(Alignment.Start)
            .width('100%')
        }
        .justifyContent(FlexAlign.SpaceBetween)
        .layoutWeight(1)
        .height('100%')
        .margin({ right: 16 })

        if (this.status != TaskStatus.COMPLETE) {
          Image(this.canPause ? $r('app.media.ic_download_pause') : $r('app.media.ic_download_resume'))
            .width(28)
            .height(28)
            .margin({ right: 14 })
            .objectFit(ImageFit.Contain)
            .onClick(() => {
              if (this.task.canPause()) {
                this.task.pause()
              } else if (this.task.canStart()) {
                this.task.addObserver(this.observer)
                this.task.addStatusObserver(this.statusObserver)
                this.task.start()
              }
            })
        }

      }
      .width('100%')
      .height('100%')
      .padding({ top: 12, bottom: 12 })
    }
    .height('100%')
    .height(80)
  }

  private showProgressAnim(duration: number = 250) {
    animateTo({
      duration: duration,
      curve: Curve.ExtremeDeceleration,
      iterations: 1,
      playMode: PlayMode.Normal
    }, () => {
      this.progressScale = this.progress / 100
    })
  }

  getActionIcon(): Resource {
    if (this.task.canPause()) {
      return $r('app.media.ic_download_pause');
    } else {
      return $r('app.media.ic_download_resume');
    }
  }

  getActionIconString(): string {
    if (this.task.canPause()) {
      return 'app.media.ic_download_pause';
    } else {
      return 'app.media.ic_download_resume';
    }
  }

  getTaskInfo() {
    let status = this.task.getStatus()
    Logger.d(this, 'getTaskInfo status=' + status)
    if (status == TaskStatus.CREATED) {
      return '已暂停';
    } else if (status == TaskStatus.PREPARING) {
      return '准备中';
    } else if (status == TaskStatus.WAITING) {
      return '等待中';
    } else if (status == TaskStatus.PROCESSING) {
      return this.task.getFormatTotalSize() + ' / ' + this.task.getFormatReceivedSize() + ' ' + this.task.getFormatProgress();
    } else if (status == TaskStatus.PAUSED) {
      return '已暂停';
    } else if (status == TaskStatus.COMPLETE) {
      return '已完成';
    } else {
      if (this.task.taskInfo.message) {
        return '出错了：' + this.task.taskInfo.message;
      }
      return '出错了';
    }
  }
}

/**
 * 下载列表
 */
@Component
struct DownloadManagerList {

  @Prop selectionManager: SelectionManager<M3U8DownloadTask>
  @Consume('pageStack') pageStack: NavPathStack
  @Link tasks: M3U8DownloadTask[]
  @State selections: number[] = []
  @Consume DarkModeImage: boolean

  aboutToAppear() {

  }

  build() {
    Column() {
      List() {
        ForEach(this.tasks.map((task, i) => {
          return i
        }), (i: number) => {
          ListItem() {
            DownloadItem({ selectionManager: this.selectionManager, task: this.tasks[i] })
          }
          .onClick(() => {
            let task = this.tasks[i]
            Logger.d(this, 'isSelectionMode=' + this.selectionManager.isSelectionMode())
            if (this.selectionManager.isSelectionMode()) {
              this.selectionManager.toggleSelectItem(task)
              return
            }
            if (task.isComplete()) {
              let episode: EpisodeInfo = {
                title: task.getTaskName() || '',
                desc: task.getTaskName() || '',
                link: task.getOriginalUrl(),
                videoUrl: task.getLocalM3U8Path()
              }
              this.pageStack.pushPathByName("LocalVideoPlayerPage", episode, true)
            }
          })
          .gesture(LongPressGesture({ repeat: false })
            .onAction((event) => {
              Logger.d(this, 'onLongPress')
              // 长按多选
              if (!this.selectionManager.isSelectionMode()) {
                this.selectionManager.toggleSelectionMode()
              }
              this.selectionManager.toggleSelectItem(this.tasks[i])
            })
          )
        })

        // TODO 这样写竟然报错？？？？
        //        ForEach(this.tasks, (task: M3U8DownloadTask) => {
        //          ListItem() {
        //            DownloadItem({ selectMode: $selectMode, task: task })
        //          }
        //          //          .selectable(true)
        //          .onSelect((isSelected) => {
        //            Logger.d(this, 'isSelected=' + isSelected)
        //          })
        //          .onClick(() => {
        //            if (task.isComplete()) {
        //              router.pushUrl({url: 'pages/LocalVideoPlayerPage', params: {video_path: task.getLocalM3u8Path()}})
        //            }
        //          })
        //          .gesture(LongPressGesture({ repeat: false })
        //            .onActionEnd(() => {
        //              Logger.d(this, 'onLongPress')
        //              this.selectMode = !this.selectMode
        //            }))
        //        })
      }
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
