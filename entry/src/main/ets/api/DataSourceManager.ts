import Logger from '../utils/Logger';
import GenericDataSource from './GenericDataSource';
import { DataSourceConfig } from './DataSourceConfig';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import Url from '@ohos.url'
import { common } from '@kit.AbilityKit';
import VideoDetailInfo from '../entity/VideoDetailInfo';
import VideoInfo from '../entity/VideoInfo';
import HomepageData from '../entity/HomepageData';

// 配置文件接口
interface DataSourceConfigFile {
  version: string;
  sources: DataSourceConfig[];
}

// 搜索策略枚举
enum SearchStrategy {
  ALL_SOURCES = 'all',
  PRIORITIZED = 'prioritized',
  SPECIFIC = 'specific'
}

// 数据源管理器
class DataSourceManager {
  private dataSources: Map<string, GenericDataSource> = new Map();
  private dataSourceConfigs: Map<string, DataSourceConfig> = new Map();
  private defaultConfigFileName: string = 'default_sources_config.json';
  private configFileName: string = 'sources_config.json';
  private context: common.UIAbilityContext
  private searchStrategy: SearchStrategy = SearchStrategy.PRIORITIZED;
  private currentDataSourceKey: string = '';

  async init(context: common.UIAbilityContext) {
    this.context = context
    await this.loadFromConfig()
  }

  /**
   * 获取当前使用的数据源key
   */
  getKey(): string {
    if (this.currentDataSourceKey && this.dataSources.has(this.currentDataSourceKey)) {
      return this.currentDataSourceKey;
    }

    const prioritized = this.getPrioritizedDataSources();
    return prioritized.length > 0 ? prioritized[0].getKey() : '';
  }

  /**
   * 获取指定key的数据源名称
   */
  getSourceTitle(key: string): string {
    return this.dataSources.get(key)?.getName()
  }

  /**
   * 设置当前使用的数据源(临时性，不持久化)
   */
  setCurrentDataSource(key: string): void {
    if (this.dataSources.has(key)) {
      this.currentDataSourceKey = key;
      Logger.i(this, `DataSourceManager.setCurrentDataSource Set current data source to: ${key}`);
    } else {
      Logger.e('tips', `DataSourceManager.setCurrentDataSource Data source not found: ${key}`);
    }
  }

  /**
   * 获取当前数据源配置
   */
  getCurrentDataSourceConfig(): DataSourceConfig | undefined {
    return this.dataSourceConfigs.get(this.currentDataSourceKey);
  }

  /**
   * 设置搜索策略
   */
  setSearchStrategy(strategy: SearchStrategy): void {
    this.searchStrategy = strategy;
    Logger.i(this, `DataSourceManager.setSearchStrategy Search strategy set to: ${strategy}`);
  }

  /**
   * 获取默认数据源
   */
  getDefaultDataSource(): GenericDataSource | undefined {
    // 查找标记为默认的数据源
    const defaultConfig = Array.from(this.dataSourceConfigs.values())
      .find(config => config.defaultSource && config.enabled !== false);

    if (defaultConfig) {
      return this.dataSources.get(defaultConfig.key);
    }

    // 返回优先级最高的数据源
    const prioritized = this.getPrioritizedDataSources();
    return prioritized.length > 0 ? prioritized[0] : undefined;
  }

  // 获取所有数据源
  getAllDataSources(): GenericDataSource[] {
    return Array.from(this.dataSources.values());
  }

  // 获取所有数据源配置
  getAllDataSourceConfigs(): DataSourceConfig[] {
    return Array.from(this.dataSourceConfigs.values());
  }

  // 按优先级排序获取数据源
  getPrioritizedDataSources(): GenericDataSource[] {
    return this.getAllDataSources().sort((a, b) => {
      const aPriority = a.getPriority() || 0;
      const bPriority = b.getPriority() || 0;
      return aPriority - bPriority;
    });
  }

  // 按优先级排序获取数据源配置
  getPrioritizedDataSourceConfigs(): DataSourceConfig[] {
    return this.getAllDataSourceConfigs().sort((a, b) => {
      const aPriority = a.priority || 0;
      const bPriority = b.priority || 0;
      return aPriority - bPriority;
    });
  }

  // 根据key获取特定数据源
  getDataSource(key: string): GenericDataSource | undefined {
    return this.dataSources.get(key);
  }

