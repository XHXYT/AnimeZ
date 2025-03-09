import { HISTORY_CHANGED_EVENT } from '../utils/EventBus';
import Logger from '../utils/Logger';
import { OnSelectChangeObserver, SelectionManager } from '../utils/SelectionManager';
import VideoTimeUtils from '../player/VideoTimeUtils';
import StateView, { ViewState } from '../components/StateView';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { HistoryInfo, VideoHistoryInfo, videoHistoryInfoDB } from '../database/VideoHistoryInfoDB';
import { VideoNavigateInfo } from '../entity/VideoDetailInfo';

// 系统路由
@Builder
export function VideoHistoryPageBuilder(name: string, param: Object) {
  VideoHistoryPage()
}


@Component
struct VideoHistoryPage {
  @Consume onShow: boolean
  @State state: number = 0
  @State errorMessage: string = ''
  @State items: VideoHistoryInfo[] = []
  @State selectMode: boolean = false
  @State selectCount: number = 0
  @State hasSelectAll: boolean = false
  @Consume('pageStack') pageStack: NavPathStack
  // 顶部避让高度
  @StorageProp('topRectHeight') topHeight: number = 0
  // 底部避让高度
  @StorageProp('bottomRectHeight') bottomHeight: number = 0
  private readonly selectionManager: SelectionManager<VideoHistoryInfo> = new SelectionManager<VideoHistoryInfo>()
  private readonly selectionObserver: OnSelectChangeObserver<VideoHistoryInfo> = {
    onSelectionModeChange: (isSelectionMode: boolean) => {
      this.selectMode = isSelectionMode
      if (!this.selectMode) {
        this.selectCount = 0
      }
    },
    onSelectChange: (item: VideoHistoryInfo, isSelected) => {
      this.selectCount = this.selectionManager.getSelectionCount()
      this.hasSelectAll = this.selectCount == this.items.length
    }
  }

  aboutToAppear() {
    this.onShow = false
    this.loadHistoryList()
    this.state = ViewState.CONTENT
    this.selectionManager.addObserver(this.selectionObserver)
    this.selectMode = this.selectionManager.isSelectionMode()
  }

  aboutToDisappear() {
    this.selectionManager.removeObserver(this.selectionObserver)
    this.state = ViewState.CONTENT
    this.onShow = true
  }

  onBackPress() {
    if (this.selectionManager.isSelectionMode()) {
      this.selectionManager.toggleSelectionMode()
      return true
    }
    return false
  }

  onPageShow() {

  }


