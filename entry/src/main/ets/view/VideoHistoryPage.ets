import { HISTORY_CHANGED_EVENT } from '../utils/EventBus';
import Logger from '../utils/Logger';
import { OnSelectChangeObserver, SelectionManager } from '../utils/SelectionManager';
import VideoTimeUtils from '../utils/VideoTimeUtils';
import StateView, { ViewState } from '../components/StateView';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { DEFAULT_DURATION } from '../utils/TransitionHelper';
import TitleBar, { TitleBarButton } from '../components/TitleBar';
import { VideoNavigateInfo } from '../entity/VideoNavigateInfo';
import { ToastUtil } from '../utils/ToastUtils';
import VideoHistoryInfo from '../entity/VideoHistoryInfo';
import { AnimeState } from '../entryability/AnimeState';
import { historyViewModel } from '../viewmodel/HistoryViewModel';
import { dataSourceManager } from '../api/DataSourceManager';
import { sourceBadgeColor } from '../utils/SourceBadgeUtils';

// 系统路由
@Builder
export function VideoHistoryPageBuilder(name: string, param: Object) {
  VideoHistoryPage()
}


@ComponentV2
struct VideoHistoryPage {
  @Local selectMode: boolean = false
  @Local selectCount: number = 0
  @Local hasSelectAll: boolean = false

  @Local selectionManager: SelectionManager<VideoHistoryInfo> = new SelectionManager<VideoHistoryInfo>()

  /** 页面展示态由 VM 数据推导（原 state 镜像的 EMPTY/CONTENT 逻辑） */
  private get viewState(): number {
    return historyViewModel.historyList.length == 0 ? ViewState.EMPTY : ViewState.CONTENT
  }

  private readonly selectionObserver: OnSelectChangeObserver<VideoHistoryInfo> = {
    onSelectionModeChange: (isSelectionMode: boolean) => {
      this.selectMode = isSelectionMode
      if (!this.selectMode) {
        this.selectCount = 0
      }
    },
    onSelectChange: (item: VideoHistoryInfo, isSelected) => {
      this.selectCount = this.selectionManager.getSelectionCount()
      this.hasSelectAll = this.selectCount == historyViewModel.historyList.length
    }
  }

  aboutToAppear() {
    AnimeState.onShow = false
    this.selectionManager.addObserver(this.selectionObserver)
    this.selectMode = this.selectionManager.isSelectionMode()
    // 幂等刷新，保证进入页面数据新鲜（VM 常驻订阅事件，跨页存活）
    historyViewModel.loadHistoryList()
  }

  aboutToDisappear() {
    this.selectionManager.removeObserver(this.selectionObserver)
    AnimeState.onShow = true
  }


  build() {
    NavDestination() {
      // 标题栏
      TitleBar({
        title: '观看历史',
        buttons: this.editButtons
      })

      StateView({
          state: this.viewState,
          errorMessage: '',
          content: () => {
            this.HistoryList()
          },
          onRetry: () => {
            historyViewModel.loadHistoryList()
            return true;
          }
        })
        .width('100%')
        .layoutWeight(1)
      // 编辑列表
      if (this.selectMode) {
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
              this.selectionManager.selectItems(historyViewModel.historyList)
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
                  title: '移除历史记录',
                  message: `确认移除选中的${this.selectCount}项历史记录？`,
                  primaryButton: {
                    value: '取消',
                    action: () => {
                    }
                  },
                  secondaryButton: {
                    value: '确定',
                    fontColor: Color.Red,
                    action: async () => {
                      const data = Array.from(this.selectionManager.getSelections())
                      const total = data.filter(item => item.id).length;
                      let completed = 0;
                      await Promise.all(
                        data.map(async (item) => {
                          if (item.id) {
                            await historyViewModel.deleteHistoryListItem(item.id);
                            completed++;
                            ToastUtil.showToast({
                              message: `删除进度: ${completed}/${total}`
                            });
                          }
                        })
                      );
                      ToastUtil.showToast({ message: `${completed}删除成功，${total - completed}项失败` })
                      this.selectionManager.toggleSelectionMode()
                      // 触发历史记录更新事件
                      HISTORY_CHANGED_EVENT.emit()
                    }
                  }
                }
              )

            })
        }
        .width('100%')
        .height(42)
      }

    }
    .padding({top: AnimeState.topRectHeight - 20, bottom: AnimeState.bottomRectHeight - 20})
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
    .onBackPressed(() => {
      if (this.selectionManager.isSelectionMode()) {
        this.selectionManager.toggleSelectionMode()
        return true
      }
      return false
    })
  }

  private get editButtons(): TitleBarButton[] {
    if (this.viewState != ViewState.CONTENT) {
      return []
    }
    return [
      {
        image: this.selectMode ? $r('app.media.ic_edit_cancel') : $r('app.media.ic_edit'),
        iconSize: 24,
        action: () => {
          this.selectionManager.toggleSelectionMode()
        }
      }
    ]
  }

  @Builder
  HistoryList() {
    List({space: 16}) {
      ForEach(historyViewModel.historyList, (item: VideoHistoryInfo) => {
        ListItem() {
          HistoryItem({selectionManager: this.selectionManager, item: item})
        }
        .onClick(() => {
          if (this.selectionManager.isSelectionMode()) {
            this.selectionManager.toggleSelectItem(item)
            return
          }
          const params: VideoNavigateInfo = {
            id: item.id,
            url: item.link as string,
            sourceKey: item.sourceKey,
            title: item.title,
            cover: item.coverUrl as string
          }
          console.log('VideoTest 历史记录页传递的params：', JSON.stringify(params))
          AnimeState.pageStack.pushPathByName("VideoDetailPage", params)
        })
        .swipeAction({
          end: {
            builder: () => { this.swipeActionEnd(item.id) },
            // 侧滑到一定距离会触发 onAction
            onAction: () => {
              ToastUtil.animateTo({ duration: 1000 }, () => {
                // 侧滑删除
                historyViewModel.deleteHistoryListItem(item.id)
              })
            },
            // onAction 侧滑距离
            actionAreaDistance: 56,
          },
          edgeEffect: SwipeEdgeEffect.None
        })
        .gesture(LongPressGesture({ repeat: false })
          .onAction((event) => {
            Logger.e('tips', 'onLongPress')
            // 长按多选
            if (!this.selectionManager.isSelectionMode()) {
              this.selectionManager.toggleSelectionMode()
            }
            this.selectionManager.toggleSelectItem(item)
          })
        )
      })
    }
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height('100%')
    .layoutWeight(1)
    .padding({top: 4, bottom: 16})
  }

  @Builder
  swipeActionEnd(id: number) {
    Row() {
      Button("删除")
        .type(ButtonType.Normal)
        .height('100%')
        .aspectRatio(1)
        .backgroundColor('#FF5E5D')
        .onClick(() => {
          // 删除列表行
          historyViewModel.deleteHistoryListItem(id)
        })
    }
    .height('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
  }

}

