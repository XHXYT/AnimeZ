import EpisodeInfo from '../entity/EpisodeInfo';
import { OnSelectChangeObserver, SelectionManager } from '../utils/SelectionManager';
import { TaskStatus, TaskStatusObserver } from '../download/core/Task';
import TaskObserver from '../download/core/TaskObserver';
import { M3U8DownloadTask } from '../utils/m3u8/M3U8Downloader';
import Logger from '../utils/Logger';
import { downloadViewModel } from '../viewmodel/DownloadViewModel';
import StateView, { ViewState } from '../components/StateView';
import TitleBar from '../components/TitleBar';
import { ToastUtil } from '../utils/ToastUtils';
import { AnimeState } from '../entryability/AnimeState';

// 系统路由 - 下载管理页
@Builder
export function DownloadManagerPageBuilder(name: string, param: string) {
  DownloadManagerPage()
}

/**
 * 下载管理页
 */
@ComponentV2
struct DownloadManagerPage {

  aboutToAppear() {
    downloadViewModel.attach()
  }

  aboutToDisappear() {
    downloadViewModel.detach()
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
        if (downloadViewModel.state == ViewState.CONTENT) {
          // 功能行
          this.FunctionBar()
          // 下载列表
          DownloadManagerList({
            tasks: downloadViewModel.tasks,
            selectionManager: downloadViewModel.selectionManager
          })
            .layoutWeight(1)
          if (downloadViewModel.selectMode) {
            this.EditToolBar()
          }
        } else {
          StateView({
            state: downloadViewModel.state,
            errorMessage: downloadViewModel.errorMessage
          })
            .width('100%')
            .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
    }
    .padding({ top: AnimeState.topRectHeight - 20, bottom: AnimeState.bottomRectHeight - 20 })
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
    .onBackPressed(() => {
      if (downloadViewModel.selectionManager.isSelectionMode()) {
        downloadViewModel.selectionManager.toggleSelectionMode()
        return true
      }
      return false
    })
  }

  @Builder
  editButton() {
    if (downloadViewModel.state == ViewState.CONTENT) {
      Image(downloadViewModel.selectMode ? $r('app.media.ic_edit_cancel') : $r('app.media.ic_edit'))
        .width(24)
        .height(24)
        .margin({ right: 16 })
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.color_text_major'))
        .onClick(() => {
          downloadViewModel.selectionManager.toggleSelectionMode()
        })
    }
  }

  @Builder
  FunctionBar() {
    Row() {
      if (downloadViewModel.isAllComplete) {
        Text() {
          Span(`${downloadViewModel.taskCount} `)
            .fontSize(14)
            .fontColor($r('app.color.primary_color'))
          Span('已缓存')
            .fontSize(14)
            .fontColor($r('app.color.color_text_major'))
        }
        .height(32)
      } else {
        Row() {
          Text(downloadViewModel.canPauseAll ? '全部暂停' : '全部开始')
            .margin({ right: 4 })
            .fontSize(12)
            .fontColor(downloadViewModel.selectMode ? $r('app.color.color_text_minor') : $r('app.color.color_text_major'))
          Image(downloadViewModel.canPauseAll ? $r('app.media.ic_pause') : $r('app.media.ic_download2'))
            .width(26)
            .height(26)
            .fillColor(downloadViewModel.selectMode ? $r('app.color.color_text_minor') : $r('app.color.color_text_major'))
        }
        .padding({ top: 8, bottom: 8 })
        .onClick(() => {
          if (downloadViewModel.selectMode) {
            return
          }
          downloadViewModel.toggleAll()
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
        Image(downloadViewModel.hasSelectAll ? $r('app.media.ic_selection_selected') : $r('app.media.ic_selection_none'))
          .width(24)
          .height(24)
          .fillColor(downloadViewModel.hasSelectAll ? $r('app.color.primary_color_accent') : $r('app.color.color_text_minor'))
        Text(downloadViewModel.hasSelectAll ? '全不选' : '全选')
          .fontColor($r('app.color.color_text_major'))
          .fontSize(14)
          .margin({ left: 8 })
      }
      .margin({ left: 16 })
      .onClick(() => {
        downloadViewModel.toggleSelectAll()
      })
      Blank()
      Text(`删除(${downloadViewModel.selectCount})`)
        .fontColor(downloadViewModel.selectCount == 0 ? $r('app.color.color_text_minor') : Color.Red)
        .fontSize(14)
        .margin({ right: 16 })
        .onClick(() => {
          if (downloadViewModel.selectCount == 0) {
            return
          }
          ToastUtil.showAlertDialog(
            {
              title: '移除下载任务',
              message: `确认移除选中的${downloadViewModel.selectCount}项下载任务？`,
              primaryButton: {
                value: '取消',
                action: () => {
                }
              },
              secondaryButton: {
                value: '确定',
                fontColor: Color.Red,
                action: () => {
                  downloadViewModel.deleteSelectedTasks()
                }
              }
            }, 'DownloadManagerPage')
        })
    }
    .width('100%')
    .height(42)
  }

}

/**
 * 下载项
 */
@ComponentV2
struct DownloadItem {

  @Require @Param selectionManager: SelectionManager<M3U8DownloadTask>
  @Require @Param task: M3U8DownloadTask
  @Local taskName: string | null = '';
  @Local info: string = '已创建';
  @Local isFinished: boolean = false;
  @Local status: number = TaskStatus.CREATED
  @Local canPause: boolean = false;
  @Local progress: number = 0;
  @Local progressScale: number = 0;
  @Local selectionMode: boolean = false
  @Local isSelected: boolean = false
  @Local selectionIconMargin: number = 0
  @Local selectionIconSize: number = 0

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
  private readonly statusObserver: TaskStatusObserver = {
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
          .shadow({ radius: 12, color: AnimeState.darkModeImage ? '#333333' : '#aaaaaa', offsetX: 6, offsetY: 6 })

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
    ToastUtil.animateTo({
      duration: duration,
      curve: Curve.ExtremeDeceleration,
      iterations: 1,
      playMode: PlayMode.Normal
    }, () => {
      this.progressScale = this.progress / 100
    })
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
@ComponentV2
struct DownloadManagerList {

  @Require @Param tasks: M3U8DownloadTask[]
  @Require @Param selectionManager: SelectionManager<M3U8DownloadTask>

  build() {
    Column() {
      List() {
        ForEach(this.tasks, (task: M3U8DownloadTask) => {
          ListItem() {
            DownloadItem({ selectionManager: this.selectionManager, task: task })
          }
          .onClick(() => {
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
              AnimeState.pageStack.pushPathByName("LocalVideoPlayerPage", episode, true)
            }
          })
          .gesture(LongPressGesture({ repeat: false })
            .onAction((event) => {
              Logger.d(this, 'onLongPress')
              // 长按多选
              if (!this.selectionManager.isSelectionMode()) {
                this.selectionManager.toggleSelectionMode()
              }
              this.selectionManager.toggleSelectItem(task)
            })
          )
        }, (task: M3U8DownloadTask) => String(task.getTaskId()))
      }
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
