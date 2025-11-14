
import Logger from '../../utils/Logger';
import VideoCollectionInfo from '../../entity/VideoCollectionInfo';
import { Context } from '@kit.AbilityKit';
import { Table } from '../decorator/Decorators';
import AutoTable from '../AutoTable';
import { ValueType } from '@kit.ArkData';

/**
 * 视频收藏记录
 */
@Table({ db: 'video_manager', name: 'video_collection' })
export class VideoCollectionTable extends AutoTable<VideoCollectionInfo> {

  constructor(context: Context) {
    super(context, 'video_manager', 'video_collection');
  }

  protected getEntityClass(): new (...args: any[]) => VideoCollectionInfo {
    return VideoCollectionInfo;
  }

  /**
   * 获取主键列名 - 改为 id
   */
  getColumnId(): string {
    return 'id'
  }

  /**
   * 获取实体ID值
   */
  getEntityId(item: VideoCollectionInfo): ValueType {
    return item.id
  }

  /**
   * 根据链接查询（保持原有业务逻辑）
   */
  async queryByLink(link: string): Promise<VideoCollectionInfo> {
    Logger.d(this, 'queryByLink link = ' + link)
    let items = await this.query(this.getPredicates().equalTo('link', link))
    return items[0]
  }

  /**
   * 保存或更新（根据link判断是否存在）
   */
  async save(item: VideoCollectionInfo): Promise<number> {
    Logger.d(this, 'save item = ' + JSON.stringify(item))
    let existingItem = await this.queryByLink(item.link)
    Logger.d(this, 'save existingItem=' + JSON.stringify(existingItem))
    let result;
    if (existingItem) {
      // 设置id，然后更新
      item.id = existingItem.id
      result = await this.update(item)
    } else {
      // id设为null，让数据库自增
      item.id = null
      result = await this.insert(item)
    }
    Logger.d(this, 'save result=' + result)
    return result
  }

  /**
   * 根据ID删除
   */
  async deleteById(id: number): Promise<number> {
    Logger.d(this, 'deleteById id = ' + id)
    return this.deleteItem(this.getPredicates().equalTo('id', id))
  }

  /**
   * 根据链接删除
   */
  async deleteByLink(link: string): Promise<number> {
    Logger.d(this, 'deleteByLink link = ' + link)
    return this.deleteItem(this.getPredicates().equalTo('link', link))
  }

  /**
   * 根据标题查询收藏记录
   */
  async queryByTitle(title: string): Promise<VideoCollectionInfo[]> {
    Logger.d(this, 'queryByTitle title=' + title)
    // 使用模糊查询
    let items = await this.query(this.getPredicates().like('title', `%${title}%`))
    return items
  }

  /**
   * 根据标题精确查询
   */
  async queryByTitleExact(title: string): Promise<VideoCollectionInfo[]> {
    Logger.d(this, 'queryByTitleExact title=' + title)

    // 精确匹配
    let items = await this.query(this.getPredicates().equalTo('title', title))
    return items
  }

  /**
   * 根据标题查询单条记录（取第一条）
   */
  async queryOneByTitle(title: string): Promise<VideoCollectionInfo> {
    Logger.d(this, 'queryOneByTitle title=' + title)

    let items = await this.queryByTitleExact(title)
    return items[0] || null
  }

}
