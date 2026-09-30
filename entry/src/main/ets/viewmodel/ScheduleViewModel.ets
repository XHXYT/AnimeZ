import VideoInfo from '../entity/VideoInfo';
import { ViewState } from '../components/StateView';
import { SOURCE_CHANGED_EVENT, SCHEDULE_SOURCE_CHANGED_EVENT, VIDEO_SOURCE_EVENT } from '../utils/EventBus';
import Logger from '../utils/Logger';
import { dataSourceManager } from '../api/DataSourceManager';
import { appSettings } from '../entryability/Settings';

/** 今天对应的星期（1-7，周一=1；周日 getDay()=0 映射为 7） */
function todayWeekday(): number {
  const day = new Date().getDay()
  return day === 0 ? 7 : day
}

/**
 * 周表 ViewModel（单例）
 * 周表源独立于首页源：由设置"周表数据源"指定（appSettings.schedule_source_key），
 * 未选择或所选源失效时空态引导；常驻订阅源变更/周表源切换事件，按天懒加载并缓存。
 */
@ObservedV2
export class ScheduleViewModel {

  @Trace selectedWeekday: number = todayWeekday()
  @Trace state: number = ViewState.CUSTOM
  @Trace errorMessage: string = ''
  @Trace videoList: VideoInfo[] = []

  // 按天缓存（非渲染状态，无需观测；源切换时整体清空）
  private cache: Map<number, VideoInfo[]> = new Map()

  constructor() {
    const reload = () => {
      this.cache.clear()
      this.load(false)
    }
    // 周表源切换：按新源重新加载
    SCHEDULE_SOURCE_CHANGED_EVENT.on(reload)
    // 首页源变化可能伴随源列表增删改（导入/更新/删除），周表源可用性随之变化
    SOURCE_CHANGED_EVENT.on(reload)
    VIDEO_SOURCE_EVENT.on(reload)
  }

  /** 当前生效的周表源 key（未选择或已失效返回 ''） */
  scheduleSourceKey(): string {
    const key = appSettings.schedule_source_key
    if (key !== '' && dataSourceManager.hasScheduleConfig(key)) {
      return key
    }
    return ''
  }

  /** 当前周表源名称（周表页顶栏展示；无有效源返回 ''） */
  scheduleSourceTitle(): string {
    const key = this.scheduleSourceKey()
    return key !== '' ? (dataSourceManager.getSourceTitle(key) || '') : ''
  }

  /** 页面显示时调用：已加载则不重复请求 */
  ensureLoaded() {
    if (this.state === ViewState.CUSTOM || this.state === ViewState.LOADING) {
      this.load(false)
    }
  }

  /** 切换星期（命中缓存直接展示） */
  selectWeekday(weekday: number) {
    if (weekday === this.selectedWeekday) {
      return
    }
    this.selectedWeekday = weekday
    this.load(false)
  }

  /** 强制刷新当天（错误重试场景） */
  refresh() {
    this.load(true)
  }

  private load(force: boolean) {
    // 未配置任何视频源：引导导入配置
    if (dataSourceManager.getAllDataSourceConfigs().length === 0) {
      this.state = ViewState.EMPTY
      this.errorMessage = '请导入配置后使用'
      return
    }
    // 未选择周表源：空态引导去设置/源编辑页选择
    if (appSettings.schedule_source_key === '') {
      this.state = ViewState.EMPTY
      this.errorMessage = '未选择周表数据源，可在 设置-周表数据源 或源编辑页勾选"周表"选择'
      return
    }
    // 所选源已删除/停用/未配置周表规则：空态提示重新选择
    const sourceKey = this.scheduleSourceKey()
    if (sourceKey === '') {
      this.state = ViewState.EMPTY
      this.errorMessage = '当前周表源不可用（未配置周表规则或已停用），请重新选择'
      return
    }
    const cached = force ? undefined : this.cache.get(this.selectedWeekday)
    if (cached) {
      this.videoList = cached
      this.state = ViewState.CONTENT
      return
    }
    this.state = ViewState.LOADING
    dataSourceManager.getSchedule(this.selectedWeekday, sourceKey)
      .then((list: VideoInfo[]) => {
        this.cache.set(this.selectedWeekday, list)
        this.videoList = list
        if (list.length === 0) {
          this.state = ViewState.EMPTY
          this.errorMessage = '当天暂无番剧更新'
        } else {
          this.state = ViewState.CONTENT
        }
      })
      .catch((e: Error) => {
        this.errorMessage = e.message
        this.state = ViewState.ERROR
        Logger.e('fail', '周表数据加载', e)
      })
  }
}

export const scheduleViewModel: ScheduleViewModel = new ScheduleViewModel()
