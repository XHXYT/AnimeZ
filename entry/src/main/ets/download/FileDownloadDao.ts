import DownloadTaskInfo from './DownloadTaskInfo';
import Logger from '../utils/Logger';
import { ValueType } from '../db/AbsTable';
import AutoTable from '../db/AutoTable';
import { Table } from '../db/decorator/Decorators';
import { Context } from '@kit.AbilityKit';

/**
 * 下载任务数据库和数据库表
 */
@Table({ db: 'download_manager', name: 'download_tasks' })
export class FileDownloadTable extends AutoTable<DownloadTaskInfo> {

  constructor(context: Context) {
    super(context, 'download_manager', 'download_tasks');
    // 添加 Context 调试
    Logger.d(this, 'Context type: ' + context.constructor.name);
    Logger.d(this, 'Context object: ' + JSON.stringify(context));
    Logger.d(this, 'Context bundleName: ' + context.processName);
    // 检查关键属性
    if (context.applicationInfo) {
      if (canIUse("SystemCapability.BundleManager.BundleFramework.Core")) {
        Logger.d(this, 'Application name: ' + context.applicationInfo.name);
      } else {
      }
    }
  }

  protected getEntityClass(): new (...args: any[]) => DownloadTaskInfo {
    return DownloadTaskInfo;
  }

  /**
   * 获取主键列名
   */
  getColumnId(): string {
    return 'taskId'
  }

  /**
   * 获取实体ID值
   */
  getEntityId(item: DownloadTaskInfo): ValueType {
    return item.taskId
  }

  // 业务方法保持不变
  async queryById(taskId: number): Promise<DownloadTaskInfo> {
    Logger.d(this, 'queryById taskId=' + taskId)
    let items = await this.query(this.getPredicates().equalTo('taskId', taskId))
    return items[0]
  }

  async queryAllByParentId(parentTaskId: number): Promise<DownloadTaskInfo[]> {
    Logger.d(this, 'queryAllByParentId parentTaskId = ' + parentTaskId)
    try {
      await this.futureDb;
      Logger.d(this, 'Database ready for query');
    } catch (error) {
      Logger.e('fail', 'Database not ready ', error);
      return [];
    }
    return this.query(this.getPredicates().equalTo('parentTaskId', parentTaskId))
  }

  async save(item: DownloadTaskInfo): Promise<number> {
    Logger.d(this, 'save item=' + JSON.stringify(item))
    let info = await this.queryById(item.taskId)
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

