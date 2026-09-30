import StateView from '../components/StateView';
import { VideoList } from '../components/VideoList';
import { scheduleViewModel } from '../viewmodel/ScheduleViewModel';
import { AnimeState } from '../entryability/AnimeState';

// 星期显示名（下标+1 即 weekday：1=周一..7=周日）
const WEEKDAY_NAMES: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

// 番剧周表页（主页旁的并列 Tab）
@ComponentV2
export struct SchedulePage {

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
          if (scheduleViewModel.scheduleSourceTitle() !== '') {
            Blank()
            Text(scheduleViewModel.scheduleSourceTitle())
              .fontSize(13)
              .fontColor($r('app.color.color_text_minor'))
              .maxLines(1)
              .constraintSize({ maxWidth: '40%' })
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
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
      // 左右滑动优先切换星期（子Tab），而不是联动外层主Tab切换
      .gesture(PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
        .onActionEnd((event: GestureEvent) => {
          const dx = event.offsetX
          if (dx < -30) {
            // 左滑：下一个星期
            if (scheduleViewModel.selectedWeekday < 7) {
              scheduleViewModel.selectWeekday(scheduleViewModel.selectedWeekday + 1)
            }
          } else if (dx > 30) {
            // 右滑：上一个星期
            if (scheduleViewModel.selectedWeekday > 1) {
              scheduleViewModel.selectWeekday(scheduleViewModel.selectedWeekday - 1)
            }
          }
        }))
    }
    .width('100%')
    .height('100%')
    .hideToolBar(true)
    .backgroundColor($r('app.color.background_color'))
    .padding({ top: AnimeState.topRectHeight, bottom: AnimeState.bottomRectHeight - 20 })
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