  // 根据key获取特定数据源配置
  getDataSourceConfig(key: string): DataSourceConfig | undefined {
    return this.dataSourceConfigs.get(key);
  }

  /**
   * 搜索视频
   */
  async search(keyword: string, page: number): Promise<VideoInfo[]> {
    if (!keyword.trim()) {
      return [];
    }

    try {
      switch (this.searchStrategy) {
        case SearchStrategy.ALL_SOURCES:  // 搜索全部
          return await this.searchAllSources(keyword, page);

        case SearchStrategy.PRIORITIZED:  // 按优先级搜索
          return await this.searchPrioritized(keyword, page);

        case SearchStrategy.SPECIFIC:     // 搜索指定
          return await this.searchSpecificSource(keyword, page);

        default:
          return await this.searchPrioritized(keyword, page);
      }
    } catch (error) {
      Logger.e('tips', `DataSourceManager.search Failed to search: ${error.message}`);
      return [];
    }
  }

  /**
   * 获取主页数据
   */
  async getHomepageData(): Promise<HomepageData> {
    const sourceKey = this.currentDataSourceKey|| this.getKey();
    const source = this.dataSources.get(sourceKey);

    if (!source) {
      throw new Error(`DataSourceManager.getHomepageData Current data source not found: ${sourceKey}`);
    }

    if (!source.isEnabled()) {
      throw new Error(`DataSourceManager.getHomepageData Data source is disabled: ${sourceKey}`);
    }

    try {
      return await source.getHomepageData();
    } catch (error) {
      Logger.e('tips', `DataSourceManager.getHomepageData Failed to get homepage data from ${sourceKey}: ${error.message}`);
      throw error;
    }
  }

  /**
   * 获取片源列表数据
   */
  async getVideoList(moreUrl: string, page: number): Promise<VideoInfo[]> {
    const sourceKey = this.currentDataSourceKey || this.getKey();
    const source = this.dataSources.get(sourceKey);

    if (!source) {
      throw new Error(`DataSourceManager.getVideoList Current data source not found: ${sourceKey}`);
    }

    if (!source.isEnabled()) {
      throw new Error(`DataSourceManager.getVideoList Data source is disabled: ${sourceKey}`);
    }

    try {
      return await source.getVideoList(moreUrl, page);
    } catch (error) {
      Logger.e('tips', `DataSourceManager.getVideoList Failed to get video list from ${sourceKey}: ${error.message}`);
      throw error;
    }
  }

  /**
   * 获取视频详情
   */
  async getVideoDetailInfo(url: string): Promise<VideoDetailInfo> {
    const source = this.identifyDataSourceByUrl(url);

    if (!source) {
      throw new Error(`DataSourceManager.getVideoDetailInfo Cannot identify data source for URL: ${url}`);
    }

    if (!source.isEnabled()) {
      throw new Error(`DataSourceManager.getVideoDetailInfo Data source is disabled: ${source.getKey()}`);
    }

    try {
      return await source.getVideoDetailInfo(url);
    } catch (error) {
      Logger.e('tips', `DataSourceManager.getVideoDetailInfo Failed to get video detail from ${source.getKey()}: ${error.message}`);
      throw error;
    }
  }

  /**
   * 解析视频链接
   */
  async parseVideoUrl(link: string): Promise<string> {
    const source = this.identifyDataSourceByUrl(link);

    if (!source) {
      throw new Error(`DataSourceManager.parseVideoUrl Cannot identify data source for URL: ${link}`);
    }

    if (!source.isEnabled()) {
      throw new Error(`DataSourceManager.parseVideoUrl Data source is disabled: ${source.getKey()}`);
    }

    try {
      return await source.parseVideoUrl(link);
    } catch (error) {
      Logger.e('tips', `DataSourceManager.parseVideoUrl Failed to parse video URL from ${source.getKey()}: ${error.message}`);
      throw error;
    }
  }

