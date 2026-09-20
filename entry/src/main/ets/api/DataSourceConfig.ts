
// 定义配置接口类型
export interface SelectorConfig {
  // 支持简单字符串选择器（向后兼容）
  title?: string | { selector: string; postProcess?: ProcessConfig };
  url?: string | { selector: string; postProcess?: ProcessConfig };
  imgUrl?: string | { selector: string; postProcess?: ProcessConfig };
  episode?: string | { selector: string; postProcess?: ProcessConfig };

  // 支持任意字段的复杂配置
  [key: string]: string | { selector: string; postProcess?: ProcessConfig } | undefined;
}

export interface StringProcessConfig {
  type: 'regex' | 'replace' | 'substring' | 'split';
  pattern?: string;
  flags?: string;
  group?: number;
  search?: string;
  replace?: string;
  start?: string | number;
  end?: string | number;
  delimiter?: string;
  index?: number;
}

export interface ProcessConfig {
  type: 'script' | 'expression' | 'string' | 'condition' | 'transform' | 'pipeline';

  // 脚本执行
  script?: string;
  context?: Record<string, any>;

  // 表达式计算
  expression?: string;

  // 字符串处理
  stringProcess?: StringProcessConfig;

  // 条件处理
  condition?: string;
  trueValue?: any;
  falseValue?: any;

  // 数据转换
  transform?: {
    map?: Record<string, any>;
    template?: string;
  };

  // 管道处理
  steps?: ProcessConfig[];
}


/** 视频集配置接口 */
export interface VideoConfig {
  urlTemplate: string;
  listSelector: string;
  urlNeedBaseUrl: boolean;
  enabledHttps: boolean;
  itemSelectors: SelectorConfig;
}

/** 分类配置接口 */
export interface CategoryConfig {
  title: string;  // 标题选择器
  titles: string; // 标题列表选择器
  moreUrl: string; // 更多链接选择器
  moreUrlNeedBaseUrl: boolean;
  videoLists: string; // 视频列表容器选择器
  videos: VideoConfig;
}

/** 剧集配置接口 */
export interface EpisodeConfig {
  containerSelector?: string;
  itemSelector: string;
  itemSelectors: SelectorConfig;
  routeTitlesSelector?: string;
  routeContainersSelector?: string;
}

/** 推荐配置接口 */
export interface RecommendConfig {
  listSelector: string;
  itemSelectors: SelectorConfig;
  urlNeedBaseUrl: boolean;
  enabledHttps: boolean;
}

/** 番剧详情配置接口 */
export interface DetailConfig {
  titleSelector: string;
  descSelector: string;
  coverSelector: string;
  episodes: EpisodeConfig;
  recommends: RecommendConfig;
  categorySelector?: string;
  directorSelector?: string;
  updateTimeSelector?: string;
  protagonistSelector?: string;
}

/** 视频URL配置接口 */
export interface VideoUrlConfig {
  urlSelector?: string;
  // attribute?: string; // 指定提取视频链接的URL属性名
  pattern?: 'regex' | 'javascript';
  postProcess?: string; // 后处理
  iframeSelector?: string
}

/** 解析配置 */
export interface ParserConfig {
  search: {
    videos: VideoConfig;
  };
  homepage: {
    banner: VideoConfig;
    category: CategoryConfig;
  };
  detail: DetailConfig;
  videoUrl: VideoUrlConfig;
}

/** 数据源配置接口 */
export interface DataSourceConfig {
  key: string;
  name: string;
  group: string,
  baseUrl: string;
  version: string;
  enabled: boolean;
  priority: number;
  description: string
  defaultSource: boolean; // 是否为默认数据源
  parserConfig: ParserConfig;
}

// 配置文件接口
export interface DataSourceConfigFile {
  version: string;
  author: string,
  update_time: string
  sources: DataSourceConfig[];
}

