import Logger from '../utils/Logger';
import { OnSelectChangeObserver, SelectionManager } from '../utils/SelectionManager';
import StateView, { ViewState } from '../components/StateView';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { DEFAULT_DURATION } from '../utils/TransitionHelper';
import TitleBar from '../components/TitleBar';
import { VideoNavigateInfo } from '../entity/VideoNavigateInfo';
import { dataSourceManager } from '../api/DataSourceManager';
import { ToastUtil } from '../utils/ToastUtils';
import { VideoCollectionTable } from '../db/impl/VideoCollectionDao';
import VideoCollectionInfo from '../entity/VideoCollectionInfo';
import { appContinueModel } from '../viewmodel/AppContinueModel';

// 系统路由
@Builder
export function VideoCollectionPageBuilder(name: string, param: Object) {
  VideoCollectionPage()
}

@Component
struct VideoCollectionPage {
  @Consume onShow: boolean
  @State state: number = 0
  @State errorMessage: string = ''
  @State items: VideoCollectionInfo[] = []
  @State selectMode: boolean = false
  @State selectCount: number = 0
  @State hasSelectAll: boolean = false
  @Consume('pageStack') pageStack: NavPathStack
  // 顶部避让高度
  @StorageProp('topRectHeight') topHeight: number = 0
  // 底部避让高度
  @StorageProp('bottomRectHeight') bottomHeight: number = 0
  // 当前颜色模式
  @StorageLink('currentColorMode') currentMode: number = 1
  @StorageProp('UIContext') UIContext: UIContext = this.getUIContext()

  @State selectionManager: SelectionManager<VideoCollectionInfo> = new SelectionManager<VideoCollectionInfo>()

  private videoCollectionInfoDB = new VideoCollectionTable(this.getUIContext().getHostContext()!)
  private readonly selectionObserver: OnSelectChangeObserver<VideoCollectionInfo> = {
    onSelectionModeChange: (isSelectionMode: boolean) => {
      this.selectMode = isSelectionMode
      if (!this.selectMode) {
        this.selectCount = 0
      }
    },
    onSelectChange: (item: VideoCollectionInfo, isSelected) => {
      this.selectCount = this.selectionManager.getSelectionCount()
      this.hasSelectAll = this.selectCount == this.items.length
    }
  }

  aboutToAppear() {
    this.onShow = false
    this.loadCollectionList()
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
          state: this.state,
          errorMessage: $errorMessage,
          content: () => {
            this.CollectionList()
          },
          custom: undefined,
          onRetry: () => {
            this.loadCollectionList()
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

              this.UIContext.showAlertDialog(
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
                        this.deleteCollectionList(item.id)
                      })
                      ToastUtil.showToast({ message: "删除成功" })
                      this.selectionManager.toggleSelectionMode()
                      this.loadCollectionList()
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

  @Builder
  EditButton() {
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

  @Builder CollectionList() {
    List({space: 16}) {
      ForEach(this.items, (item: VideoCollectionInfo) => {
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
          this.pageStack.pushPathByName("VideoDetailPage", params)
          appContinueModel.jumpVideoDetail("VideoDetailPage", params)
        })
        .swipeAction({
          end: {
            builder: () => { this.swipeActionEnd(item.id) },
            // 侧滑到一定距离会触发 onAction
            onAction: () => {
              animateTo({ duration: 1000 }, () => {
                // 侧滑删除
                this.deleteCollectionList(item.id)
                this.loadCollectionList()
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
          this.deleteCollectionList(id)
          this.loadCollectionList()
        })
    }
    .height('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
  }

  private async loadCollectionList() {
    const list = await this.videoCollectionInfoDB.queryAll()
    // 如果有历史记录，回显到页面中
    // 查询入组
    this.items = list
    console.log('VideoCollectionTest 收藏页数据：', JSON.stringify(this.items))
    if (this.items.length == 0) {
      this.state = ViewState.EMPTY
    } else {
      this.state = ViewState.CONTENT
    }
  }

  async deleteCollectionList(id: number) {
    try {
      await this.videoCollectionInfoDB.deleteById(id)
      this.items = this.items.filter(value => { value.id != id })
    } catch (err) {
      Logger.e('fail', `videoCollectionInfoDB 删除 ${id} `, err)
    }
  }

}

/**
 * 收藏项
 */
@Component
struct CollectionItem {

  @State selectionMode: boolean = false
  @State isSelected: boolean = false
  @StorageLink('currentColorMode') currentMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
  @Link selectionManager: SelectionManager<VideoCollectionInfo>
  @State selectionIconMargin: number = 0
  @State selectionIconSize: number = 0
  @Prop item: VideoCollectionInfo

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
        .shadow({ radius: 12, color: this.currentMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#000000' : '#aaaaaa', offsetX: 6, offsetY: 6 })
      Column() {
        Text(this.item.title)
          .alignSelf(ItemAlign.Start)
          .fontColor($r('app.color.color_text_major'))
          .fontSize(16)
        Column() {
          Text(new Date(this.item.accessTime).toLocaleDateString())
            .alignSelf(ItemAlign.Start)
            .margin({ top: 4 })
            .fontSize(12)
            .fontColor($r('app.color.color_text_minor'))
          Text(dataSourceManager.getSourceTitle(this.item.sourceKey))
            .alignSelf(ItemAlign.Start)
            .margin({ top: 4 })
            .padding(4)
            .fontSize(10)
            .borderRadius(4)
            .backgroundColor($r('app.color.primary_color'))
            .fontColor(Color.White)
        }
        .alignSelf(ItemAlign.Start)
      }
      .height('100%')
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