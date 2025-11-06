import Logger from '../utils/Logger';
import GenericDataSource from './GenericDataSource';
import { DataSourceConfig } from './DataSourceConfig';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import Url from '@ohos.url'
import { common, Context } from '@kit.AbilityKit';
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
   * 获取所有数据源key
   */
  getTotalKey(): string[] {
    const keys: string[] = []
    this.dataSources.forEach(item => {
      keys.push(item.getKey())
    })
    return keys;
  }

  /**
   * 获取指定key的数据源名称
   */
  getSourceTitle(key: string): string {
    return this.dataSources.get(key)?.getName()
  }

  /**
   * 获取所有的数据源名称
   */
  getTotalSourceTitle(): string[] {
    const names: string[] = []
    this.dataSources.forEach(item => {
      names.push(item.getName())
    })
    return names;
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
   * 设置搜索策略
   */
  setSearchStrategy(strategy: SearchStrategy): void {
    this.searchStrategy = strategy;
    Logger.i(this, `DataSourceManager.setSearchStrategy Search strategy set to: ${strategy}`);
  }

  /**
   * 获取当前数据源配置
   */
  getCurrentDataSourceConfig(): DataSourceConfig | undefined {
    return this.dataSourceConfigs.get(this.currentDataSourceKey);
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
        case SearchStrategy.ALL_SOURCES:  // 搜索全部已启用
          return await this.searchAllSources(keyword, page);

        case SearchStrategy.PRIORITIZED:  // 按优先级搜索
          return await this.searchPrioritized(keyword, page);

        case SearchStrategy.SPECIFIC:     // 搜索指定
          return await this.searchSpecificSource(keyword, page);

        default:
          return await this.searchPrioritized(keyword, page);
      }
    } catch (error) {
      Logger.e('fail', `DataSourceManager.search`, error);
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
  async getVideoDetailInfo(url: string, order: "asc" | "desc" = 'asc'): Promise<VideoDetailInfo> {
    const source = this.identifyDataSourceByUrl(url);
    if (!source) {
      throw new Error(`DataSourceManager.getVideoDetailInfo Cannot identify data source for URL: ${url}`);
    }
    if (!source.isEnabled()) {
      throw new Error(`DataSourceManager.getVideoDetailInfo Data source is disabled: ${source.getKey()}`);
    }
    try {
      return await source.getVideoDetailInfo(url, order);
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
      const videoLink = await source.parseVideoUrl(link)
      if (videoLink) {
        return videoLink
      }
      throw new Error('DataSourceManager.parseVideoUrl，视频链接解析值为空，解析失败')
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
        // 如果沙箱中没有配置文件，从rawfile获取默认配置
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
   * 从文件导入配置(支持批量导入)
   * @param context 应用上下文
   * @param overwrite 可选，是否覆盖已存在的数据源。默认为 false (不覆盖更新)
   * @returns message 导入情况
   */
  async importSourceConfigFromFile(context: Context, overwrite: boolean = false): Promise<string> {
    const filePicker = new picker.DocumentViewPicker(context)
    const options = new picker.DocumentSelectOptions()
    const result = await filePicker.select(options)
    let message = ''
    if (!result || result.length === 0) {
      message = '未选择任何文件'
      return message
    }
    let totalImported = 0;
    let totalUpdated = 0;
    let totalSkipped = 0;
    let totalFailed = 0;
    const failedFiles: string[] = [];
    const skippedSources: { key: string, name: string, reason: string }[] = [];
    try {
      // 处理每个选择的文件
      for (let i = 0; i < result.length; i++) {
        const fileUri = result[i];
        // 正确解码文件名 ---
        let fileName: string;
        try {
          // URI 中的路径部分可能被百分号编码，需要解码
          fileName = decodeURIComponent(fileUri.split('/').pop() || `文件${i + 1}`);
        } catch (e) {
          // 如果解码失败，使用原始名称作为后备
          Logger.w('tips', `DataSourceManager.importSourceConfigFromFile Failed to decode file name from URI: ${fileUri}`);
          fileName = fileUri.split('/').pop() || `文件${i + 1}`;
        }
        try {
          // 使用 TextDecoder 正确读取文件内容
          const file = fileIo.openSync(fileUri, fileIo.OpenMode.READ_ONLY);
          // 读取所有字节到 buffer
          const stat = fileIo.statSync(file.fd);
          const buffer = new ArrayBuffer(stat.size);
          fileIo.readSync(file.fd, buffer);
          fileIo.closeSync(file);
          // 使用 TextDecoder 将字节流解码为字符串
          const textDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
          const content = textDecoder.decodeToString(new Uint8Array(buffer));
          // 智能解析配置文件内容，并获取版本信息
          const { sources, version } = this.parseConfigFileWithVersion(content);
          if (!sources || sources.length === 0) {
            throw new Error('配置文件为空或格式无效');
          }
          // 验证版本兼容性 (示例：只兼容1.x.x版本)
          if (version && !this.isVersionCompatible(version)) {
            throw new Error(`不支持的配置文件版本: ${version}`);
          }
          // 导入数据源配置 (这部分逻辑保持不变)
          for (const sourceConfig of sources) {
            if (!sourceConfig.key || !sourceConfig.name) {
              Logger.w('tips', `DataSourceManager.importSourceConfigFromFile Invalid source config: ${JSON.stringify(sourceConfig)}`);
              skippedSources.push({ key: 'N/A', name: 'N/A', reason: '配置无效：缺少key或name' });
              continue;
            }
            const existingConfig = this.dataSourceConfigs.get(sourceConfig.key);
            if (existingConfig) {
              if (overwrite) {
                try {
                  await this.updateDataSource(sourceConfig.key, sourceConfig);
                  totalUpdated++;
                  Logger.i(this, `DataSourceManager.importSourceConfigFromFile Updated source: ${sourceConfig.key}`);
                } catch (error) {
                  Logger.e('tips', `DataSourceManager.importSourceConfigFromFile Failed to update source ${sourceConfig.key}:${error.message}`);
                  skippedSources.push({ key: sourceConfig.key, name: sourceConfig.name, reason: `更新失败: ${error.message}` });
                }
              } else {
                totalSkipped++;
                Logger.i(this, `DataSourceManager.importSourceConfigFromFile Skipped existing source: ${sourceConfig.key}`);
                skippedSources.push({ key: sourceConfig.key, name: sourceConfig.name, reason: '已存在且未选择覆盖' });
              }
            } else {
              try {
                await this.addDataSource(sourceConfig);
                totalImported++;
                Logger.i(this, `DataSourceManager.importSourceConfigFromFile Imported new source: ${sourceConfig.key}`);
              } catch (error) {
                Logger.e('tips', `DataSourceManager.importSourceConfigFromFile Failed to import source ${sourceConfig.key}:${error.message}`);
                skippedSources.push({ key: sourceConfig.key, name: sourceConfig.name, reason: `导入失败: ${error.message}` });
              }
            }
          }
        } catch (error) {
          totalFailed++;
          failedFiles.push(fileName); // 使用解码后的文件名
          Logger.e('tips', `DataSourceManager.importSourceConfigFromFile Failed to process file ${fileName}:${error.message}`);
        }
      }
      // 构建详细的返回消息 (这部分逻辑保持不变)
      const parts: string[] = [];
      if (totalImported > 0) parts.push(`新增 ${totalImported} 个`);
      if (totalUpdated > 0) parts.push(`更新 ${totalUpdated} 个`);
      if (totalSkipped > 0) parts.push(`跳过 ${totalSkipped} 个`);
      if (totalFailed > 0) parts.push(`${totalFailed} 个文件处理失败`);

      if (parts.length > 0) {
        message = `导入完成: ${parts.join('，')}`;
      } else {
        message = '没有可导入的数据源';
      }
      if (failedFiles.length > 0) {
        Logger.w('tips', `DataSourceManager.importSourceConfigFromFile Failed files: ${failedFiles.join(', ')}`);
      }
      if (skippedSources.length > 0) {
        Logger.w('tips', `DataSourceManager.importSourceConfigFromFile Skipped sources: ${JSON.stringify(skippedSources, null, 2)}`);
      }
    } catch (error) {
      Logger.e('tips', `DataSourceManager.importSourceConfigFromFile Import process failed: ${error.message}`);
      throw new Error(`导入失败: ${error.message}`);
    }
    return message;
  }

  /**
   * 智能解析配置文件，并返回版本信息
   */
  private parseConfigFileWithVersion(content: string): { sources: DataSourceConfig[], version?: string } {
    try {
      const parsed = JSON.parse(content);
      // 情况1: DataSourceConfigFile 格式
      if (parsed && typeof parsed === 'object' && parsed.sources && Array.isArray(parsed.sources)) {
        return { sources: parsed.sources, version: parsed.version };
      }
      // 情况2: DataSourceConfig 数组格式
      if (Array.isArray(parsed)) {
        const isValidArray = parsed.every(item =>
        item && typeof item === 'object' && item.key && item.name
        );
        if (isValidArray) {
          return { sources: parsed }; // 数组格式没有版本信息
        }
      }
      // 情况3: 单个 DataSourceConfig 格式
      if (parsed && typeof parsed === 'object' && parsed.key && parsed.name) {
        return { sources: [parsed] }; // 单个对象格式也没有版本信息
      }
      throw new Error('无法识别的配置文件格式');
    } catch (error) {
      Logger.e('tips', `DataSourceManager.parseConfigFileWithVersion Failed to parse config: ${error.message}`);
      throw new Error(`配置文件解析失败: ${error.message}`);
    }
  }

  /**
   * 检查版本兼容性
   * @param version 配置文件的版本号，例如 "1.2.3"
   * @returns 是否兼容
   */
  private isVersionCompatible(version: string): boolean {
    // 这里实现你的版本兼容性逻辑
    // 示例：只兼容主版本号为1的版本
    const majorVersion = parseInt(version.split('.')[0], 10);
    return majorVersion === 1;
  }


  /**
   * 直接导出给定的数据源配置对象到文件
   * @param context 应用上下文，用于文件选择器
   * @param configs 要导出的数据源配置对象数组。如果不传或为空数组，则导出所有数据源。
   * @returns 返回操作结果消息
   */
  async exportDataSourceConfigs(context: Context, configs?: DataSourceConfig[]): Promise<string> {
    let message = '';
    // 确定要导出的配置和默认文件名
    let configsToExport: DataSourceConfig[];
    let defaultFileName = 'AnimeZ_data_sources.json';
    if (!configs || configs.length === 0) {
      // 模式3: 导出所有数据源配置 (DataSourceConfigFile 格式)
      configsToExport = this.getAllDataSourceConfigs();
      defaultFileName = 'AnimeZ_all_data_sources.json';
    } else {
      // 模式1 & 2: 导出指定的一个或多个数据源 (DataSourceConfig[] 格式)
      configsToExport = configs;
      if (configs.length === 1) {
        // 单个源，用源名做文件名
        defaultFileName = `${configs[0].name}.json`;
      } else {
        // 多个源，用通用名
        defaultFileName = 'AnimeZ_selected_data_sources.json';
      }
    }
    if (configsToExport.length === 0) {
      return "没有找到要导出的数据源";
    }
    // 准备要写入的JSON内容
    let dataToExport: object;
    if (!configs || configs.length === 0) { // 注意这里的判断条件，是基于原始参数
      // 导出全部时，使用完整的文件格式
      dataToExport = {
        version: "1.0.0",
        sources: configsToExport
      };
    } else {
      // 导出部分时，直接导出配置数组
      dataToExport = configsToExport;
    }
    const jsonContent = JSON.stringify(dataToExport, null, 2);
    // 初始化文件选择器
    const filePicker = new picker.DocumentViewPicker(context);
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [defaultFileName];
    options.fileSuffixChoices = ["'JSON文件|.json'"]; // 设置默认后缀为.json
    options.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
    try {
      // 让用户选择保存位置
      const result = await filePicker.save(options);
      if (!result || result.length === 0) {
        return "未选择保存位置，导出已取消";
      }
      const targetUri = new fileUri.FileUri(result[0] + `/${defaultFileName}`).path
      Logger.i(this, `DataSourceManager.exportDataSourceConfigs Exporting to URI: ${targetUri} jsonContent: ${jsonContent.length}`);
      // 将JSON内容写入文件
      const file = fileIo.openSync(targetUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.writeSync(file.fd, jsonContent);
      fileIo.fsync(file.fd).catch((error: Error) => {
        console.warn(`文件的缓存数据同步到存储失败：`, error)
      })
      fileIo.closeSync(file);
      // 返回成功消息
      message = `成功导出 ${configsToExport.length} 个数据源到: ${targetUri}`;
      Logger.i(this, message);
    } catch (error) {
      // 错误处理
      message = `导出失败: ${error.message}`;
      Logger.e('tips', `DataSourceManager.exportDataSourceConfigs ${message}`);
    }
    return message;
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
      // console.log(`从rawfile读取的默认配置文件：${content}`)
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
      Logger.i(this, `DataSourceManager.saveConfigToSandbox sandbox 配置地址：${sandboxPath}`);
      // 转换为JSON字符串
      const jsonContent = JSON.stringify(config, null, 2);
      const sandboxUri = fileUri.getUriFromPath(sandboxPath)
      Logger.i(this, `DataSourceManager.saveConfigToSandbox sandbox 配置地址uri：${sandboxUri}`);
      // 写入配置文件
      let fileModify = fileIo.openSync(sandboxUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.writeSync(fileModify.fd, jsonContent);
      // fileIo.fsync(fileModify.fd).catch((error: Error) => {
      //   console.error(`DataSourceManager.saveConfigToSandbox 文件的缓存数据同步到存储失败：`, error)
      // })
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
   * 搜索所有已启用数据源
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
      Logger.i(this, `DataSourceManager.setDefaultDataSource Set 默认数据源 from config: ${this.currentDataSourceKey}`);
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
