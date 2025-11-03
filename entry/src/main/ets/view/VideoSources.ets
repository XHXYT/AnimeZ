import { DataSourceConfig, ParserConfig } from "../api/DataSourceConfig"
import { VideoSourcesViewModel, SortType } from "../viewmodel/VideoSourcesViewModel"
import StateView from "../components/StateView"
import TitleBar from "../components/TitleBar"
import { ButtonBuilder, ButtonConfig, MenuItem } from "../components/common/Button"
import { LengthMetrics } from "@kit.ArkUI"
import { AppConfigs } from "../entryability/Settings"
import { GroupManager } from "./VideoSourcesGroupManager"
import { ToastUtil } from "../utils/ToastUtils"

// 系统路由 - 视频源
@Builder
export function VideoSourcesBuilder(name: string, param: string) {
  VideoSources()
}

@Component
struct VideoSources {

  // 应用设置
  @StorageLink('AppSettings') appSettings: AppConfigs = new AppConfigs()
  @State viewModel: VideoSourcesViewModel = new VideoSourcesViewModel()
  // 添加搜索控制器
  private searchController: SearchController = new SearchController()
  @State errorMessage: string = this.viewModel.errorMessage
  @State state: number = this.viewModel.state

  @Consume onShow: boolean
  @Consume DarkModeImage: boolean
  @State showGroupManager: boolean = false

  @Consume('pageStack') pageStack: NavPathStack
  // 顶部避让高度
  @StorageProp('topRectHeight') topHeight: number = 0
  // 底部避让高度
  @StorageProp('bottomRectHeight') bottomHeight: number = 0
  // 宽度断点
  @StorageLink('currentWidthBreakpoint') widthBp: WidthBreakpoint = 1
  // 高度断点
  @StorageLink('currentHeightBreakpoint') heightBp: HeightBreakpoint = 0

  aboutToAppear() {
    this.onShow = false
    this.viewModel.pageStack = this.pageStack
    this.viewModel.appSettings = this.appSettings
    // 初始化分组数据
    this.viewModel.loadCustomGroups()
    // 初始化数据源
    this.viewModel.initialize()
  }

  aboutToDisappear() {
    this.viewModel.dispose()
    this.onShow = true
  }

  build() {
    NavDestination() {
      Column() {
        // 标题栏
        TitleBar({
          title: '视频源',
          button: () => {
            this.ControlBar()
          }
        })
        // 内容区域
        StateView({
          state: this.state,
          errorMessage: this.errorMessage,
          content: () => {
            this.VideoSourcesContent()
          },
          custom: undefined,
          onRetry: () => {
            this.viewModel.initialize()
            return true
          }
        })
          .width('100%')
          .layoutWeight(1)
      }
      .bindSheet($$this.showGroupManager, this.GroupManager(), {
        detents: [SheetSize.LARGE],
        showClose: true,
        dragBar: false,
        backgroundColor: $r('app.color.color_card'),
        keyboardAvoidMode: SheetKeyboardAvoidMode.RESIZE_ONLY,
        scrollSizeMode: ScrollSizeMode.CONTINUOUS,
        preferType: SheetType.CENTER,
        onWillDismiss: ((DismissSheetAction: DismissSheetAction) => {
          console.debug("模态弹窗关闭原因：", DismissSheetAction.reason)
          DismissSheetAction.dismiss()
        }),
        onWillAppear: () => {
        },
        onDisappear: async () => {
        }
      })
    }
    .padding({top: this.topHeight - 15, bottom: this.bottomHeight - 15})
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
    .onBackPressed(() => {
      return this.viewModel.handleBackPressed()
    })
  }

  @Builder
  VideoSourcesContent() {
    SourcesList({
      viewModel: this.viewModel,
      goDetail: (isNew: boolean, config?: DataSourceConfig) => {
        this.goToSourceDetail(isNew, config)
      }
    })
  }

