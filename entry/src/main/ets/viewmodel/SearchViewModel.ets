import SearchHistoryInfo from '../entity/SearchHistoryInfo';
import { SearchHistoryTable } from '../db/impl/SearchHistoryDao';
import { _AnimeState } from '../entryability/AnimeState';
import { dataSourceManager } from '../api/DataSourceManager';
import { DataSourceConfig } from '../api/DataSourceConfig';
import { appSettings } from '../entryability/Settings';
import Logger from '../utils/Logger';

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
   * 记录一条搜索历史（相同关键词去重，仅更新访问时间）
   */
  public async addHistory(keyword: string) {
    try {
      await this.getDB().saveOrUpdate(keyword)
      await this.loadHistory()
    } catch (error) {
      Logger.e('fail', 'SearchViewModel #addHistory 插入操作失败: ', error)
    }
  }

  /**
   * 删除指定关键词的搜索历史
   */
  public async deleteHistory(keyword: string) {
    try {
      await this.getDB().deleteByKeyword(keyword)
      await this.loadHistory()
    } catch (error) {
      Logger.e('fail', 'SearchViewModel #deleteHistory 删除操作失败: ', error)
    }
  }

  /**
   * 清空搜索历史（原 SearchPage.clearHistory 确认分支）
   */
  public async clearHistory() {
    await this.getDB().clearAll()
    this.searchHistoryList = []
  }

  /**
   * 获取分组选项（与视频源管理界面的分组保持同步）：
   * 数据源配置中的分组 ∪ 分组管理中持久化的自定义分组
   */
  public getSyncedGroups(): string[] {
    const groupSet = new Set<string>()
    for (const config of dataSourceManager.getAllDataSourceConfigs()) {
      const groups = this.parseGroups(config.group)
      for (const group of groups) {
        groupSet.add(group)
      }
    }
    const savedData = appSettings.video_sources_group_filter_manager
    if (savedData) {
      try {
        const savedGroups = JSON.parse(savedData) as string[]
        if (Array.isArray(savedGroups)) {
          for (const group of savedGroups) {
            if (typeof group === 'string' && group.trim() !== '') {
              groupSet.add(group.trim())
            }
          }
        }
      } catch (error) {
        Logger.e('fail', 'SearchViewModel #getSyncedGroups 解析自定义分组失败: ', error)
      }
    }
    return Array.from(groupSet).sort()
  }

  /**
   * 获取可参与搜索的源配置（已启用，按优先级排序）
   */
  public getSearchableSourceConfigs(): DataSourceConfig[] {
    return dataSourceManager.getPrioritizedDataSourceConfigs()
      .filter((config: DataSourceConfig): boolean => !!config.enabled)
  }

  /**
   * 解析当前设置解析搜索范围对应的数据源 key 列表
   * @returns undefined 表示不限定（全部源/默认策略），空数组以外的数组表示限定范围
   */
  public getSearchSourceKeys(): string[] | undefined {
    const scope = appSettings.search_scope
    if (scope === 'all') {
      return undefined
    }
    if (scope === 'group') {
      const groups = this.parseStringArray(appSettings.search_scope_groups)
      if (groups.length === 0) {
        return undefined
      }
      const keys: string[] = []
      for (const config of this.getSearchableSourceConfigs()) {
        const sourceGroups = this.parseGroups(config.group)
        if (sourceGroups.some((group: string): boolean => groups.includes(group))) {
          keys.push(config.key)
        }
      }
      return keys.length > 0 ? keys : undefined
    }
    if (scope === 'source') {
      const selectedKeys = this.parseStringArray(appSettings.search_scope_sources)
      if (selectedKeys.length === 0) {
        return undefined
      }
      const keys: string[] = []
      for (const config of this.getSearchableSourceConfigs()) {
        if (selectedKeys.includes(config.key)) {
          keys.push(config.key)
        }
      }
      return keys.length > 0 ? keys : undefined
    }
    return undefined
  }

  /**
   * 解析结果屏蔽词（逗号/空格分隔）
   */
  public getBlockWords(): string[] {
    const raw = appSettings.search_block_words
    if (!raw || raw.trim() === '') {
      return []
    }
    return raw.split(/[,，、\s]+/).filter((word: string): boolean => word !== '')
  }

  /**
   * 解析分组字符串为数组（与 VideoSourcesViewModel.parseGroups 一致：空白分隔）
   */
  private parseGroups(groupString: string | undefined): string[] {
    if (!groupString || groupString.trim() === '') {
      return []
    }
    return groupString.trim().split(/\s+/).filter((group: string): boolean => group.trim() !== '')
  }

  /**
   * 解析 JSON 数组字符串为 string[]，异常时返回空数组
   */
  public parseStringArray(json: string): string[] {
    if (!json || json.trim() === '') {
      return []
    }
    try {
      const parsed = JSON.parse(json) as string[]
      if (!Array.isArray(parsed)) {
        return []
      }
      const result: string[] = []
      for (const item of parsed) {
        if (typeof item === 'string' && item.trim() !== '') {
          result.push(item)
        }
      }
      return result
    } catch (error) {
      Logger.e('fail', 'SearchViewModel #parseStringArray 解析失败: ', error)
      return []
    }
  }
}

export const searchViewModel: SearchViewModel = new SearchViewModel()
