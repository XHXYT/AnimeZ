import StateView from '../components/StateView';
import { VideoList } from '../components/VideoList';
import { scheduleViewModel } from '../viewmodel/ScheduleViewModel';
import { AnimeState } from '../entryability/AnimeState';
import { MenuSelectPanel, MENU_MAX_VISIBLE, MENU_PANEL_WIDTH } from '../components/CustomListItem';
import { CustomItemInfo, ItemActionType, MenuOption } from '../entity/CusItemInfo';
import { dataSourceManager } from '../api/DataSourceManager';
import { appSettings } from '../entryability/Settings';
import { SCHEDULE_SOURCE_CHANGED_EVENT } from '../utils/EventBus';

// 星期显示名（下标+1 即 weekday：1=周一..7=周日）
const WEEKDAY_NAMES: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

// 番剧周表页（主页旁的并列 Tab）
@ComponentV2
export struct SchedulePage {

  /** 周表源切换菜单是否展示（bindPopup 布尔受控） */
  @Local showSourceMenu: boolean = false
  @Local sourceMenuScroller: Scroller = new Scroller()

  aboutToAppear() {
    scheduleViewModel.ensureLoaded()
  }

  build() {
    NavDestination() {
      Column() {
        // 顶部标题栏
        Row({ space: 12 }) {
          Image($r("app.media.ic_anime"))
            .width(28)
            .height(28)
            .objectFit(ImageFit.Contain)
          Text("番剧周表")
            .fontSize(20)
            .fontWeight(600)
            .fontColor($r('app.color.color_text_major'))
          Blank()
          this.ScheduleSourceEntry()
        }
        .height(56)
        .width('100%')
        .padding({
          left: 16,
          right: AnimeState.windowMode ? Math.max(16, AnimeState.titleButtonWidth + 12) : 16
        })
        .alignItems(VerticalAlign.Center)

        // 星期切换条
        Row() {
          ForEach(WEEKDAY_NAMES, (name: string, index: number) => {
            this.WeekdayItem(name, index + 1)
          }, (name: string, index: number) => name)
        }
        .width('100%')
        .height(44)
        .padding({ left: 8, right: 8 })

        // 当天内容
        StateView(
          {
            state: scheduleViewModel.state,
            errorMessage: scheduleViewModel.errorMessage,
            content: () => {
              this.Content()
            },
            onRetry: () => {
              scheduleViewModel.refresh()
              return true;
            }
          }
        )
          .width('100%')
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      // 左右滑动优先切换星期（子Tab）；滑到周界后继续往外滑，联动外层主Tab切换
      .gesture(PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
        .onActionEnd((event: GestureEvent) => {
          const dx = event.offsetX
          if (dx < -30) {
            // 左滑：下一个星期；已在周日则切换主Tab到「我的」
            if (scheduleViewModel.selectedWeekday < 7) {
              scheduleViewModel.selectWeekday(scheduleViewModel.selectedWeekday + 1)
            } else if (AnimeState.currentIndex === 1) {
              AnimeState.tabsController.changeIndex(2)
            }
          } else if (dx > 30) {
            // 右滑：上一个星期；已在周一则切换主Tab到「首页」
            if (scheduleViewModel.selectedWeekday > 1) {
              scheduleViewModel.selectWeekday(scheduleViewModel.selectedWeekday - 1)
            } else if (AnimeState.currentIndex === 1) {
              AnimeState.tabsController.changeIndex(0)
            }
          }
        }))
    }
    .width('100%')
    .height('100%')
    .hideToolBar(true)
    .backgroundColor($r('app.color.background_color'))
    .padding({ top: AnimeState.topRectHeight, /*bottom: AnimeState.bottomRectHeight - 20*/ })
  }

  /** 右上角入口是否展示：已选有效源，或存在可选的周表源 */
  private hasSourceEntry(): boolean {
    return scheduleViewModel.scheduleSourceTitle() !== '' || dataSourceManager.getScheduleSourceKeys().length > 0
  }

  /** 右上角入口文案：已选源显示源名称，未选时引导选择 */
  private sourceEntryText(): string {
    const title = scheduleViewModel.scheduleSourceTitle()
    return title !== '' ? title : '选择周表源'
  }

  /** 周表源菜单项（复用设置页逻辑：已启用且配置了周表规则的源） */
  private scheduleSourceItem(): CustomItemInfo {
    const keys: string[] = dataSourceManager.getScheduleSourceKeys()
    const options: MenuOption[] = keys.length > 0
      ? keys.map((key: string): MenuOption => new MenuOption(key, dataSourceManager.getSourceTitle(key) || key))
      : [new MenuOption('', '暂无可用源')]
    return new CustomItemInfo({
      id: 'schedule_source',
      title: '周表数据源',
      type: ItemActionType.MENU,
      value: scheduleViewModel.scheduleSourceKey(),
      menuOptions: options
    })
  }

  /** 切换周表源（与设置页"周表数据源"一致：写设置并发事件触发重载） */
  private switchScheduleSource(value: string) {
    if (value !== '' && value !== appSettings.schedule_source_key) {
      appSettings.schedule_source_key = value
      SCHEDULE_SOURCE_CHANGED_EVENT.emit()
    }
  }

  @Builder
  ScheduleSourceEntry() {
    if (this.hasSourceEntry()) {
      Row({ space: 2 }) {
        Text(this.sourceEntryText())
          .fontSize(13)
          .fontColor($r('app.color.color_text_minor'))
          .maxLines(1)
          .constraintSize({ maxWidth: '35%' })
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(12)
          .fontColor([$r('app.color.color_text_minor')])
      }
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.showSourceMenu = true
      })
      .bindPopup(this.showSourceMenu, {
        builder: (): void => {
          this.SourceMenuPopup()
        },
        placement: Placement.BottomRight,
        popupColor: Color.Transparent,
        backgroundBlurStyle: BlurStyle.NONE,
        enableArrow: false,
        autoCancel: true,
        width: MENU_PANEL_WIDTH,
        onStateChange: (event) => {
          if (event.isVisible) {
            this.scrollSourceMenuToSelected()
          } else {
            this.showSourceMenu = false
          }
        }
      })
    }
  }

  @Builder
  SourceMenuPopup() {
    MenuSelectPanel({
      item: this.scheduleSourceItem(),
      scroller: this.sourceMenuScroller,
      onSelect: (menu: MenuOption) => {
        // 先收起菜单：切换源会触发整页重渲染，菜单开着会随状态更新重复弹出
        this.showSourceMenu = false
        this.switchScheduleSource(menu.value)
      }
    })
  }

  /** 菜单弹出时把已选周表源滚动到可视区中央（源数量超出最大可见条数才需要滚动） */
  private scrollSourceMenuToSelected(): void {
    const keys: string[] = dataSourceManager.getScheduleSourceKeys()
    if (keys.length <= MENU_MAX_VISIBLE) {
      return
    }
    const index = keys.indexOf(scheduleViewModel.scheduleSourceKey())
    if (index <= 0) {
      return
    }
    // 弹窗内容布局完成后再定位，直接调用时布局未完成会不生效
    setTimeout(() => {
      this.sourceMenuScroller.scrollToIndex(index, false, ScrollAlign.CENTER)
    }, 100)
  }

  @Builder
  WeekdayItem(name: string, weekday: number) {
    Column({ space: 4 }) {
      Text(name)
        .fontSize(14)
        .fontWeight(scheduleViewModel.selectedWeekday === weekday ? 600 : 400)
        .fontColor(scheduleViewModel.selectedWeekday === weekday ? '#007DFF' : $r('app.color.color_text_major'))
      // 选中下划线（未选中时以透明占位保持等高）
      Row()
        .width(16)
        .height(3)
        .borderRadius(2)
        .backgroundColor(scheduleViewModel.selectedWeekday === weekday ? '#007DFF' : Color.Transparent)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      scheduleViewModel.selectWeekday(weekday)
    })
  }

  @Builder
  Content() {
    VideoList({
      videoList: scheduleViewModel.videoList,
      scrollable: true,
      nestedScrollSelfFirst: true
    })
  }

}