/**
 * 历史记录项
 */
@ComponentV2
struct HistoryItem {

  @Require @Param item: VideoHistoryInfo
  @Require @Param selectionManager: SelectionManager<VideoHistoryInfo>
  @Local isSelected: boolean = false
  @Local selectionMode: boolean = false
  @Local selectionIconMargin: number = 0
  @Local selectionIconSize: number = 0

  private readonly selectionObserver: OnSelectChangeObserver<VideoHistoryInfo> = {
    onSelectionModeChange: (isSelectionMode: boolean) => {
      if (isSelectionMode) {
        this.selectionMode = true
        ToastUtil.animateTo({
          duration: DEFAULT_DURATION,
          curve: Curve.ExtremeDeceleration,
          iterations: 1,
          playMode: PlayMode.Normal
        }, () => {
          this.selectionIconSize = 24
          this.selectionIconMargin = 16
        })
      } else {
        ToastUtil.animateTo({
          duration: DEFAULT_DURATION,
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
    onSelectChange: (item: VideoHistoryInfo, isSelected) => {
      if (this.item && this.item.link == item.link) {
        Logger.d('tips', 'onSelectChange isSelect = ' + isSelected)
        this.isSelected = isSelected
      }
    }
  }

  aboutToAppear() {
    Logger.d('tips', 'aboutToAppear')
    this.selectionManager.addObserver(this.selectionObserver)
    this.isSelected = this.selectionManager.isSelect(this.item)
  }

  aboutToDisappear() {
    Logger.d('tips', 'aboutToDisappear')
    this.selectionManager.removeObserver(this.selectionObserver)
  }

  private get sourceTitle(): string {
    return dataSourceManager.getSourceTitle(this.item.sourceKey) ?? ''
  }


  build() {
    Row() {
      Image(this.isSelected ? $r('app.media.ic_selection_selected') : $r('app.media.ic_selection_none'))
        .width(this.selectionIconSize)
        .height(this.selectionIconSize)
        .margin({ left: this.selectionIconMargin })
        .visibility(this.selectionMode ? Visibility.Visible : Visibility.None)
        .fillColor(this.isSelected ? $r('app.color.primary_color') : $r('app.color.color_text_minor') )
      Image(this.item.coverUrl)
        .alt($r('app.media.pic_load_failed'))
        .objectFit(ImageFit.Cover)
        .height('100%')
        .margin({left: 16})
        .aspectRatio(1.5)
        .borderRadius(8)
        .shadow({
          radius: 12,
          color: AnimeState.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#000000' : '#aaaaaa',
          offsetX: 6, offsetY: 6 })

      Column() {
        Text(this.item.title)
          .alignSelf(ItemAlign.Start)
          .fontColor($r('app.color.color_text_major'))
          .fontSize(16)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
        Text(this.item.episodeName)
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 4 })
          .fontSize(12)
          .fontColor($r('app.color.color_text_minor'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 8 }) {
          Text(VideoTimeUtils.stringForTime(this.item.currentTime) + ' / ' + VideoTimeUtils.stringForTime(this.item.totalTime))
            .fontSize(12)
            .fontColor($r('app.color.color_text_minor'))
            .maxLines(1)
            .layoutWeight(1)
          if (this.sourceTitle !== '') {
            Text(this.sourceTitle)
              .fontSize(10)
              .fontColor(sourceBadgeColor(this.item.sourceKey))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '60%' })
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
              .backgroundColor('#33808080')
          }
        }
        .alignItems(VerticalAlign.Center)
      }
      .height('100%')
      .layoutWeight(1)
      .margin({ left: 12, right: 16 })
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .height(80)
  }
}
