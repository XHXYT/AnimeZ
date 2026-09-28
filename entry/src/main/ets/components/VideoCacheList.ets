import { TaskStatus } from '../utils/download/core/Task';
import { ZDownloader } from '../utils/download/ZDownloader';
import { VideoCacheItem } from './VideoCacheItem';
import EpisodeInfo from '../entity/EpisodeInfo';
import EpisodeList from '../entity/EpisodeList';
import VideoDetailInfo from '../entity/VideoDetailInfo';
import Logger from '../utils/Logger';
import M3U8Downloader, { M3U8DownloadTask } from '../utils/m3u8/M3U8Downloader';
import { TaskManagerObserver } from '../utils/download/core/TaskManager';
import { AnimeState } from '../entryability/AnimeState';
import { common } from '@kit.AbilityKit';
import { DownloadDirHelper } from '../utils/DownloadDirHelper';
import { ToastUtil } from '../utils/ToastUtils';
import { appSettings } from '../entryability/Settings';
import { sortEpisodesByNumber } from '../utils/SortUtils';
import { CollapsibleSection } from './common/CollapsibleSection';

@ComponentV2
export struct VideoCacheList {

  @Require @Param videoDetailInfo: VideoDetailInfo

  aboutToAppear() {
    Logger.d(this, 'aboutToAppear')
  }

  aboutToDisappear() {
    Logger.d(this, 'aboutToDisappear')
  }

  build() {
    Column() {
      Row() {
        Scroll() {
          Column() {
            ForEach(this.videoDetailInfo.episodes, (episodeList: EpisodeList, episodeListIndex: number) => {
              if (episodeList.title != '') {
                CollapsibleSection({
                  title: episodeList.title,
                  headerEnd: (): void => {
                    this.CacheSectionHeaderEnd(episodeList)
                  },
                  content: (): void => {
                    this.CacheSectionGrid(episodeList)
                  }
                })
              } else {
                // 无名线路：无节标题可折叠，保留排序开关与缓存全部
                Column() {
                  Row() {
                    Row()
                      .height(14)
                      .width(6)
                      .margin({ right: 2 })
                      .borderRadius(4)
                      .backgroundColor($r('app.color.primary_color'))
                    Blank()
                    this.EpisodeOrderToggle()
                    Text('缓存全部')
                      .fontSize(12)
                      .padding(8)
                      .borderRadius(6)
                      .onClick(() => {
                        this.downloadAll(episodeList)
                      })
                  }
                  .padding({ left: 16, top: 16, right: 16, bottom: 4 })
                  .width('100%')
                  this.CacheSectionGrid(episodeList)
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
            }, (episodeList: EpisodeList, episodeListIndex: number) => episodeListIndex + '-' + episodeList.title)
          }
          .alignItems(HorizontalAlign.Start)
          .constraintSize({
            minHeight: '100%'
          })
        }
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .layoutWeight(1)

      Row() {
        Text("下载列表")
          .textAlign(TextAlign.Center)
          .fontSize(14)
          .backgroundColor($r('app.color.primary_color_accent'))
          .fontColor(Color.White)
          .borderRadius(21)
          .layoutWeight(1)
          .onClick(() => {
            AnimeState.pageStack.pushPathByName("DownloadManagerPage", '', true)
          })
          .height(42)
          .width('100%')
      }
      .padding({ left: 24, right: 24, top: 12, bottom: 12 })
    }
    .width('100%')
    .layoutWeight(1)
  }

  /** 剧集排序快捷开关：与详情页/播放器共用全局设置，切换后各处同步重排 */
  @Builder EpisodeOrderToggle() {
    Row({ space: 4 }) {
      SymbolGlyph(appSettings.episodes_order === 'asc'
        ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
        .fontSize(12)
        .fontColor([$r('app.color.color_text_normal')])
      Text(appSettings.episodes_order === 'asc' ? '正序' : '倒序')
        .fontColor($r('app.color.color_text_normal'))
        .fontSize(12)
    }
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .borderRadius(14)
    .backgroundColor($r('app.color.background_color_accent'))
    .onClick(() => {
      appSettings.episodes_order = appSettings.episodes_order === 'asc' ? 'desc' : 'asc'
    })
  }

  /** 节标题行右侧内容：排序开关 + 缓存全部（在父组件上下文执行，捕获外层 ForEach 的线路数据） */
  @Builder CacheSectionHeaderEnd(episodeList: EpisodeList) {
    Row({ space: 8 }) {
      this.EpisodeOrderToggle()
      Text('缓存全部')
        .fontSize(12)
        .padding(8)
        .borderRadius(6)
        .onClick(() => {
          this.downloadAll(episodeList)
        })
    }
  }

  /** 单条线路的缓存剧集网格，按全局正倒序设置排列（在父组件上下文执行，捕获外层 ForEach 的线路数据） */
  @Builder CacheSectionGrid(episodeList: EpisodeList) {
    Flex({ alignItems: ItemAlign.Start, justifyContent: FlexAlign.Start, wrap: FlexWrap.Wrap }) {
      ForEach(sortEpisodesByNumber(episodeList.episodes, appSettings.episodes_order),
        (item: EpisodeInfo, episodeIndex: number) => {
          VideoCacheItem({ videoDetailInfo: this.videoDetailInfo, episodeInfo: item, routeTitle: episodeList.title })
            .width('22%')
            .margin({ bottom: 8, right: (episodeIndex + 1) % 4 == 0 ? 0 : '4%' })
        }, (item: EpisodeInfo) => item.link)
    }
    .margin({ top: 8 })
    .padding({ left: 16, right: 16 })
  }

  /**
   * TODO test缓存全部
   */
  private downloadAll(episodeList: EpisodeList) {
    const taskDir: string = DownloadDirHelper.getTaskDownloadDir(
      this.getUIContext().getHostContext()! as common.UIAbilityContext, this.videoDetailInfo.title, episodeList.title)
    const observer: TaskManagerObserver<M3U8DownloadTask> = {
      onTaskLoaded: (tasks: M3U8DownloadTask[]) => {
        ZDownloader.get(M3U8Downloader).removeObserver(observer)
        let added = 0
        for (let episode of episodeList.episodes) {
          let task = tasks.find((task) => {
            return task.getOriginalUrl() == episode.link && task.taskInfo.downloadDir == taskDir
          })
          Logger.d(this, 'find task=' + task + ' link=' + episode.link)
          if (task) {
            continue
          }
          task = ZDownloader.get(M3U8Downloader)
            .with(episode.link)
            .setPageLink(this.videoDetailInfo.url)
            .setCoverUrl(this.videoDetailInfo.coverUrl)
            .setSourceKey(this.videoDetailInfo.sourceKey)
            .setTaskName(episode.desc)
            .setFileName('index.m3u8')
            .setDownloadDir(taskDir)
            .build()
          task.start()
          added++
        }
        if (added > 0) {
          ToastUtil.showToast({ message: `已加入${added}个下载任务，将按顺序自动下载` })
        } else {
          ToastUtil.showToast({ message: '本列表剧集均已在下载列表中' })
        }
      },
      onTaskCreateFailed: (task: M3U8DownloadTask, error: Error) => {
      },
      onTaskAdd: (task: M3U8DownloadTask) => {
      },
      onTaskRemove: (task: M3U8DownloadTask) => {
      },
      onTaskComplete: (task: M3U8DownloadTask) => {
      },
      onTaskStatusChanged: (task: M3U8DownloadTask, oldStatus: TaskStatus, newStatus: TaskStatus) => {
      }
    }
    ZDownloader.get(M3U8Downloader).addObserver(observer)
  }

}
