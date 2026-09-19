import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import Logger from './Logger';

const TAG: string = 'PreferenceUtil';

/**
 * 首选项工具类
 * 使用单例模式，封装了首选项的常用异步操作。
 * 使用前必须先调用 init 方法进行初始化。
 */
class PreferenceUtil {
  private static instance: PreferenceUtil | null = null;
  private preference: preferences.Preferences | null = null;

  private constructor() {
  }

  /**
   * 获取单例实例
   * @returns PreferenceUtil实例
   */
  public static getInstance(): PreferenceUtil {
    if (!PreferenceUtil.instance) {
      PreferenceUtil.instance = new PreferenceUtil();
    }
    return PreferenceUtil.instance;
  }

  /**
   * 初始化首选项工具类，必须在调用其他方法前执行。
   * @param context 应用上下文
   * @param fileName 首选项文件名
   * @returns Promise<void>
   */
  public async init(context: Context, fileName: string = 'animez_preference'): Promise<void> {
    if (this.preference) {
      Logger.w(TAG, 'PreferenceUtil 已初始化，跳过重复初始化');
      return;
    }
    try {
      this.preference = await preferences.getPreferences(context, { name: fileName });
      Logger.i(TAG, `首选项初始化成功: ${fileName}`);
    } catch (error) {
      const err = error as BusinessError;
      Logger.e('fail', '首选项初始化', err);
      throw new Error(`${err}`);
    }
  }

  /**
   * 确保已初始化
   */
  private ensureInitialized(): void {
    if (!this.preference) {
      throw new Error('PreferenceUtil is not initialized. Please call init() first.');
    }
  }

  /**
   * 保存或更新一个键值对（含落盘）
   * @param key 键
   * @param value 值
   */
  public async put(key: string, value: preferences.ValueType): Promise<void> {
    this.ensureInitialized();
    try {
      await this.preference!.put(key, value);
      await this.preference!.flush();
    } catch (error) {
      const err = error as BusinessError;
      Logger.e('fail', `首选项写入 key '${key}'`, err);
      throw new Error(`${err}`);
    }
  }

  /**
   * 获取指定键的值
   * @param key 键
   * @param defValue 键不存在时返回的默认值
   * @returns Promise<T>
   */
  public async get<T>(key: string, defValue: preferences.ValueType): Promise<T> {
    this.ensureInitialized();
    try {
      const value = await this.preference!.get(key, defValue);
      return value as T;
    } catch (error) {
      const err = error as BusinessError;
      Logger.e('fail', `首选项读取 key '${key}'`, err);
      return defValue as T;
    }
  }

  /**
   * 删除指定键的数据
   * @param key 键
   */
  public async delete(key: string): Promise<void> {
    this.ensureInitialized();
    try {
      await this.preference!.delete(key);
      await this.preference!.flush();
    } catch (error) {
      const err = error as BusinessError;
      Logger.e('fail', `首选项删除 key '${key}'`, err);
      throw new Error(`${err}`);
    }
  }

  /**
   * 检查某个键是否存在
   * @param key 键
   */
  public async has(key: string): Promise<boolean> {
    this.ensureInitialized();
    try {
      return await this.preference!.has(key);
    } catch (error) {
      return false;
    }
  }

  /**
   * 将内存中的缓存数据持久化到磁盘
   */
  public async flush(): Promise<void> {
    this.ensureInitialized();
    try {
      await this.preference!.flush();
    } catch (error) {
      const err = error as BusinessError;
      Logger.e('fail', '首选项 flush', err);
    }
  }
}

// 导出单例
export const preferenceUtil = PreferenceUtil.getInstance();
