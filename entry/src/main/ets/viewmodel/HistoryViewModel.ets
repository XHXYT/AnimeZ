import VideoHistoryInfo from '../entity/VideoHistoryInfo';
import { VideoHistoryTable } from '../db/impl/VideoHistoryDao';
import { HISTORY_CHANGED_EVENT } from '../utils/EventBus';
import Logger from '../utils/Logger';
import { AnimeState } from '../entryability/AnimeState';

/**
 * 观看历史 ViewModel（单例）
 * 修复原 MyPage/VideoHistoryPage 各自订阅 HISTORY_CHANGED_EVENT 且 off() 全局互踢的问题：
 * VM 常驻订阅，@Trace historyList 供所有读取处自动刷新（替代幽灵 key HistoryList）。
 */
@ObservedV2
export class HistoryViewModel {

  @Trace historyList: VideoHistoryInfo[] = []

  private db: VideoHistoryTable | null = null

  constructor() {
    // 常驻订阅历史记录变更事件
    HISTORY_CHANGED_EVENT.on(() => {
      this.loadHistoryList()
    })
  }

  private getDB(): VideoHistoryTable {
    if (!this.db) {
      this.db = new VideoHistoryTable(AnimeState.Context!)
    }
    return this.db
  }

  /**
   * 查询全部历史记录（按访问时间倒序，原 MyPage/VideoHistoryPage.loadHistoryList）
   */
  public async loadHistoryList() {
    const list = await this.getDB().queryAllByAccessTimeDesc()
    if (list) {
      this.historyList = list
      console.log(`HistoryViewModel #loadHistoryList 历史记录项：${JSON.stringify(this.historyList)}`)
    }
  }

  /**
   * 删除单条历史记录（原 VideoHistoryPage.deleteHistoryListItem）
   * 修复原 filter 回调无返回值导致列表被清空的 bug
   */
  public async deleteHistoryListItem(id: number) {
    try {
      await this.getDB().deleteById(id)
      this.historyList = this.historyList.filter(value => value.id != id)
    } catch (err) {
      Logger.e('fail', `videoHistoryInfoDB 删除 ${id} `, err)
    }
  }
}

export const historyViewModel: HistoryViewModel = new HistoryViewModel()
