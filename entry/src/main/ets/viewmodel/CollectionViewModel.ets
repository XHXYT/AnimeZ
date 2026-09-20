import VideoCollectionInfo from '../entity/VideoCollectionInfo';
import { VideoCollectionTable } from '../db/impl/VideoCollectionDao';
import Logger from '../utils/Logger';
import { _AnimeState } from '../entryability/AnimeState';

/**
 * 我的收藏 ViewModel（单例）
 * 从 VideoCollectionPage 抽离的收藏列表加载/删除逻辑。
 */
@ObservedV2
export class CollectionViewModel {

  @Trace collectionList: VideoCollectionInfo[] = []

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
    console.log(`CollectionViewModel 收藏页数据：${JSON.stringify(this.collectionList)}`)
  }

  /**
   * 删除单条收藏（原 VideoCollectionPage.deleteCollectionList）
   * 修复原 filter 回调无返回值导致列表被清空的 bug
   */
  public async deleteCollectionListItem(id: number) {
    try {
      await this.getDB().deleteById(id)
      this.collectionList = this.collectionList.filter(value => value.id != id)
    } catch (err) {
      Logger.e('fail', `videoCollectionInfoDB 删除 ${id} `, err)
    }
  }
}

export const collectionViewModel: CollectionViewModel = new CollectionViewModel()
