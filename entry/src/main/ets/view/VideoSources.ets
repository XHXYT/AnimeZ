import { DataSourceConfig } from "../api/DataSourceConfig"
import { VideoSourcesViewModel, SortType } from "../viewmodel/VideoSourcesViewModel"
import StateView from "../components/StateView"
import TitleBar from "../components/TitleBar"
import { ButtonBuilder, ButtonConfig, MenuItem } from "../components/common/Button"
import { LengthMetrics } from "@kit.ArkUI"
import { AppConfigs } from "../entryability/Settings"

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

  @Consume('pageStack') pageStack: NavPathStack
  // 顶部避让高度
  @StorageProp('topRectHeight') topHeight: number = 0
  // 底部避让高度
  @StorageProp('bottomRectHeight') bottomHeight: number = 0
  // 宽度断点
  @StorageLink('currentWidthBreakpoint') widthBp: WidthBreakpoint = 1
  // 高度断点
  @StorageLink('currentHeightBreakpoint') heightBp: HeightBreakpoint = 0

  // 功能按钮
  private controlButtons: ButtonConfig[] = [
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
      menuSelected: this.appSettings.video_sources_group_filter,
      fontColor: $r('app.color.color_text_major'),
      action: () => {
        this.updateGroupButtonMenu()
      },
      menuItems: [
        {
          name: '分组管理',
          value: 'group_manage',
          action: () => {

          }
        },
        {
          name: '不分组',
          value: 'not_filter',
          action: () => {
            this.viewModel.setGroupType('not_filter')
          }
        },
        {
          name: '已启用',
          value: 'enabled',
          action: () => {
            this.viewModel.setGroupType('enabled')
          }
        },
        {
          name: '已禁用',
          value: 'disabled',
          action: () => {
            this.viewModel.setGroupType('disabled')
          }
        },
      ]
    },
    { // 更多按钮
      symbolSrc: 'dot_grid_2x2', // Symbol 图标
      iconSize: 24,
      fontColor: $r('app.color.color_text_major'),
      menuItems: [
        {
          name: '重置为默认配置',
          value: 'reset',
          symbolStart: 'arrow_clockwise',
          action: () => {
            this.viewModel.resetToDefault()
          }
        },
        {
          name: '添加新数据源',
          value: 'add',
          symbolStart: 'plus_circle',
          action: () => {
            this.viewModel.goToSourceDetail(true)
          }
        }
      ]
    }
  ]

  aboutToAppear() {
    this.onShow = false
    this.viewModel.pageStack = this.pageStack
    this.viewModel.appSettings = this.appSettings
    this.viewModel.initialize()
    this.viewModel.loadCustomGroups()
    setTimeout(() => {
      this.updateGroupButtonMenu()
    }, 500)
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

        // 编辑工具栏
        if (this.viewModel.selectMode) {
          this.EditToolbar()
        }
      }
    }
    .padding({top: this.topHeight - 20, bottom: this.bottomHeight - 20})
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
    Column() {
      // 列表内容
      List() {
        ForEach(this.viewModel.videoSources, (item: DataSourceConfig) => {
          // 普通数据项
          ListItem() {
            this.SourceItem(item)
          }
        })
      }
      .layoutWeight(1)
    }
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
        .margin({ top: 8, bottom: 8})
        .onChange((value: string) => {
          this.viewModel.setSearchText(value)
        })
      // 遍历并渲染其余按钮
      ForEach(this.controlButtons, (config: ButtonConfig) => {
        ButtonBuilder({
          config: config,
          menuSelected: config.menuSelected
        })
      })
    }
    .backgroundColor($r('app.color.background_color_accent'))
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

        Text(`${item.group || '未分组'} | 优先级: ${item.priority}`)
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
    .width('100%')
    .padding(16)
    .onClick(() => {
      if (this.viewModel.selectMode) {
        this.viewModel.toggleItemSelection(item)
      } else {
        // 点击跳转到详情页
        this.pageStack.pushPathByName('VideoSourceDetail', null, true)
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

  // 更新分组按钮的菜单项
  private updateGroupButtonMenu() {
    const groupButton = this.controlButtons[1] // 分组按钮
    // 保留前4个默认项
    const defaultItems = groupButton.menuItems?.slice(0, 4) || []
    // 添加自定义分组
    const customItems: MenuItem[] = this.viewModel.customGroups.map(group => ({
      name: group.name,
      value: group.value,
      action: () => {
        this.viewModel.setGroupType(group.value)
        this.appSettings.video_sources_group_filter = group.value
      }
    } as MenuItem))
    groupButton.menuItems = [...defaultItems, ...customItems]
    // 替换菜单列表
    this.controlButtons.splice(1, 1, groupButton)
  }

}