  @Builder
  ControlBar() {
    Flex({
      direction: FlexDirection.Row,
      alignItems: ItemAlign.Center,
      space: { main: LengthMetrics.vp(12) }
    }) {
      // 搜索框
      Search({ placeholder: '搜索视频源', controller: this.searchController })
        .margin({ top: 24, bottom: 24})
        .height(36)
        .onChange((value: string) => {
          this.viewModel.setSearchText(value)
        })
      // 遍历并渲染其余按钮
      ForEach(this.getControlButtons(), (config: ButtonConfig) => {
        ButtonBuilder({
          config: config,
          menuSelected: config.menuSelected
        })
      })
    }
    .backgroundColor($r('app.color.background_color_accent'))
  }

  @Builder
  GroupManager() {
    GroupManager({ viewModel: this.viewModel })
  }

  @Builder
  GroupHeaderItem(item: DataSourceConfig) {
    Row() {
      Text(item.name)
        .fontSize(16)
        .fontColor($r('app.color.color_text_major'))
        .fontWeight(FontWeight.Bold)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.background_color_accent'))
  }

  getControlButtons() {
    // 加载自定义分组
    const customItems: MenuItem[] = this.viewModel.customGroups.map(group => ({
      name: group,
      value: group,
      action: () => {
        this.viewModel.setGroupType(group)
      }
    } as MenuItem))
    const controlButtons: ButtonConfig[] = [
      { // 排序按钮
        symbolSrc: 'mobiledata_circle', // Symbol 图标
        iconSize: 24,
        menuSelected: this.appSettings.video_sources_order,
        menuTitle: '排列顺序',
        fontColor: $r('app.color.color_text_major'),
        menuItems: [
          {
            name: '按优先级',
            value: SortType.PRIORITY,
            action: () => {
              this.viewModel.setSortType(SortType.PRIORITY)
            }
          },
          {
            name: '按名称',
            value: SortType.NAME,
            action: () => {
              this.viewModel.setSortType(SortType.NAME)
            }
          },
          {
            name: '按状态',
            value: SortType.ENABLED,
            action: () => {
              this.viewModel.setSortType(SortType.ENABLED)
            }
          },
          {
            name: '智能排序',
            value: SortType.CUSTOM,
            action: () => {
              this.viewModel.setSortType(SortType.CUSTOM)
            }
          }
        ]
      },
      { // 分组按钮
        symbolSrc: 'satellite_map', // Symbol 图标
        iconSize: 24,
        menuTitle: '分组筛选',
        prohibitValue: 'group_manage',
        menuSelected: this.appSettings.video_sources_group_filter,
        fontColor: $r('app.color.color_text_major'),
        menuItems: [
          {
            name: '分组管理',
            value: 'group_manage',
            action: () => {
              this.showGroupManager = true
            }
          },
          {
            name: '不分组',
            value: '不分组',
            action: () => {
              this.viewModel.setGroupType('不分组')
            }
          },
          {
            name: '已启用',
            value: '已启用',
            action: () => {
              this.viewModel.setGroupType('已启用')
            }
          },
          {
            name: '已禁用',
            value: '已禁用',
            action: () => {
              this.viewModel.setGroupType('已禁用')
            }
          },
          ...customItems
        ]
      },
      { // 更多按钮
        symbolSrc: 'dot_grid_2x2', // Symbol 图标
        iconSize: 24,
        fontColor: $r('app.color.color_text_major'),
        menuItems: [
          {
            name: '添加新数据源',
            value: 'add',
            symbolStart: 'plus_circle',
            action: () => {
              this.goToSourceDetail(true)
            }
          },
          {
            name: '本地导入',
            value: 'import_file',
            symbolStart: 'plus_circle',
            action: () => {

            }
          },
          {
            name: '网络导入',
            value: 'import_url',
            symbolStart: 'plus_circle',
            action: () => {
              ToastUtil.showToast({message: '开发中'})
            }
          },
          {
            name: '二维码导入',
            value: 'import_qr',
            symbolStart: 'plus_circle',
            action: () => {
              ToastUtil.showToast({message: '开发中'})
            }
          },
          {
            name: '批量管理',
            value: 'batch_manage',
            symbolStart: 'square_and_square',
            action: () => {
              this.viewModel.toggleSelectionMode()
            }
          },
          {
            name: '重置为默认配置',
            value: 'reset',
            symbolStart: 'arrow_clockwise',
            action: () => {
              this.viewModel.resetToDefault()
            }
          },
        ]
      }
    ]

    return controlButtons
  }

  goToSourceDetail(isNew: boolean, config?: DataSourceConfig) {
    if (isNew) {
      const newSource: DataSourceConfig = {
        key: 'new', // new标识
        name: '',
        group: '',
        baseUrl: '',
        version: 1,
        enabled: true,
        priority: 100,
        description: '',
        defaultSource: false,
        parserConfig: {} as ParserConfig
      }
      this.pageStack.pushPathByName('VideoSourceDetail', newSource, true)
    } else {
      // 编辑现有数据源
      this.pageStack.pushPathByName('VideoSourceDetail', config, true)
    }
  }

}


@Component
struct SourcesList {

