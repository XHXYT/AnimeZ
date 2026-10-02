import { OnSelectChangeObserver, SelectionManager } from '../../utils/SelectionManager';
import { M3U8DownloadTask } from '../../utils/m3u8/M3U8Downloader';
import { TaskStatus } from '../../utils/download/core/Task';
import Logger from '../../utils/Logger';
import { downloadViewModel } from '../../viewmodel/DownloadViewModel';
import TitleBar, { TitleBarButton } from '../../components/TitleBar';
import StateView, { ViewState } from '../../components/StateView';
import { MenuItem } from '../../components/common/Button';
import { CollapsibleSection } from '../../components/common/CollapsibleSection';
import { ToastUtil } from '../../utils/ToastUtils';
import { AnimeState } from '../../entryability/AnimeState';
import EpisodeInfo from '../../entity/EpisodeInfo';
import { DownloadItem } from './DownloadManagerPage';

// 系统路由 - 番剧下载任务页
@Builder
export function DownloadAnimeTasksPageBuilder(name: string, param: Object) {
  DownloadAnimeTasksPage()
}

/**
 * 番剧内的线路分组：同一线路（downloadDir 中的线路子目录）的下载任务为一节
 */
class AnimeRouteSection {
  /** 线路名（目录名；空串表示未分线路的旧任务，不显示节标题） */
  readonly title: string
  readonly tasks: M3U8DownloadTask[] = []

  constructor(title: string) {
    this.title = title
  }
}

/**
 * 番剧下载任务页（二级）：展示单个番剧的全部下载任务
 */
@ComponentV2
struct DownloadAnimeTasksPage {

  @Local dir: string = ''
  @Local title: string = ''
  @Local selectionMode: boolean = false
  @Local selectCount: number = 0
  @Local hasSelectAll: boolean = false
  @Local sortKey: string = 'time' // 排列顺序：time=按时间( taskId 序)，name=按名称
  @Local sortAsc: boolean = true // 升序/降序

  private readonly selectionManager: SelectionManager<M3U8DownloadTask> =
    new SelectionManager<M3U8DownloadTask>()

  /** 本番剧的任务列表（按当前排列顺序），跟随全局任务列表联动；
   *  分组键为番剧级目录，任务目录可能带线路子目录，用前缀匹配归属 */
  @Computed
  get animeTasks(): M3U8DownloadTask[] {
    const list: M3U8DownloadTask[] = downloadViewModel.tasks
      .filter((task: M3U8DownloadTask): boolean => {
        const dir: string = task.taskInfo.downloadDir
        return dir == this.dir || (dir != '' && dir.startsWith(this.dir))
      })
    if (this.sortKey == 'name') {
      list.sort((a: M3U8DownloadTask, b: M3U8DownloadTask): number => {
        const an: string = a.getTaskName() ?? ''
        const bn: string = b.getTaskName() ?? ''
        if (an == bn) {
          return a.getTaskId() - b.getTaskId()
        }
        return (an < bn) == this.sortAsc ? -1 : 1
      })
    } else {
      list.sort((a: M3U8DownloadTask, b: M3U8DownloadTask): number => {
        return this.sortAsc ? a.getTaskId() - b.getTaskId() : b.getTaskId() - a.getTaskId()
      })
    }
    return list
  }

  /** 按线路（downloadDir 相对番剧目录的子目录）分节展示；无线路层的旧任务归入无名节 */
  @Computed
  get routeSections(): AnimeRouteSection[] {
    const sections: AnimeRouteSection[] = []
    const sectionMap: Map<string, AnimeRouteSection> = new Map<string, AnimeRouteSection>()
    for (let task of this.animeTasks) {
      let route = ''
      const dir: string = task.taskInfo.downloadDir
      if (dir.length > this.dir.length && dir.startsWith(this.dir)) {
        let rel = dir.substring(this.dir.length)
        if (rel.endsWith('/')) {
          rel = rel.substring(0, rel.length - 1)
        }
        route = rel
      }
      let section = sectionMap.get(route)
      if (!section) {
        section = new AnimeRouteSection(route)
        sectionMap.set(route, section)
        sections.push(section)
      }
      section.tasks.push(task)
    }
    return sections
  }

  private readonly selectionObserver: OnSelectChangeObserver<M3U8DownloadTask> = {
    onSelectionModeChange: (isSelectionMode: boolean) => {
      this.selectionMode = isSelectionMode
      if (!isSelectionMode) {
        this.selectCount = 0
      }
    },
    onSelectChange: (item: M3U8DownloadTask, isSelected) => {
      this.selectCount = this.selectionManager.getSelectionCount()
      this.hasSelectAll = this.selectCount == this.animeTasks.length
    }
  }

  aboutToAppear() {
    this.selectionManager.addObserver(this.selectionObserver)
  }

  aboutToDisappear() {
    if (this.selectionManager.isSelectionMode()) {
      this.selectionManager.toggleSelectionMode()
    }
    this.selectionManager.removeObserver(this.selectionObserver)
  }

