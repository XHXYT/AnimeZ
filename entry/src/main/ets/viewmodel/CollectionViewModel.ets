import VideoCollectionInfo from '../entity/VideoCollectionInfo';
import { VideoCollectionTable } from '../db/impl/VideoCollectionDao';
import Logger from '../utils/Logger';
import { _AnimeState } from '../entryability/AnimeState';

/**
 * 收藏分组：同名不同源的收藏聚合到一组
 */
export class CollectionGroup {
  title: string = ''
  items: VideoCollectionInfo[] = []
}

/**
 * 我的收藏 ViewModel（单例）
 * 从 VideoCollectionPage 抽离的收藏列表加载/删除逻辑。
 */
@ObservedV2
export class CollectionViewModel {

  @Trace collectionList: VideoCollectionInfo[] = []
  @Trace groupedList: CollectionGroup[] = []
  @Trace searchText: string = ''

  private db: VideoCollectionTable | null = null

  private getDB(): VideoCollectionTable {
    if (!this.db) {
      this.db = new VideoCollectionTable(_AnimeState.Context!)
    }
    return this.db
  }

  /**
   * 查询全部收藏（原 VideoCollectionPage.loadCollectionList）
   */
  public async loadCollectionList() {
    const list = await this.getDB().queryAll()
    this.collectionList = list
    this.rebuildGroupedList()
    console.log(`CollectionViewModel 收藏页数据：${JSON.stringify(this.collectionList)}`)
  }

  /**
   * 设置搜索词（TitleBar 搜索框输入回调）
   */
  public setSearchText(text: string) {
    this.searchText = text
    this.rebuildGroupedList()
  }

  /**
   * 按搜索词过滤收藏（匹配标题/手动分组名，忽略大小写）
   */
  public getFilteredList(): VideoCollectionInfo[] {
    const keyword = this.searchText.trim().toLowerCase()
    if (!keyword) {
      return this.collectionList
    }
    return this.collectionList.filter((item: VideoCollectionInfo): boolean => {
      const groupKey = (item.groupTitle ?? '') !== '' ? item.groupTitle : item.title
      return item.title.toLowerCase().includes(keyword) || groupKey.toLowerCase().includes(keyword)
    })
  }

  /**
   * 将过滤后的收藏聚合为一组：手动分组名优先，否则按自身标题；组内按访问时间倒序
   */
  private rebuildGroupedList() {
    const list = this.getFilteredList()
    const groups: CollectionGroup[] = []
    const index: Map<string, CollectionGroup> = new Map<string, CollectionGroup>()
    list.forEach((item: VideoCollectionInfo) => {
      const groupKey = (item.groupTitle ?? '') !== '' ? item.groupTitle : item.title
      let group: CollectionGroup | undefined = index.get(groupKey)
      if (!group) {
        group = new CollectionGroup()
        group.title = groupKey
        group.items = []
        index.set(groupKey, group)
        groups.push(group)
      }
      group.items.push(item)
    })
    groups.forEach((group: CollectionGroup) => {
      group.items.sort((a: VideoCollectionInfo, b: VideoCollectionInfo): number => b.accessTime - a.accessTime)
    })
    this.groupedList = groups
  }

  /**
   * 多选合并：把选中收藏统一归到指定分组名下
   */
  public async mergeSelected(items: VideoCollectionInfo[], groupTitle: string) {
    const ids: number[] = []
    items.forEach((item: VideoCollectionInfo) => {
      if (item.id !== null) {
        ids.push(item.id)
      }
    })
    if (ids.length === 0) {
      return
    }
    await this.getDB().updateGroupTitle(ids, groupTitle)
    await this.loadCollectionList()
  }

  /**
   * 删除单条收藏（原 VideoCollectionPage.deleteCollectionList）
   * 修复原 filter 回调无返回值导致列表被清空的 bug
   */
  public async deleteCollectionListItem(id: number) {
    try {
      await this.getDB().deleteById(id)
      this.collectionList = this.collectionList.filter((value: VideoCollectionInfo): boolean => value.id != id)
      this.rebuildGroupedList()
    } catch (err) {
      Logger.e('fail', `videoCollectionInfoDB 删除 ${id} `, err)
    }
  }
}

export const collectionViewModel: CollectionViewModel = new CollectionViewModel()