  // 从配置文件加载所有数据源
  async loadFromConfig(): Promise<void> {
    try {
      // 首先尝试从沙箱目录读取配置文件
      const sandboxConfig = await this.readSandboxConfig();

      if (sandboxConfig) {
        // 如果沙箱中有配置文件，使用它
        await this.loadConfigData(sandboxConfig)
        Logger.i(this, 'DataSourceManager.loadFromConfig Loaded data sources from sandbox config');
      } else {
        // 如果沙箱中没有配置文件，从rawfile读取默认配置
        const defaultConfig = await this.readRawFileConfig()
        await this.loadConfigData(defaultConfig)

        // 将默认配置保存到沙箱
        await this.saveConfigToSandbox(defaultConfig)
        Logger.i(this, 'DataSourceManager.loadFromConfig Loaded data sources from default config and saved to sandbox');
      }
      // 设置默认数据源
      this.setDefaultDataSource()
    } catch (error) {
      Logger.e('tips', `DataSourceManager.loadFromConfig Failed to load data sources: ${error.message}`);
      throw error;
    }
  }

  /**
   * 设置指定数据源为默认
   */
  async setDataSourceAsDefault(key: string): Promise<void> {
    if (!this.dataSources.has(key)) {
      throw new Error(`DataSourceManager.setDataSourceAsDefault Data source with key '${key}' does not exist`);
    }

    // 清除其他数据源的默认标记
    for (const config of this.dataSourceConfigs.values()) {
      config.defaultSource = false;
    }

    // 设置当前数据源为默认
    const config = this.dataSourceConfigs.get(key);
    if (config) {
      config.defaultSource = true;
      this.currentDataSourceKey = key;

      // 保存配置
      await this.saveCurrentConfig();
      Logger.i(this, `DataSourceManager.setDataSourceAsDefault Set data source as default: ${key}`);
    }
  }

  // 添加数据源
  async addDataSource(config: DataSourceConfig): Promise<void> {
    if (this.dataSources.has(config.key)) {
      throw new Error(`DataSourceManager.addDataSource Data source with key '${config.key}' already exists`);
    }

    // 如果新添加的数据源是默认的，清除其他数据源的默认标记
    if (config.defaultSource) {
      for (const existingConfig of this.dataSourceConfigs.values()) {
        existingConfig.defaultSource = false;
      }
    }

    const dataSource = new GenericDataSource(config);
    this.dataSources.set(config.key, dataSource);
    this.dataSourceConfigs.set(config.key, config);

    // 保存到沙箱配置文件
    await this.saveCurrentConfig();

    Logger.i(this, `DataSourceManager.addDataSource Added data source: ${config.name}`);
  }

  // 更新数据源
  async updateDataSource(key: string, config: DataSourceConfig): Promise<void> {
    if (!this.dataSources.has(key)) {
      throw new Error(`DataSourceManager Data source with key '${key}' does not exist`);
    }

    // 如果新配置是默认的，清除其他数据源的默认标记
    if (config.defaultSource) {
      for (const existingConfig of this.dataSourceConfigs.values()) {
        if (existingConfig.key !== key) {
          existingConfig.defaultSource = false;
        }
      }
    }

    // 如果key发生变化，需要先删除旧的
    if (key !== config.key) {
      this.dataSources.delete(key);
      this.dataSourceConfigs.delete(key);
    }

    const dataSource = new GenericDataSource(config);
    this.dataSources.set(config.key, dataSource);
    this.dataSourceConfigs.set(config.key, config);

    // 保存到沙箱配置文件
    await this.saveCurrentConfig();

    Logger.i(this, `DataSourceManager.updateDataSource Updated data source: ${config.name}`);
  }

  // 删除数据源
  async removeDataSource(key: string): Promise<void> {
    if (!this.dataSources.has(key)) {
      throw new Error(`DataSourceManager Data source with key '${key}' does not exist`);
    }

    const name = this.dataSourceConfigs.get(key)?.name || key;
    this.dataSources.delete(key);
    this.dataSourceConfigs.delete(key);

    // 保存到沙箱配置文件
    await this.saveCurrentConfig();

    Logger.i(this, `DataSourceManager.removeDataSource Removed data source: ${name}`);
  }

  // 启用/禁用数据源
  async setDataSourceEnabled(key: string, enabled: boolean): Promise<void> {
    const config = this.dataSourceConfigs.get(key);
    if (!config) {
      throw new Error(`DataSourceManager.setDataSourceEnabled Data source with key '${key}' does not exist`);
    }

    config.enabled = enabled;

    // 重新创建数据源实例
    const dataSource = new GenericDataSource(config);
    this.dataSources.set(key, dataSource);

    // 保存到沙箱配置文件
    await this.saveCurrentConfig();

    Logger.i(this, `DataSourceManager.setDataSourceEnabled ${enabled ? 'Enabled' : 'Disabled'} data source: ${config.name}`);
  }

