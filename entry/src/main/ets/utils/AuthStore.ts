import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import Logger from './Logger';

interface AuthRecord {
  token: string;
  username: string;
  expiresAt: number; // 毫秒时间戳，0 表示未知过期时间
}

/**
 * 数据源登录凭证存储：按源 key 持久化 token
 */
export default class AuthStore {
  private static store: preferences.Preferences | null = null;

  static async init(context: Context): Promise<void> {
    if (this.store) {
      return;
    }
    try {
      this.store = await preferences.getPreferences(context, 'auth_store');
    } catch (error) {
      Logger.e('fail', `AuthStore.init ${error.message}`);
    }
  }

  private static buildKey(sourceKey: string): string {
    return `auth_${sourceKey}`;
  }

  /**
   * 获取指定源的登录凭证（已过期时返回空）
   */
  static async getAuthRecord(sourceKey: string): Promise<AuthRecord | null> {
    if (!this.store) {
      return null;
    }
    try {
      const raw = this.store.getSync(this.buildKey(sourceKey), '') as string;
      if (!raw) {
        return null;
      }
      const record = JSON.parse(raw) as AuthRecord;
      if (!record || !record.token) {
        return null;
      }
      if (record.expiresAt > 0 && Date.now() > record.expiresAt) {
        Logger.w('tips', `AuthStore.getAuthRecord token of ${sourceKey} expired`);
        return null;
      }
      return record;
    } catch (error) {
      Logger.e('fail', `AuthStore.getAuthRecord ${error.message}`);
      return null;
    }
  }

  static async getToken(sourceKey: string): Promise<string> {
    const record = await this.getAuthRecord(sourceKey);
    return record ? record.token : '';
  }

  static async saveToken(sourceKey: string, token: string, username: string = '', expiresAt: number = 0): Promise<void> {
    if (!this.store) {
      throw new Error('AuthStore 未初始化');
    }
    const record: AuthRecord = { token, username, expiresAt };
    await this.store.put(this.buildKey(sourceKey), JSON.stringify(record));
    await this.store.flush();
  }

  static async clearToken(sourceKey: string): Promise<void> {
    if (!this.store) {
      return;
    }
    await this.store.delete(this.buildKey(sourceKey));
    await this.store.flush();
  }
}
