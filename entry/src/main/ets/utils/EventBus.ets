import emitter from '@ohos.events.emitter';

export interface Event {

  on(callback: (data: emitter.EventData, priority?: emitter.EventPriority) => void): void

  once(callback: (data: emitter.EventData, priority?: emitter.EventPriority) => void): void

  emit(priority?: emitter.EventPriority, data?: emitter.EventData): void

  off(): void

}

export class EventImpl implements Event {
  private readonly eventId: number;

  constructor(eventId: number) {
    this.eventId = eventId
  }

  on(callback: (data: emitter.EventData) => void, priority: emitter.EventPriority = emitter.EventPriority.LOW): void {
    emitter.on({ eventId: this.eventId, priority: priority }, callback);
  }

  once(callback: (data: emitter.EventData) => void, priority: emitter.EventPriority = emitter.EventPriority.LOW): void {
    emitter.once({ eventId: this.eventId, priority: priority }, callback);
  }

  emit(priority: emitter.EventPriority = emitter.EventPriority.LOW, data: emitter.EventData): void {
    if (data) {
      emitter.emit({ eventId: this.eventId, priority: priority }, data)
    } else {
      emitter.emit({ eventId: this.eventId, priority: priority })
    }
  }

  off(): void {
    emitter.off(this.eventId)
  }
}

/**
 * 首页数据源改变
 */
export const SOURCE_CHANGED_EVENT: Event = new EventImpl(1)

/**
 * 历史记录改变
 */
export const HISTORY_CHANGED_EVENT: Event = new EventImpl(2)

/**
 * 视频数据源改变
 */
export const VIDEO_SOURCE_EVENT: Event = new EventImpl(3)

/**
 * 应用接续恢复进度
 */
export const APP_RESUME_PROGRESS_EVENT: Event = new EventImpl(4)

/**
 * 播放器后端切换（data.resumePos 为切换前播放位置毫秒，用于续播）
 */
export const PLAYER_SWITCH_EVENT: Event = new EventImpl(5)

/**
 * 打开播放设置面板（非全屏时由播放器控制层发出，详情页用简介同款半模态面板展示）
 */
export const PLAYER_SETTINGS_EVENT: Event = new EventImpl(6)

/**
 * 周表数据源改变（设置页"周表数据源"选择后发出，周表页按新源重新加载）
 */
export const SCHEDULE_SOURCE_CHANGED_EVENT: Event = new EventImpl(7)

/**
 * 应用主窗口不可见（锁屏/退后台，EntryAbility 由主窗口 windowEvent 转发）
 */
export const WINDOW_HIDDEN_EVENT: Event = new EventImpl(8)