  // 重置为默认配置
  async resetToDefault(): Promise<void> {
    try {
      // 从rawfile读取默认配置
      const defaultConfig = await this.readRawFileConfig();

      // 加载默认配置
      await this.loadConfigData(defaultConfig);

      // 保存到沙箱（覆盖当前配置）
      await this.saveConfigToSandbox(defaultConfig);

      Logger.i(this, 'DataSourceManager.resetToDefault Reset to default configuration');
    } catch (error) {
      Logger.e('tips', `DataSourceManager.resetToDefault Failed to reset to default configuration: ${error.message}`);
      throw error;
    }
  }

  // 从沙箱目录读取配置文件
  private async readSandboxConfig(): Promise<DataSourceConfigFile | null> {
    try {

      const sandboxPath = this.context.filesDir + '/' + this.configFileName;

      // 检查文件是否存在
      try {
        await fileIo.access(sandboxPath);
      } catch {
        // 文件不存在
        Logger.e('tips', `DataSourceManager.readSandboxConfig Failed to read sandbox config: 文件不存在`);
        return null;
      }

      // 读取文件内容
      const content = await fileIo.readText(sandboxPath);
      return JSON.parse(content) as DataSourceConfigFile;
    } catch (error) {
      Logger.e('tips', `DataSourceManager.readSandboxConfig Failed to read sandbox config: ${error.message}`);
      return null;
    }
  }

  // 从rawfile读取默认配置文件
  private async readRawFileConfig(): Promise<DataSourceConfigFile> {
    try {
      const resourceManager = this.context.resourceManager;

      const value: Uint8Array = await resourceManager.getRawFileContent(this.defaultConfigFileName);
      const textDecoder = util.TextDecoder.create("UTF-8", { ignoreBOM: false })
      const content = textDecoder.decodeToString(value);

      return JSON.parse(content) as DataSourceConfigFile;
    } catch (error) {
      Logger.e('tips', `DataSourceManager.readRawFileConfig Failed to read rawfile config: ${error.message}`);
      throw error;
    }
  }

  // 加载配置数据
  private async loadConfigData(configData: DataSourceConfigFile): Promise<void> {
    // 验证配置格式
    if (!configData.sources || !Array.isArray(configData.sources)) {
      throw new Error('DataSourceManager.loadConfigData Invalid configuration format: missing sources array');
    }

    // 清空现有数据
    this.dataSources.clear();
    this.dataSourceConfigs.clear();

    // 创建所有的数据源及其配置
    for (const sourceConfig of configData.sources) {
      const dataSource = new GenericDataSource(sourceConfig);
      this.dataSources.set(sourceConfig.key, dataSource);
      this.dataSourceConfigs.set(sourceConfig.key, sourceConfig);
    }

    Logger.i(this, `DataSourceManager.loadConfigData Loaded ${this.dataSources.size} data sources`);
  }

