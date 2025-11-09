
import Logger from '../../utils/Logger';
import { Table } from '../decorator/Decorators';
import AbsTable from '../AbsTable';
import { ValuesBucket, ValueType } from '../AbsTable';
import rdb from '@ohos.data.relationalStore';
import { VideoCollectionInfo } from '../../entity/VideoCollectionInfo';

/**
 * 视频播放历史记录
 * TODO 通过装饰器配置数据库表信息
 * TODO 支持数据源key和数据源title
 */
@Table({ db: 'video_manager', name: 'video_collection' })
export class VideoCollectionTable extends AbsTable<VideoCollectionInfo> {
  getColumnId(): string {
    return "link"
  }

  getTableColumns(): string[] {
    return ['link', 'title', 'coverUrl', 'sourceKey', 'accessTime']
  }

  getCreateTableSql(): string {
    return "CREATE TABLE IF NOT EXISTS video_collection(link TEXT, title TEXT, coverUrl TEXT, sourceKey TEXT, accessTime INTEGER, PRIMARY KEY(link))"
  }

  getEntityId(item: VideoCollectionInfo): ValueType {
    return item.link
  }

  createItem(cursor: rdb.ResultSet): VideoCollectionInfo {
    let info: VideoCollectionInfo = {
      id: null,
      link: '',
      title: '',
      coverUrl: '',
      sourceKey: '',
      accessTime: 0
    }
    info['link'] = cursor.getString(cursor.getColumnIndex('link'))
    info['title'] = cursor.getString(cursor.getColumnIndex('title'))
    info['coverUrl'] = cursor.getString(cursor.getColumnIndex('coverUrl'))
    info['sourceKey'] = cursor.getString(cursor.getColumnIndex('sourceKey'))
    info['accessTime'] = cursor.getLong(cursor.getColumnIndex('accessTime'))
    return info
  }

  async queryBySrc(link: string): Promise<VideoCollectionInfo> {
    let items = await this.query(this.getPredicates().equalTo('link', link))
    return items[0]
  }

  async save(item: VideoCollectionInfo): Promise<number> {
    Logger.d(this, 'save item=' + JSON.stringify(item))
    let info = await this.queryBySrc(item.link)
    Logger.d(this, 'save info=' + JSON.stringify(info))
    let result;
    if (info) {
      result = await this.update(item)
    } else {
      result = await this.insert(item)
    }
    Logger.d(this, 'saveOrUpdate result=' + result)
    return result
  }

}