import YingHuaDataSource from './impl/YingHuaDataSource';
import DataStore from '../utils/DataStore';
import BimiAcgDataSource from './impl/BimiAcgDataSource';
import DataSource from './DataSource';
import VideoInfo from '../entity/VideoInfo';
import HomepageData from '../entity/HomepageData';
import VideoDetailInfo from '../entity/VideoDetailInfo';
import Logger from '../utils/Logger';
import AGEDataSource from './impl/AGEDataSource';

const MAP_DATA_SOURCE = 'map_data_source'
const KEY_CURRENT_SOURCE = 'key_current_source'


// 数据源信息接口
interface SourceInfo {
  key: string,
  title: string,
  source: () => DataSource
}

// TODO 通过注解配置key和title
const ALL_SOURCES: SourceInfo[] = [
  { key: 'key_yinghuavideo', title: '樱花动漫', source: () => new YingHuaDataSource() },
  // { key: 'key_agedmvideo', title: 'AGE动漫', source: () => new AGEDataSource() }
]

/**
 * 初始化数据源
 */
export function initDataSources() {
  ALL_SOURCES.forEach((item: SourceInfo) => {
    const title = item.title
    try {
      const key = item.key
      const instance = item.source()
      DataSourceManager.register(key, instance);
    } catch (e) {
      Logger.e(`数据源[${title}]注册失败: ${e.message}`);
    }
  });

}

/**
 * 视频数据源管理
 */
export default class DataSourceManager {
  private static dataSourceRegistry = new Map<string, DataSource>()

  // 注册数据源实现
  static register(sourceKey: string, dataSource: DataSource) {
    DataSourceManager.dataSourceRegistry.set(sourceKey, dataSource);
    console.log('数据源 已注册:', sourceKey)
  }

  /**
   * 获取所有数据源
   */
  static getAllSources(): string[] {
    return ALL_SOURCES.map((source) => {
      return source.title
    })
  }

  static getSourceTitle(key: string): string {
    let targetSource = ALL_SOURCES.find((source) => {
      return source.key == key
    })
    if (targetSource) {
      return targetSource.title
    } else {
      return ''
    }
  }

  /**
   * 获取当前视频数据源
   */
  static getCurrentSource(): DataSource {
    let currentSource = DataStore.get(KEY_CURRENT_SOURCE, ALL_SOURCES[0].key)
    return DataSourceManager.getSource(currentSource)
  }

  /**
   * 设置当前视频数据源
   */
  static setCurrentSource(key: string) {
    DataStore.set(KEY_CURRENT_SOURCE, key)
  }

  /**
   * 获取当前数据源key
   */
  static getCurrentSourceKey(): string {
    return DataStore.get(KEY_CURRENT_SOURCE, ALL_SOURCES[0].key)
  }

  /**
   * 根据index设置当前数据源
   * @param index
   */
  static setCurrentSourceIndex(index: number) {
    if (ALL_SOURCES.length > index) {
      DataSourceManager.setCurrentSource(ALL_SOURCES[index].key)
    }
  }

  static getSource(sourceKey: string): DataSource {
    const source = DataSourceManager.dataSourceRegistry.get(sourceKey);
    if (!source) throw new Error(`数据源 [${sourceKey}] not registered`)
    console.log('数据源 :', sourceKey)
    return source;
  }

}

// 独立维护实例容器
const dataSourceMap = new Map<string, Map<string, DataSource>>()


