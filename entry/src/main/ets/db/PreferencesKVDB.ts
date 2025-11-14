import { distributedKVStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { Context } from '@kit.AbilityKit';


class PreferencesKVDB {
  private kvManager: distributedKVStore.KVManager | undefined = undefined;
  private kvStore: distributedKVStore.SingleKVStore | undefined = undefined;
  private appId: string = '';
  private storeId: string = '';
  private context: Context | null = null;
  private options?: distributedKVStore.Options

  /**
   * 初始化KVManager
   * @param context 上下文对象
   * @param storeId 数据库ID
   */
  async initKVManager(context: Context, storeId: string, options?: distributedKVStore.Options): Promise<void> {
    this.context = context;
    this.appId = context.applicationInfo.name;
    this.storeId = storeId
    this.options = options
    const kvManagerConfig: distributedKVStore.KVManagerConfig = {
      context: context,
      bundleName: this.appId
    };

    try {
      this.kvManager = distributedKVStore.createKVManager(kvManagerConfig);
      console.info('Succeeded in creating KVManager.');
      this.getKVStore()
    } catch (e) {
      const error = e as BusinessError;
      console.error(`Failed to create KVManager. Code:${error.code},message:${error.message}`);
      throw error;
    }

  }

  /**
   * 创建或获取KVStore数据库
   * @param storeId 数据库ID
   * @param options 数据库配置选项
   */
  async getKVStore(): Promise<distributedKVStore.SingleKVStore> {
    if (!this.kvManager) {
      throw new Error('KVManager is not initialized. Call initKVManager first.');
    }

    const defaultOptions: distributedKVStore.Options = {
      createIfMissing: true,
      encrypt: false,
      backup: false,
      autoSync: true,
      kvStoreType: distributedKVStore.KVStoreType.SINGLE_VERSION,
      securityLevel: distributedKVStore.SecurityLevel.S1
    };

    const finalOptions = this.options || defaultOptions;

    return new Promise((resolve, reject) => {
      this.kvManager!.getKVStore<distributedKVStore.SingleKVStore>(
        this.storeId,
        finalOptions,
        (err, store: distributedKVStore.SingleKVStore) => {
          if (err) {
            console.error(`Failed to get KVStore: Code:${err.code},message:${err.message}`);
            reject(err);
            return;
          }
          console.info('Succeeded in getting KVStore.');
          this.kvStore = store;
          resolve(store);
        }
      );
    });
  }

  /**
   * 向数据库插入数据
   * @param key 键
   * @param value 值（支持string、number、boolean、Uint8Array类型）
   */
  async putData(key: string, value: string | number | boolean | Uint8Array): Promise<void> {
    if (!this.kvStore) {
      throw new Error('KVStore is not initialized. Call getKVStore first.');
    }

    return new Promise((resolve, reject) => {
      this.kvStore!.put(key, value, (err) => {
        if (err !== undefined) {
          console.error(`Failed to put data. Code:${err.code},message:${err.message}`);
          reject(err);
          return;
        }
        console.info('Succeeded in putting data.');
        resolve();
      });
    });
  }

  /**
   * 从数据库获取数据
   * @param key 键
   * @returns 存储的值
   */
  async getData(key: string): Promise<string | number | boolean | Uint8Array> {
    if (!this.kvStore) {
      throw new Error('KVStore is not initialized. Call getKVStore first.');
    }

    return new Promise((resolve, reject) => {
      this.kvStore!.get(key, (err, data) => {
        if (err !== undefined) {
          console.error(`Failed to get data. Code:${err.code},message:${err.message}`);
          reject(err);
          return;
        }
        console.info('Succeeded in getting data.');
        resolve(data);
      });
    });
  }

  /**
   * 从数据库删除数据
   * @param key 要删除的键
   */
  async deleteData(key: string): Promise<void> {
    if (!this.kvStore) {
      throw new Error('KVStore is not initialized. Call getKVStore first.');
    }

    return new Promise((resolve, reject) => {
      this.kvStore!.delete(key, (err) => {
        if (err !== undefined) {
          console.error(`Failed to delete data. Code:${err.code},message:${err.message}`);
          reject(err);
          return;
        }
        console.info('Succeeded in deleting data.');
        resolve();
      });
    });
  }

  /**
   * 订阅数据变更
   * @param callback 数据变更时的回调函数
   */
  subscribeDataChange(callback: (data: any) => void): void {
    if (!this.kvStore) {
      throw new Error('KVStore is not initialized. Call getKVStore first.');
    }

    try {
      this.kvStore!.on('dataChange', distributedKVStore.SubscribeType.SUBSCRIBE_TYPE_ALL, callback);
      console.info('Succeeded in subscribing to data changes.');
    } catch (e) {
      const error = e as BusinessError;
      console.error(`Failed to subscribe to data changes. Code:${error.code},message:${error.message}`);
      throw error;
    }
  }

  /**
   * 取消订阅数据变更
   */
  unsubscribeDataChange(): void {
    if (!this.kvStore) {
      throw new Error('KVStore is not initialized. Call getKVStore first.');
    }

    try {
      this.kvStore!.off('dataChange');
      console.info('Succeeded in unsubscribing from data changes.');
    } catch (e) {
      const error = e as BusinessError;
      console.error(`Failed to unsubscribe from data changes. Code:${error.code},message:${error.message}`);
      throw error;
    }
  }

  /**
   * 备份数据库
   * @param backupFile 备份文件名
   */
  async backupDatabase(backupFile: string): Promise<void> {
    if (!this.kvStore) {
      throw new Error('KVStore is not initialized. Call getKVStore first.');
    }

    return new Promise((resolve, reject) => {
      this.kvStore!.backup(backupFile, (err) => {
        if (err) {
          console.error(`Failed to backup database. Code:${err.code},message:${err.message}`);
          reject(err);
          return;
        }
        console.info('Succeeded in backing up database.');
        resolve();
      });
    });
  }

  /**
   * 恢复数据库
   * @param backupFile 要恢复的备份文件名
   */
  async restoreDatabase(backupFile: string): Promise<void> {
    if (!this.kvStore) {
      throw new Error('KVStore is not initialized. Call getKVStore first.');
    }

    return new Promise((resolve, reject) => {
      this.kvStore!.restore(backupFile, (err) => {
        if (err) {
          console.error(`Failed to restore database. Code:${err.code},message:${err.message}`);
          reject(err);
          return;
        }
        console.info('Succeeded in restoring database.');
        resolve();
      });
    });
  }

  /**
   * 删除备份文件
   * @param backupFiles 要删除的备份文件列表
   */
  async deleteBackup(backupFiles: string[]): Promise<void> {
    if (!this.kvStore) {
      throw new Error('KVStore is not initialized. Call getKVStore first.');
    }

    try {
      await this.kvStore!.deleteBackup(backupFiles);
      console.info('Succeeded in deleting backup.');
    } catch (e) {
      const error = e as BusinessError;
      console.error(`Failed to delete backup. Code:${error.code},message:${error.message}`);
      throw error;
    }
  }

  /**
   * 关闭数据库
   */
  async closeKVStore(): Promise<void> {
    if (!this.kvManager || !this.kvStore) {
      throw new Error('KVManager or KVStore is not initialized.');
    }

    return new Promise((resolve, reject) => {
      this.kvManager!.closeKVStore(this.appId, this.storeId, (err: BusinessError) => {
        if (err) {
          console.error(`Failed to close KVStore. Code:${err.code},message:${err.message}`);
          reject(err);
          return;
        }
        console.info('Succeeded in closing KVStore.');
        this.kvStore = undefined;
        resolve();
      });
    });
  }

  /**
   * 删除数据库
   */
  async deleteKVStore(): Promise<void> {
    if (!this.kvManager) {
      throw new Error('KVManager is not initialized.');
    }

    return new Promise((resolve, reject) => {
      this.kvManager!.deleteKVStore(this.appId, this.storeId, (err: BusinessError) => {
        if (err) {
          console.error(`Failed to delete KVStore. Code:${err.code},message:${err.message}`);
          reject(err);
          return;
        }
        console.info('Succeeded in deleting KVStore.');
        this.kvStore = undefined;
        resolve();
      });
    });
  }
}


/** 用户首选项键值型数据库封装 */
export const preferencesKVDB = new PreferencesKVDB();