  build() {
    NavDestination() {
      // 标题栏
      Row({space: 16}) {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(24)
          .fontColor([$r('app.color.color_text_major')])
          .onClick(() => {
            this.pageStack.pop(true)
          })
        Text('观看历史')
          .fontColor($r('app.color.color_text_major'))
          .fontSize(20)
          .fontWeight(500)
          .layoutWeight(1)
          .align(Alignment.Start)
        Blank()

        if (this.state == ViewState.CONTENT) {
          Image(this.selectMode ? $r('app.media.ic_edit_cancel') : $r('app.media.ic_edit'))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.color_text_major'))
            .onClick(() => {
              this.selectionManager.toggleSelectionMode()
            })
        }
      }
      .height(56)
      .width('100%')
      .padding({left: 16, right: 16})

      StateView(
        {
          state: this.state,
          errorMessage: $errorMessage,
          content: () => {
            this.HistoryList()
          },
          custom: undefined,
          onRetry: () => {
            this.loadHistoryList()
            return true;
          }
        }
      )
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
              this.selectionManager.selectItems(this.items)
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

              AlertDialog.show(
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
                    action: () => {
                      const data = Array.from(this.selectionManager.getSelections())
                      data.forEach((item: VideoHistoryInfo) => {
                        this.deleteHistoryList(item.id)
                      })
                      promptAction.showToast({ message: "删除成功" })
                      // 通知历史记录变化
                      HISTORY_CHANGED_EVENT.emit()
                      this.selectionManager.toggleSelectionMode()
                      this.loadHistoryList()
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
    .padding({top: this.topHeight - 20, bottom: this.bottomHeight - 20})
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
  }

  @Builder HistoryList() {
    List({space: 16}) {
      ForEach(this.items, (item: VideoHistoryInfo) => {
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
          this.pageStack.pushPathByName("VideoDetailPage", params)
        })
        .swipeAction({
          end: {
            builder: () => { this.swipeActionEnd(item.id) },
            // 侧滑到一定距离会触发 onAction
            onAction: () => {
              animateTo({ duration: 1000 }, () => {
                // 侧滑删除
                this.deleteHistoryList(item.id)
                this.loadHistoryList()
              })
            },
            // onAction 侧滑距离
            actionAreaDistance: 56,
          },
          edgeEffect: SwipeEdgeEffect.None
        })
        .gesture(LongPressGesture({ repeat: false })
          .onAction((event) => {
            Logger.e(this, 'onLongPress')
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
    .padding({top: 16, bottom: 16})
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
          this.deleteHistoryList(id)
          this.loadHistoryList()
        })
    }
    .height('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
  }

  private async loadHistoryList() {
    // 查询全部历史记录
    const list = await videoHistoryInfoDB.query()
    // 如果有历史记录，回显到页面中
    if (list) {
      // 倒序查询入组
      this.items = list
      console.log('VideoHistoryTest 历史记录页数据：', JSON.stringify(this.items))
      if (this.items.length == 0) {
        this.state = ViewState.EMPTY
      } else {
        this.state = ViewState.CONTENT
      }
    }
  }

  async deleteHistoryList(id: number) {
    await videoHistoryInfoDB.delete(id)
  }

}

/**
 * 历史记录项
 */
@Component
struct HistoryItem {
  @State selectionMode: boolean = false
  @State isSelected: boolean = false
  @State selectionManager: SelectionManager<VideoHistoryInfo> | undefined = undefined
  @State item: VideoHistoryInfo = HistoryInfo
  @State selectionIconMargin: number = 0
  @State selectionIconSize: number = 0
  @StorageProp('currentColorMode') currentMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
  private readonly selectionObserver: OnSelectChangeObserver<VideoHistoryInfo> = {
    onSelectionModeChange: (isSelectionMode: boolean) => {
      if (isSelectionMode) {
        this.selectionMode = true
        animateTo({
          duration: 360,
          curve: Curve.ExtremeDeceleration,
          iterations: 1,
          playMode: PlayMode.Normal
        }, () => {
          this.selectionIconSize = 24
          this.selectionIconMargin = 16
        })
      } else {
        animateTo({
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
    onSelectChange: (item: VideoHistoryInfo, isSelected) => {
      if (this.item && this.item.link == item.link) {
        Logger.e(this, 'onSelectChange isSelect=' + isSelected)
        this.isSelected = isSelected
      }
    }
  }

  aboutToAppear() {
    Logger.e(this, 'aboutToAppear')
    if (this.selectionManager !== undefined) {
      this.selectionManager.addObserver(this.selectionObserver)
      this.isSelected = this.selectionManager.isSelect(this.item)
    }
  }

  aboutToDisappear() {
    Logger.e(this, 'aboutToDisappear')
    if (this.selectionManager !== undefined) {
      this.selectionManager.removeObserver(this.selectionObserver)
    }
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
          color: this.currentMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#000000' : '#aaaaaa',
          offsetX: 6, offsetY: 6 })

      Column() {
        Text(this.item.title)
          .alignSelf(ItemAlign.Start)
          .fontColor($r('app.color.color_text_major'))
          .fontSize(16)
        Blank()
        Text(this.item.episodeName)
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 4 })
          .fontSize(12)
          .fontColor($r('app.color.color_text_minor'))
        Text(VideoTimeUtils.stringForTime(this.item.currentTime) + ' / ' + VideoTimeUtils.stringForTime(this.item.totalTime))
          .alignSelf(ItemAlign.Start)
          .fontSize(12)
          .fontColor($r('app.color.color_text_minor'))
      }
      .height('100%')
      .margin({ left: 12, right: 16 })
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .height(80)
  }
}