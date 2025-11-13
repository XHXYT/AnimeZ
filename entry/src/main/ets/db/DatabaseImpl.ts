
import IDatabase from './IDatabase';
import AbsTable from './AbsTable';
import Logger from '../utils/Logger';
import 'reflect-metadata';
import Globals from '../utils/Globals';
import { Context } from '@ohos.arkui.UIContext';

/**
 * 缓存数据库中的table
 */
export default class DatabaseImpl implements IDatabase {
    private readonly dbName
    private readonly key
    context: Context

    constructor(dbName: string, context: Context) {
        this.dbName = dbName
        this.context = context
        this.key = "table_map_" + this.dbName
    }

    getTable<T extends AbsTable<any>>(tableClass: { new (context: Context, dbName: string, tableName: string): T }): T {
        return Globals.getOrCreate(this.dbName + '_' + tableClass.name, () => {
            let tableName = Reflect.getMetadata('TableName', tableClass)
            Logger.d(this, 'getTable tableName=' + tableName)
            if (!tableName) {
                throw new Error('table name is empty')
            }
            // 参数顺序：context, dbName, tableName
            return new tableClass(this.context, this.dbName, tableName)
        })
    }

}