  build() {
    NavDestination() {
      Column() {
        TitleBar({
          title: this.title,
          buttons: this.editButtons
        })
        if (this.animeTasks.length > 0) {
          AnimeTaskList({
            sections: this.routeSections,
            selectionManager: this.selectionManager
          })
            .layoutWeight(1)
          if (this.selectionMode) {
            this.EditToolBar()
          }
        } else {
          StateView({
            state: ViewState.EMPTY,
            errorMessage: ''
          })
            .width('100%')
            .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
    }
    .padding({ top: AnimeState.topRectHeight, bottom: AnimeState.bottomRectHeight - 20 })
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
    .onReady((value) => {
      let params = value.pathInfo.param as Record<string, string>
      this.dir = params ? (params.dir ?? '') : ''
      this.title = params ? (params.title ?? '') : ''
      Logger.d(this, 'onReady dir=' + this.dir + ' title=' + this.title)
    })
    .onBackPressed(() => {
      if (this.selectionManager.isSelectionMode()) {
        this.selectionManager.toggleSelectionMode()
        return true
      }
      return false
    })
  }

  private get editButtons(): TitleBarButton[] {
    if (this.animeTasks.length == 0) {
      return []
    }
    return [
      {
        image: this.selectionMode ? $r('app.media.ic_edit_cancel') : $r('app.media.ic_edit'),
        iconSize: 24,
        action: () => {
          this.selectionManager.toggleSelectionMode()
        }
      },
      {
        symbol: 'square_grid_2x2',
        iconSize: 24,
        menuItems: this.moreMenuItems
      }
    ]
  }

  /** 右上角更多菜单项（仅作用于当前番剧） */
  private get moreMenuItems(): MenuItem[] {
    return [
      {
        name: '全部开始',
        value: 'start_all',
        symbolStart: 'play',
        action: () => {
          this.animeTasks.forEach((task: M3U8DownloadTask) => {
            const status: TaskStatus = task.getStatus()
            if (status == TaskStatus.PAUSED || status == TaskStatus.ERROR) {
              task.start()
            }
          })
        }
      },
      {
        name: '全部暂停',
        value: 'pause_all',
        symbolStart: 'pause',
        action: () => {
          this.animeTasks.forEach((task: M3U8DownloadTask) => {
            if (task.canPause()) {
              task.pause()
            }
          })
        }
      },
      {
        name: '重试失败',
        value: 'retry_failed',
        symbolStart: 'arrow_clockwise',
        action: () => {
          this.animeTasks.forEach((task: M3U8DownloadTask) => {
            if (task.getStatus() == TaskStatus.ERROR) {
              task.start()
            }
          })
        }
      },
      {
        name: '清空本番剧',
        value: 'clear_anime',
        symbolStart: 'trash',
        action: () => {
          this.showClearAnimeConfirm()
        }
      },
      {
        name: '排列顺序',
        value: 'sort_order',
        symbolStart: 'arrow_up_arrow_down',
        labelInfo: this.sortKey == 'time' ? '时间' : '名称',
        children: [
          {
            name: '时间',
            value: 'sort_time',
            symbolEnd: this.sortKey == 'time' ? (this.sortAsc ? 'arrow_up' : 'arrow_down') : undefined,
            action: () => {
              if (this.sortKey == 'time') {
                this.sortAsc = !this.sortAsc
              } else {
                this.sortKey = 'time'
              }
            }
          },
          {
            name: '名称',
            value: 'sort_name',
            symbolEnd: this.sortKey == 'name' ? (this.sortAsc ? 'arrow_up' : 'arrow_down') : undefined,
            action: () => {
              if (this.sortKey == 'name') {
                this.sortAsc = !this.sortAsc
              } else {
                this.sortKey = 'name'
              }
            }
          }
        ]
      }
    ]
  }

  /** 清空本番剧确认弹窗 */
  private showClearAnimeConfirm() {
    ToastUtil.showAlertDialog(
      {
        title: '清空本番剧',
        message: `确认清空《${this.title}》的全部${this.animeTasks.length}项下载任务？已缓存的视频文件将一并删除，该操作不可恢复。`,
        primaryButton: {
          value: '取消',
          action: () => {
          }
        },
        secondaryButton: {
          value: '清空',
          fontColor: Color.Red,
          action: () => {
            this.animeTasks.forEach((task: M3U8DownloadTask) => {
              task.delete()
            })
            AnimeState.popPage(true)
          }
        }
      }, 'DownloadAnimeTasksPage')
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
          this.selectionManager.selectItems(this.animeTasks)
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
                  this.selectionManager.getSelections().forEach((task: M3U8DownloadTask) => {
                    task.delete()
                  })
                  this.selectionManager.toggleSelectionMode()
                }
              }
            }, 'DownloadAnimeTasksPage')
        })
    }
    .width('100%')
    .height(42)
  }
}

/**
 * 番剧任务列表：按线路分节展示，节可折叠（色条方向与折叠过程同步动画，复用 CollapsibleSection）
 */
@ComponentV2
struct AnimeTaskList {

  @Require @Param sections: AnimeRouteSection[]
  @Require @Param selectionManager: SelectionManager<M3U8DownloadTask>

  build() {
    Column() {
      List() {
        ForEach(this.sections, (section: AnimeRouteSection) => {
          ListItem() {
            CollapsibleSection({
              title: section.title,
              content: (): void => {
                this.SectionTasks(section)
              }
            })
          }
        }, (section: AnimeRouteSection) => section.title)
      }
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  /** 单个线路节内的任务列表（在父组件上下文执行，捕获外层 ForEach 的 section） */
  @Builder SectionTasks(section: AnimeRouteSection) {
    ForEach(section.tasks, (task: M3U8DownloadTask) => {
      DownloadItem({ selectionManager: this.selectionManager, task: task })
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
            // LocalVideoPlayerPage 期望参数为 { episode: EpisodeInfo }，直接传对象会取到 undefined
            let params: Record<string, EpisodeInfo> = { 'episode': episode }
            AnimeState.pushPage("LocalVideoPlayerPage", params, true)
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
}
