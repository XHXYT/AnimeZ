import Logger from '../../utils/Logger';
import { MyTable } from '../decorator/Decorators';
import { Table } from '../decorator/Decorators';
import AbsTable from '../AbsTable';
import { ValuesBucket, ValueType } from '../AbsTable';
import rdb from '@ohos.data.relationalStore';
import { SearchHistoryInfo } from '../../entity/SearchHistoryInfo';

/**
 * 视频搜索记录
 */
@Table({ db: 'video_manager', name: 'search_history' })
export class SearchHistoryTable extends AbsTable<SearchHistoryInfo> {
  getColumnId(): string {
    return "id"
  }

  getTableColumns(): string[] {
    return ['id', 'keyword', 'accessTime']
  }

  getCreateTableSql(): string {
    return "CREATE TABLE IF NOT EXISTS search_history(id INTEGER PRIMARY KEY AUTOINCREMENT, keyword TEXT, accessTime INTEGER)"
  }

  bindToValuesBucket(bucket: ValuesBucket, item: SearchHistoryInfo) {
    this.getTableColumns().forEach((col) => {
      bucket[col] = item[col]
    })
  }

  getEntityId(item: SearchHistoryInfo): ValueType {
    return item.id
  }

  createItem(cursor: rdb.ResultSet): SearchHistoryInfo {
    let info: SearchHistoryInfo = {
      id: cursor.getLong(cursor.getColumnIndex('id')),
      keyword: cursor.getString(cursor.getColumnIndex('keyword')),
      accessTime: cursor.getLong(cursor.getColumnIndex('accessTime'))
    }
    return info
  }

  async queryAll(): Promise<SearchHistoryInfo[]> {
    return this.query(this.getPredicates().orderByDesc('accessTime'), this.getTableColumns())
  }

  async saveOrUpdate(keyword: string): Promise<number> {
    Logger.d(this, 'saveOrUpdate keyword=' + keyword)
    let results = await this.query(this.getPredicates().equalTo('keyword', keyword))
    Logger.d(this, 'saveOrUpdate results=' + JSON.stringify(results))
    let result;
    if (!results || results.length == 0) {
      result = await this.insert({
        keyword: keyword,
        accessTime: new Date().getTime(),
        id: null
      })
    } else {
      let info = results[0]
      Logger.d(this, 'saveOrUpdate info=' + JSON.stringify(info))
      result = await this.update({
        id: info.id,
        keyword: keyword,
        accessTime: new Date().getTime()
      }, this.getPredicates().equalTo('keyword', keyword))
    }
    Logger.d(this, 'saveOrUpdate result=' + result)
    return result
  }
}