  // 保存配置到沙箱目录
  private async saveConfigToSandbox(config: DataSourceConfigFile): Promise<void> {
    try {

      const sandboxPath = this.context.filesDir + '/' + this.configFileName;

      // 转换为JSON字符串
      const jsonContent = JSON.stringify(config, null, 2);

      // 写入配置文件
      let fileModify = fileIo.openSync(sandboxPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(fileModify.fd, jsonContent);
      fileIo.close(fileModify);

      Logger.i(this, 'DataSourceManager.saveConfigToSandbox Configuration saved to sandbox');
    } catch (error) {
      Logger.e('tips', `DataSourceManager.saveConfigToSandbox Failed to save configuration to sandbox: ${error.message}`);
      throw error;
    }
  }

  // 保存当前配置到沙箱目录
  private async saveCurrentConfig(): Promise<void> {
    const configFile: DataSourceConfigFile = {
      version: "1.0.0",
      sources: Array.from(this.dataSourceConfigs.values())
    };

    await this.saveConfigToSandbox(configFile);
  }

  /**
   * 搜索所有数据源
   */
  private async searchAllSources(keyword: string, page: number): Promise<VideoInfo[]> {
    const enabledSources = this.getPrioritizedDataSources().filter(ds => ds.isEnabled());
    const searchPromises = enabledSources.map(source =>
    source.search(keyword, page).catch(error => {
      Logger.e('tips', `DataSourceManager.searchAllSources Failed to search ${source.getKey()}: ${error.message}`);
      return [];
    })
    );

    const results = await Promise.all(searchPromises);
    const mergedResults: VideoInfo[] = [];
    const urlSet = new Set<string>();

    results.flat().forEach(video => {
      if (!urlSet.has(video.url)) {
        urlSet.add(video.url);
        mergedResults.push(video);
      }
    });

    return mergedResults;
  }

  /**
   * 按优先级搜索直到有结果
   */
  private async searchPrioritized(keyword: string, page: number): Promise<VideoInfo[]> {
    const enabledSources = this.getPrioritizedDataSources().filter(ds => ds.isEnabled());

    for (const source of enabledSources) {
      try {
        const results = await source.search(keyword, page);
        if (results.length > 0) {
          Logger.i(this, `DataSourceManager.searchPrioritized Found ${results.length} results from ${source.getKey()}`);
          return results;
        }
      } catch (error) {
        Logger.e('tips', `DataSourceManager.searchPrioritized Failed to search ${source.getKey()}: ${error.message}`);
      }
    }

    Logger.i(this, 'DataSourceManager.searchPrioritized No results found from any source');
    return [];
  }

  /**
   * 搜索特定数据源
   */
  private async searchSpecificSource(keyword: string, page: number): Promise<VideoInfo[]> {
    const sourceKey = this.currentDataSourceKey|| this.getKey();
    const source = this.dataSources.get(sourceKey);

    if (!source) {
      Logger.e('tips', `DataSourceManager.searchSpecificSource Current data source not found: ${sourceKey}`);
      return [];
    }

    if (!source.isEnabled()) {
      Logger.e('tips', `DataSourceManager.searchSpecificSource Data source is disabled: ${sourceKey}`);
      return [];
    }

    try {
      return await source.search(keyword, page);
    } catch (error) {
      Logger.e('tips', `DataSourceManager.searchSpecificSource Failed to search ${sourceKey}: ${error.message}`);
      return [];
    }
  }

  /**
   * 根据URL识别数据源
   */
  private identifyDataSourceByUrl(url: string): GenericDataSource | undefined {
    for (const source of this.dataSources.values()) {
      if (source.isEnabled()) {
        try {
          const sourceUrl = Url.URL.parseURL(decodeURIComponent(source.getBaseUrl()));
          const targetUrl = Url.URL.parseURL(decodeURIComponent(url));
          if (targetUrl.hostname.includes(sourceUrl.hostname) || sourceUrl.hostname.includes(targetUrl.hostname)) {
            return source;
          }
        } catch (error) {
          // URL解析失败，使用简单包含判断
          if (url.includes(source.getBaseUrl()) || source.getBaseUrl().includes(url)) {
            return source;
          }
        }
      }
    }
    return undefined;
  }

  /**
   * 初始化默认数据源
   */
  private setDefaultDataSource(): void {
    // 查找标记为默认的数据源
    const defaultSources = Array.from(this.dataSourceConfigs.values())
      .filter(config => config.defaultSource && config.enabled !== false);

    if (defaultSources.length > 0) {
      // 有多个默认数据源，选择优先级最高的
      const highestPriorityDefault = defaultSources.reduce((prev, current) =>
      (prev.priority || 0) < (current.priority || 0) ? prev : current
      );
      this.currentDataSourceKey = highestPriorityDefault.key;
      Logger.i(this, `DataSourceManager.setDefaultDataSource Set default data source from config: ${this.currentDataSourceKey}`);
      return;
    }

    // 没有标记为默认的数据源，选择优先级最高的启用数据源
    const prioritized = this.getPrioritizedDataSources();
    if (prioritized.length > 0) {
      this.currentDataSourceKey = prioritized[0].getKey();
      Logger.i(this, `DataSourceManager.setDefaultDataSource Set highest priority data source: ${this.currentDataSourceKey}`);
      return;
    }

    // 没有可用的数据源
    this.currentDataSourceKey = '';
    Logger.e('tips', 'DataSourceManager.setDefaultDataSource No available data source found');
  }

}

export const dataSourceManager = new DataSourceManager()
