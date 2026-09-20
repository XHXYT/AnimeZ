import SearchHistoryInfo from '../entity/SearchHistoryInfo';
import { SearchHistoryTable } from '../db/impl/SearchHistoryDao';
import { _AnimeState } from '../entryability/AnimeState';

/**
 * 搜索历史 ViewModel（单例，仅负责搜索历史）
 * 搜索结果列表由每页独立的 CategoryViewModel 实例承载。
 */
@ObservedV2
export class SearchViewModel {

  @Trace searchHistoryList: SearchHistoryInfo[] = []

  private db: SearchHistoryTable | null = null

  private getDB(): SearchHistoryTable {
    if (!this.db) {
      this.db = new SearchHistoryTable(_AnimeState.Context!)
    }
    return this.db
  }

  /**
   * 查询全部搜索历史（原 SearchPage.aboutToAppear）
   */
  public async loadHistory() {
    const searchList = await this.getDB().queryAll()
    if (searchList) {
      this.searchHistoryList = searchList
    }
  }

  /**
   * 记录一条搜索历史（原 SearchPage.doSearch 插入逻辑）
   */
  public async addHistory(keyword: string) {
    const result: SearchHistoryInfo = {
      id: null,
      keyword: keyword,
      accessTime: new Date().getTime()
    }
    try {
      const insertId = await this.getDB().insert(result)
      console.log('SearchViewModel #addHistory 插入成功id为：', insertId)
      await this.loadHistory()
    } catch (error) {
      console.error('SearchViewModel #addHistory 插入操作失败: ', error)
    }
  }

  /**
   * 清空搜索历史（原 SearchPage.clearHistory 确认分支）
   */
  public async clearHistory() {
    await this.getDB().clearAll()
    this.searchHistoryList = []
  }
}

export const searchViewModel: SearchViewModel = new SearchViewModel()