  @ObjectLink viewModel: VideoSourcesViewModel
  goDetail: (isNew: boolean, config?: DataSourceConfig) => void = () => {}

  build() {
    Column() {
      // 列表内容
      List({space: 12}) {
        ForEach(this.viewModel.videoSources, (item: DataSourceConfig) => {
          // 普通数据项
          ListItem() {
            this.SourceItem(item)
          }
        })
      }
      .layoutWeight(1)
      .margin({ left: 16, right: 16})
      // 编辑工具栏
      if (this.viewModel.selectMode) {
        this.EditToolbar()
      }
    }
  }

  @Builder
  SourceItem(item: DataSourceConfig) {
    Row() {
      // 选择框
      if (this.viewModel.selectMode) {
        Image(this.viewModel.selectionManager.isSelect(item) ?
          $r('app.media.ic_selection_selected') :
          $r('app.media.ic_selection_none'))
          .width(24)
          .height(24)
          .margin({ right: 12 })
      }
      // 数据源信息
      Column() {
        Text(item.name)
          .fontSize(16)
          .fontColor($r('app.color.color_text_major'))
        Text(`${item.group || '未分组'} | ${item.version}`)
          .fontSize(12)
          .fontColor($r('app.color.color_text_minor'))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      // 状态标识
      if (item.defaultSource) {
        Text('默认')
          .fontSize(12)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.primary_color_accent'))
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(4)
          .margin({ right: 8 })
      }
      if (!item.enabled) {
        Text('已禁用')
          .fontSize(12)
          .fontColor($r('app.color.color_text_minor'))
          .margin({ right: 8 })
      }
    }
    .padding(16)
    .width('100%')
    .borderRadius(16)
    .backgroundColor($r('app.color.background_color'))
    .onClick(() => {
      if (this.viewModel.selectMode) {
        this.viewModel.toggleItemSelection(item)
      } else {
        // 点击跳转到详情页
        this.goDetail(false, item)
      }
    })
  }

  @Builder
  EditToolbar() {
    Row() {
      Row() {
        Image(this.viewModel.hasSelectAll ?
          $r('app.media.ic_selection_selected') :
          $r('app.media.ic_selection_none'))
          .width(24)
          .height(24)
          .fillColor(this.viewModel.hasSelectAll ?
            $r('app.color.primary_color_accent') :
            $r('app.color.color_text_minor'))
        Text(this.viewModel.hasSelectAll ? '全不选' : '全选')
          .fontColor($r('app.color.color_text_major'))
          .fontSize(14)
          .margin({ left: 8 })
      }
      .margin({ left: 16 })
      .onClick(() => {
        this.viewModel.toggleSelectAll()
      })

      Blank()

      Text(`删除(${this.viewModel.selectCount})`)
        .fontColor(this.viewModel.selectCount == 0 ?
          $r('app.color.color_text_minor') : Color.Red)
        .fontSize(14)
        .margin({ right: 16 })
        .onClick(() => {
          this.viewModel.deleteSelectedItems()
        })
    }
    .width('100%')
    .height(42)
  }

}
