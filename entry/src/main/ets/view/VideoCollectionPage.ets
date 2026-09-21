import Logger from '../utils/Logger';
import { OnSelectChangeObserver, SelectionManager } from '../utils/SelectionManager';
import StateView, { ViewState } from '../components/StateView';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { DEFAULT_DURATION } from '../utils/TransitionHelper';
import TitleBar from '../components/TitleBar';
import { VideoNavigateInfo } from '../entity/VideoNavigateInfo';
import { dataSourceManager } from '../api/DataSourceManager';
import { ToastUtil } from '../utils/ToastUtils';
import VideoCollectionInfo from '../entity/VideoCollectionInfo';
import { AnimeState } from '../entryability/AnimeState';
import { collectionViewModel } from '../viewmodel/CollectionViewModel';

// 系统路由
@Builder
export function VideoCollectionPageBuilder(name: string, param: Object) {
  VideoCollectionPage()
}

@ComponentV2
struct VideoCollectionPage {
  @Local selectMode: boolean = false
  @Local selectCount: number = 0
  @Local hasSelectAll: boolean = false

  @Local selectionManager: SelectionManager<VideoCollectionInfo> = new SelectionManager<VideoCollectionInfo>()

  /** 页面展示态由 VM 数据推导（原 state 镜像的 EMPTY/CONTENT 逻辑） */
  private get viewState(): number {
    return collectionViewModel.collectionList.length == 0 ? ViewState.EMPTY : ViewState.CONTENT
  }

  private readonly selectionObserver: OnSelectChangeObserver<VideoCollectionInfo> = {
    onSelectionModeChange: (isSelectionMode: boolean) => {
      this.selectMode = isSelectionMode
      if (!this.selectMode) {
        this.selectCount = 0
      }
    },
    onSelectChange: (item: VideoCollectionInfo, isSelected) => {
      this.selectCount = this.selectionManager.getSelectionCount()
      this.hasSelectAll = this.selectCount == collectionViewModel.collectionList.length
    }
  }

  aboutToAppear() {
    AnimeState.onShow = false
    collectionViewModel.loadCollectionList()
    this.selectionManager.addObserver(this.selectionObserver)
    this.selectMode = this.selectionManager.isSelectionMode()
  }

  aboutToDisappear() {
    this.selectionManager.removeObserver(this.selectionObserver)
    AnimeState.onShow = true
  }

  build() {
    NavDestination() {
      // 标题栏
      TitleBar({
        title: '我的收藏',
        button: () => {
          this.EditButton()
        }
      })

      StateView(
        {
          state: this.viewState,
          errorMessage: '',
          content: () => {
            this.CollectionList()
          },
          onRetry: () => {
            collectionViewModel.loadCollectionList()
            return true;
          }
        }
      )
        .width('100%')
        .layoutWeight(1)
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
              this.selectionManager.selectItems(collectionViewModel.collectionList)
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

              this.getUIContext().showAlertDialog(
                {
                  title: '移除收藏动漫',
                  message: `确认移除选中的${this.selectCount}项收藏动漫？`,
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
                      data.forEach((item: VideoCollectionInfo) => {
                        collectionViewModel.deleteCollectionListItem(item.id)
                      })
                      ToastUtil.showToast({ message: "删除成功" })
                      this.selectionManager.toggleSelectionMode()
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
      // 选择模式返回时优先退出选择模式
      if (this.selectionManager.isSelectionMode()) {
        this.selectionManager.toggleSelectionMode()
        return true
      }
      return false
    })
  }

  @Builder
  EditButton() {
    if (this.viewState == ViewState.CONTENT) {
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

  @Builder CollectionList() {
    List({space: 16}) {
      ForEach(collectionViewModel.collectionList, (item: VideoCollectionInfo) => {
        ListItem() {
          CollectionItem({selectionManager: this.selectionManager, item: item})
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
          console.log('VideoTest 视频收藏页传递的params：', JSON.stringify(params))
          AnimeState.pageStack.pushPathByName("VideoDetailPage", params)
        })
        .swipeAction({
          end: {
            builder: () => { this.swipeActionEnd(item.id) },
            // 侧滑到一定距离会触发 onAction
            onAction: () => {
              animateTo({ duration: 1000 }, () => {
                // 侧滑删除
                collectionViewModel.deleteCollectionListItem(item.id)
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
          collectionViewModel.deleteCollectionListItem(id)
        })
    }
    .height('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
  }

}

/**
 * 收藏项
 */
@ComponentV2
struct CollectionItem {

  @Require @Param item: VideoCollectionInfo
  @Require @Param selectionManager: SelectionManager<VideoCollectionInfo>
  @Local isSelected: boolean = false
  @Local selectionMode: boolean = false
  @Local selectionIconMargin: number = 0
  @Local selectionIconSize: number = 0

  build() {
    Row() {
      Image(this.isSelected ? $r('app.media.ic_selection_selected') : $r('app.media.ic_selection_none'))
        .width(this.selectionIconSize)
        .height(this.selectionIconSize)
        .margin({ left: this.selectionIconMargin })
        .visibility(this.selectionMode ? Visibility.Visible : Visibility.None)
        .fillColor(this.isSelected ? $r('app.color.primary_color') : $r('app.color.color_text_minor'))
      Image(this.item.coverUrl)
        .alt($r('app.media.pic_load_failed'))
        .objectFit(ImageFit.Cover)
        .height('100%')
        .margin({left: 16})
        .aspectRatio(1.5)
        .borderRadius(8)
        .shadow({ radius: 12, color: AnimeState.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#000000' : '#aaaaaa', offsetX: 6, offsetY: 6 })
      Column() {
        Text(this.item.title)
          .alignSelf(ItemAlign.Start)
          .fontColor($r('app.color.color_text_major'))
          .fontSize(16)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Column() {
          Text(new Date(this.item.accessTime).toLocaleDateString())
            .alignSelf(ItemAlign.Start)
            .margin({ top: 4 })
            .fontSize(12)
            .fontColor($r('app.color.color_text_minor'))
            .maxLines(1)
          Text(dataSourceManager.getSourceTitle(this.item.sourceKey))
            .alignSelf(ItemAlign.Start)
            .margin({ top: 4 })
            .padding(4)
            .fontSize(10)
            .borderRadius(4)
            .backgroundColor($r('app.color.primary_color'))
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignSelf(ItemAlign.Start)
      }
      .height('100%')
      .layoutWeight(1)
      .margin({ left: 12, right: 16 })
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .height(80)
  }

  private readonly selectionObserver: OnSelectChangeObserver<VideoCollectionInfo> = {
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
    onSelectChange: (item: VideoCollectionInfo, isSelected) => {
      if (this.item && this.item.id == item.id) {
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

}
