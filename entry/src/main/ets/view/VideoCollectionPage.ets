import Logger from '../utils/Logger';
import { CoverImage } from '../components/CoverImage';
import { OnSelectChangeObserver, SelectionManager } from '../utils/SelectionManager';
import StateView, { ViewState } from '../components/StateView';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { DEFAULT_DURATION } from '../utils/TransitionHelper';
import TitleBar, { TitleBarButton } from '../components/TitleBar';
import { VideoNavigateInfo } from '../entity/VideoNavigateInfo';
import { dataSourceManager } from '../api/DataSourceManager';
import { ToastUtil } from '../utils/ToastUtils';
import VideoCollectionInfo from '../entity/VideoCollectionInfo';
import { AnimeState } from '../entryability/AnimeState';
import { CollectionGroup, collectionViewModel } from '../viewmodel/CollectionViewModel';
import { sourceBadgeColor } from '../utils/SourceBadgeUtils';
import { CustomContentDialog } from '@kit.ArkUI';
import { ButtonOptions } from '@ohos.arkui.advanced.Dialog';
import { appSettings } from '../entryability/Settings';

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
  @Local expandedTitle: string = ''

  @Local selectionManager: SelectionManager<VideoCollectionInfo> = new SelectionManager<VideoCollectionInfo>()

  @Local mergeCandidateTitles: string[] = []
  @Local mergeTitleIndex: number = 0
  @Local mergeDialog: CustomDialogController | undefined = undefined
  private mergePendingItems: VideoCollectionInfo[] = []

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
      this.hasSelectAll = this.selectCount == collectionViewModel.getFilteredList().length
    }
  }

  aboutToAppear() {
    AnimeState.onShow = false
    collectionViewModel.loadCollectionList()
    this.selectionManager.addObserver(this.selectionObserver)
    this.selectMode = this.selectionManager.isSelectionMode()

    const mergeDialogButtons: ButtonOptions[] = [
      {
        value: '取消',
        buttonStyle: ButtonStyleMode.TEXTUAL,
        fontColor: $r('app.color.primary_color'),
        action: () => {
          this.mergeDialog?.close()
        }
      },
      {
        value: '确定',
        buttonStyle: ButtonStyleMode.EMPHASIZED,
        action: () => {
          this.confirmMerge()
        }
      }
    ]
    this.mergeDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: '合并收藏',
        secondaryTitle: '选择用作番剧名称的标题',
        contentBuilder: (): void => {
          this.mergeTitleContent()
        },
        buttons: mergeDialogButtons,
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 },
        themeColorMode: appSettings.color_mode,
      }),
      autoCancel: false,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
    })
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
        searchPlaceholder: '搜索我的收藏',
        onSearchChange: (value: string) => {
          collectionViewModel.setSearchText(value)
        },
        buttons: this.editButtons
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
              this.selectionManager.selectItems(collectionViewModel.getFilteredList())
            }
          })

          Blank()
          Text(`合并(${this.selectCount})`)
            .fontColor(this.selectCount < 2 ? $r('app.color.color_text_minor') : $r('app.color.primary_color'))
            .fontSize(14)
            .margin({ right: 16 })
            .onClick(() => {
              this.openMergeDialog()
            })
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
                        if (item.id !== null) {
                          collectionViewModel.deleteCollectionListItem(item.id)
                        }
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
    .padding({top: AnimeState.topRectHeight, bottom: AnimeState.bottomRectHeight - 20})
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
      if (this.expandedTitle !== '') {
        ToastUtil.animateTo({ duration: 200 }, () => {
          this.expandedTitle = ''
        })
        return true
      }
      return false
    })
    .onShown(() => {
      collectionViewModel.loadCollectionList()
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

  private navigateToDetail(item: VideoCollectionInfo) {
    const params: VideoNavigateInfo = {
      // 收藏表 id 不是历史表 id，传 null；续播信息由详情页检索历史表获得
      id: null,
      url: item.link,
      sourceKey: item.sourceKey,
      title: item.title,
      cover: item.coverUrl
    }
    console.log('VideoTest 视频收藏页传递的params：', JSON.stringify(params))
    AnimeState.pushPage("VideoDetailPage", params)
  }

  private toggleGroupSelect(group: CollectionGroup) {
    const allSelected = group.items.every((item: VideoCollectionInfo): boolean => this.selectionManager.isSelect(item))
    if (allSelected) {
      this.selectionManager.unselectItems(group.items)
    } else {
      this.selectionManager.selectItems(group.items)
    }
  }

  private handleGroupClick(group: CollectionGroup) {
    if (this.selectionManager.isSelectionMode()) {
      this.toggleGroupSelect(group)
      return
    }
    if (group.items.length === 1) {
      this.navigateToDetail(group.items[0])
      return
    }
    animateTo({ duration: 200 }, () => {
      this.expandedTitle = this.expandedTitle === group.title ? '' : group.title
    })
  }

  private deleteGroup(group: CollectionGroup) {
    group.items.forEach((item: VideoCollectionInfo) => {
      if (item.id !== null) {
        collectionViewModel.deleteCollectionListItem(item.id)
      }
    })
  }

  private confirmDeleteGroup(group: CollectionGroup) {    if (group.items.length <= 1) {
      animateTo({ duration: 200 }, () => {
        this.deleteGroup(group)
      })
      return
    }
    this.getUIContext().showAlertDialog(
      {
        title: '移除收藏动漫',
        message: `《${group.title}》的收藏包含${group.items.length}个视频源，确认全部移除？`,
        primaryButton: {
          value: '取消',
          action: () => {
          }
        },
        secondaryButton: {
          value: '确定',
          fontColor: Color.Red,
          action: () => {
            this.deleteGroup(group)
            ToastUtil.showToast({ message: '删除成功' })
          }
        }
      }
    )
  }

  @Builder CollectionList() {
    List({space: 16}) {
      ForEach(collectionViewModel.groupedList, (group: CollectionGroup) => {
        ListItem() {
          CollectionGroupItem({
            group: group,
            selectionManager: this.selectionManager,
            isExpanded: this.expandedTitle === group.title,
            onRowClick: () => {
              this.handleGroupClick(group)
            },
            onToggleSelect: () => {
              this.toggleGroupSelect(group)
            },
            onSourceClick: (item: VideoCollectionInfo) => {
              this.navigateToDetail(item)
            },
            onSourceEntryClick: (item: VideoCollectionInfo) => {
              this.navigateToDetail(item)
            }
          })
        }
        .swipeAction({
          end: {
            builder: () => { this.swipeActionEnd(group) },
            // 侧滑到一定距离会触发 onAction
            onAction: () => {
              this.confirmDeleteGroup(group)
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
            this.toggleGroupSelect(group)
          })
        )
      }, (group: CollectionGroup) => `${group.title}_${group.items.map((it: VideoCollectionInfo): string => `${it.id ?? 0}`).join('_')}`)
    }
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height('100%')
    .layoutWeight(1)
    .padding({top: 4, bottom: 16})
  }

  @Builder
  swipeActionEnd(group: CollectionGroup) {
    Row() {
      Button("删除")
        .type(ButtonType.Normal)
        .height('100%')
        .aspectRatio(1)
        .backgroundColor('#FF5E5D')
        .onClick(() => {
          this.confirmDeleteGroup(group)
        })
    }
    .height('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
  }

  private openMergeDialog() {
    const items = Array.from(this.selectionManager.getSelections())
    if (items.length < 2) {
      ToastUtil.showToast({ message: '至少选择两项收藏' })
      return
    }
    const titles: string[] = []
    items.forEach((item: VideoCollectionInfo) => {
      const name = (item.groupTitle ?? '') !== '' ? item.groupTitle : item.title
      if (!titles.includes(name)) {
        titles.push(name)
      }
    })
    this.mergePendingItems = items
    this.mergeCandidateTitles = titles
    this.mergeTitleIndex = 0
    this.mergeDialog?.open()
  }

  private confirmMerge() {
    this.mergeDialog?.close()
    const items = this.mergePendingItems
    const groupTitle = this.mergeCandidateTitles[this.mergeTitleIndex] ?? ''
    if (items.length < 2 || groupTitle === '') {
      return
    }
    this.doMerge(items, groupTitle)
  }

  private async doMerge(items: VideoCollectionInfo[], groupTitle: string) {
    try {
      await collectionViewModel.mergeSelected(items, groupTitle)
      ToastUtil.showToast({ message: '合并成功' })
      this.selectionManager.toggleSelectionMode()
    } catch (err) {
      Logger.e('fail', 'merge favorites failed', err)
      ToastUtil.showToast({ message: '合并失败' })
    }
  }

  @Builder
  mergeTitleContent() {
    Column({ space: 8 }) {
      ForEach(this.mergeCandidateTitles, (title: string, index: number) => {
        Row() {
          Text(title)
            .fontSize(16)
            .fontColor(index === this.mergeTitleIndex ? $r('app.color.primary_color') : $r('app.color.color_text_major'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (index === this.mergeTitleIndex) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(20)
              .fontColor([$r('app.color.primary_color')])
          }
        }
        .width('100%')
        .constraintSize({ minHeight: 48 })
        .borderRadius(12)
        .backgroundColor(index === this.mergeTitleIndex ? $r('app.color.background_color') : Color.Transparent)
        .padding({ left: 12, right: 12 })
        .onClick(() => {
          this.mergeTitleIndex = index
        })
      }, (title: string) => title)
    }
    .width('100%')
    .constraintSize({ maxHeight: 320 })
  }

}

/**
 * 收藏分组项：同名多源聚合行 + 展开的源入口列表
 */
@ComponentV2
struct CollectionGroupItem {

  @Require @Param group: CollectionGroup
  @Require @Param selectionManager: SelectionManager<VideoCollectionInfo>
  @Require @Param isExpanded: boolean
  @Event onRowClick: () => void = () => {}
  @Event onToggleSelect: () => void = () => {}
  @Event onSourceClick: (item: VideoCollectionInfo) => void = (item: VideoCollectionInfo) => {}
  @Event onSourceEntryClick: (item: VideoCollectionInfo) => void = (item: VideoCollectionInfo) => {}

  @Local isSelected: boolean = false
  @Local selectionMode: boolean = false
  @Local selectionIconMargin: number = 0
  @Local selectionIconSize: number = 0

  private static readonly MAX_SOURCE_BADGES: number = 3

  build() {
    Column() {
      Row() {
        Image(this.isSelected ? $r('app.media.ic_selection_selected') : $r('app.media.ic_selection_none'))
          .width(this.selectionIconSize)
          .height(this.selectionIconSize)
          .margin({ left: this.selectionIconMargin })
          .visibility(this.selectionMode ? Visibility.Visible : Visibility.None)
          .fillColor(this.isSelected ? $r('app.color.primary_color') : $r('app.color.color_text_minor'))
        CoverImage({ imgUrl: this.primaryItem().coverUrl })
          .height('100%')
          .margin({left: 16})
          .aspectRatio(1.5)
          .borderRadius(8)
          .clip(true)
          .shadow({ radius: 12, color: AnimeState.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#000000' : '#aaaaaa', offsetX: 6, offsetY: 6 })
        Column() {
          Text(this.group.title)
            .alignSelf(ItemAlign.Start)
            .fontColor($r('app.color.color_text_major'))
            .fontSize(16)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Column() {
            Text(new Date(this.primaryItem().accessTime).toLocaleDateString())
              .alignSelf(ItemAlign.Start)
              .margin({ top: 4 })
              .fontSize(12)
              .fontColor($r('app.color.color_text_minor'))
              .maxLines(1)
            Row() {
              ForEach(this.visibleSourceItems(), (item: VideoCollectionInfo, index: number) => {
                Text(this.sourceTitle(item.sourceKey))
                  .padding(4)
                  .fontSize(10)
                  .borderRadius(4)
                  .backgroundColor(sourceBadgeColor(item.sourceKey))
                  .fontColor(Color.White)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: '30%' })
                  .margin({ left: index === 0 ? 0 : 4 })
                  .onClick(() => {
                    if (this.selectionMode) {
                      this.onToggleSelect()
                    } else {
                      this.onSourceClick(item)
                    }
                  })
              }, (item: VideoCollectionInfo) => `${item.id}`)
              if (this.hiddenSourceCount() > 0) {
                Text(`+${this.hiddenSourceCount()}`)
                  .fontSize(10)
                  .fontColor($r('app.color.color_text_minor'))
                  .margin({ left: 4 })
                  .alignSelf(ItemAlign.Center)
              }
            }
            .width('100%')
            .margin({ top: 4 })
          }
        }
        .height('100%')
        .layoutWeight(1)
        .margin({ left: 12, right: 16 })
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
      .height(80)
      .onClick(() => {
        this.onRowClick()
      })

      if (this.isExpanded && !this.selectionMode && this.group.items.length > 1) {
        Column({ space: 4 }) {
          ForEach(this.group.items, (item: VideoCollectionInfo) => {
            Row() {
              Text(this.sourceTitle(item.sourceKey))
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .fontSize(11)
                .borderRadius(4)
                .backgroundColor(sourceBadgeColor(item.sourceKey))
                .fontColor(Color.White)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: '50%' })
              Text(new Date(item.accessTime).toLocaleDateString())
                .fontSize(11)
                .fontColor($r('app.color.color_text_minor'))
                .margin({ left: 8 })
              Blank()
              Text('›')
                .fontSize(16)
                .fontColor($r('app.color.color_text_minor'))
            }
            .width('100%')
            .height(42)
            .borderRadius(8)
            .backgroundColor($r('app.color.background_color'))
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.onSourceEntryClick(item)
            })
          }, (item: VideoCollectionInfo) => `${item.id}`)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ top: 8 })
        .transition(TransitionEffect.OPACITY)
      }
    }
    .width('100%')
  }

  private primaryItem(): VideoCollectionInfo {
    return this.group.items[0]
  }

  private sourceTitle(sourceKey: string): string {
    return dataSourceManager.getSourceTitle(sourceKey) ?? sourceKey
  }

  private visibleSourceItems(): VideoCollectionInfo[] {
    const count: number = Math.min(this.group.items.length, CollectionGroupItem.MAX_SOURCE_BADGES)
    return this.group.items.slice(0, count)
  }

  private hiddenSourceCount(): number {
    return this.group.items.length - Math.min(this.group.items.length, CollectionGroupItem.MAX_SOURCE_BADGES)
  }

  private refreshSelectedState() {
    this.isSelected = this.group.items.length > 0 &&
      this.group.items.every((item: VideoCollectionInfo): boolean => this.selectionManager.isSelect(item))
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
      if (this.group.items.some((it: VideoCollectionInfo): boolean => it.id === item.id)) {
        Logger.d('tips', 'onSelectChange isSelect = ' + isSelected)
        this.refreshSelectedState()
      }
    }
  }

  aboutToAppear() {
    Logger.d('tips', 'aboutToAppear')
    this.selectionManager.addObserver(this.selectionObserver)
    this.refreshSelectedState()
    this.selectionMode = this.selectionManager.isSelectionMode()
    if (this.selectionMode) {
      this.selectionIconSize = 24
      this.selectionIconMargin = 16
    }
  }

  aboutToDisappear() {
    Logger.d('tips', 'aboutToDisappear')
    this.selectionManager.removeObserver(this.selectionObserver)
  }

}
