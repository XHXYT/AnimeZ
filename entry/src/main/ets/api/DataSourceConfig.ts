
// 定义配置接口类型
export interface SelectorConfig {
  // 支持简单字符串选择器（向后兼容）
  title?: string | { selector: string; postProcess?: ProcessConfig };
  url?: string | { selector: string; postProcess?: ProcessConfig };
  imgUrl?: string | { selector: string; postProcess?: ProcessConfig };
  episode?: string | { selector: string; postProcess?: ProcessConfig };
  // 可选扩展字段（VideoInfo 挂载，源里有什么配什么）
  playCount?: string | { selector: string; postProcess?: ProcessConfig };
  year?: string | { selector: string; postProcess?: ProcessConfig };
  month?: string | { selector: string; postProcess?: ProcessConfig };
  director?: string | { selector: string; postProcess?: ProcessConfig };
  actors?: string | { selector: string; postProcess?: ProcessConfig };
  tags?: string | { selector: string; postProcess?: ProcessConfig };

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
  // 可选：条目容器的选择器。在分类“更多”页等整页文档中，先用它定位列表容器，
  // 再用 listSelector 在容器内选取条目；缺省时直接用 listSelector 定位容器
  containerSelector?: string;
  urlNeedBaseUrl: boolean;
  enabledHttps: boolean;
  itemSelectors: SelectorConfig;
}

/** 首页分类卡片配置（每个卡片对应一个独立接口/页面：JSON 模式用 listPath，HTML 模式用 listSelector） */
export interface CategoryCardConfig {
  title: string;            // 卡片标题
  url: string;              // 数据地址（相对 baseUrl 或绝对）：JSON=接口地址，HTML=页面地址
  moreUrl?: string;         // "更多"页地址，支持 {page} 占位符（JSON）或页面地址（HTML）
  listPath?: string;         // JSON 模式：列表在响应中的 JSON 路径，如 data.list
  listSelector?: string;     // HTML 模式：列表的 CSS 选择器，如 .anime-card
  itemSelectors: SelectorConfig; // 字段选择器/模板
  urlNeedBaseUrl?: boolean;
  enabledHttps?: boolean;
  maxItems?: number;        // 显示条数上限（解析前截断，减少主页解析/渲染耗时；完整列表走"更多"）
}

/** 分类配置接口 */
export interface CategoryConfig {
  title: string;  // 标题选择器
  titles: string; // 标题列表选择器
  moreUrl: string; // 更多链接选择器
  moreUrlNeedBaseUrl: boolean;
  videoLists: string; // 视频列表容器选择器
  videos: VideoConfig;
  // JSON 模式：直接声明分类卡片数组（HTML 模式不使用）
  cards?: CategoryCardConfig[];
}

/** 剧集配置接口 */
export interface EpisodeConfig {
  containerSelector?: string;
  itemSelector: string;
  itemSelectors: SelectorConfig;
  routeTitlesSelector?: string;
  routeContainersSelector?: string;
  // JSON 模式：路线/选集接口配置
  jsonRoutesPath?: string;          // 详情响应中的路线数组路径，如 play_from
  jsonRouteTitleTemplate?: string;  // 路线标题模板，上下文为详情字段+路线项字段
  jsonSectionsUrlTemplate?: string; // 选集接口地址模板，如 {baseUrl}/api/videos/{id}/sections?player_code={code}
  jsonListPath?: string;            // 选集列表在响应中的 JSON 路径，默认 data.list
}

/** 推荐配置接口 */
export interface RecommendConfig {
  listSelector: string;
  itemSelectors: SelectorConfig;
  urlNeedBaseUrl: boolean;
  enabledHttps: boolean;
  // JSON 模式：推荐列表接口地址模板，上下文为详情字段
  jsonUrlTemplate?: string;
}

/** 番剧详情配置接口 */
export interface DetailConfig {
  titleSelector: string;
  descSelector: string;
  coverSelector: string;
  // JSON 模式：详情数据在响应中的 JSON 路径，默认 data（支持数组索引，如 PostgREST 数组响应的 0）
  dataPath?: string;
  // JSON 模式：封面地址后处理（如改写为站点图片代理）
  coverPostProcess?: ProcessConfig;
  episodes: EpisodeConfig;
  recommends: RecommendConfig;
  categorySelector?: string;
  directorSelector?: string;
  updateTimeSelector?: string;
  protagonistSelector?: string;
  // 详情扩展字段（播放量/年份/月份/导演/演员/标签），HTML=CSS选择器 / JSON=字段模板，支持后处理
  extra?: SelectorConfig;
}

/** 视频URL配置接口 */
export interface VideoUrlConfig {
  urlSelector?: string;
  // attribute?: string; // 指定提取视频链接的URL属性名
  pattern?: 'regex' | 'javascript' | 'json' | 'link';
  postProcess?: string; // 后处理
  iframeSelector?: string
  // JSON 模式：播放地址在响应中的 JSON 路径，默认 data.url
  valuePath?: string;
}

/** 登录配置接口（当前支持 JSON API 登录） */
export interface LoginConfig {
  type: 'api';
  loginUrl: string;            // 登录接口地址（相对 baseUrl 或绝对）
  usernameField?: string;      // 请求体中用户名字段名，默认 username
  passwordField?: string;      // 请求体中密码字段名，默认 password
  extraBody?: Record<string, string>; // 额外的固定请求体字段
  tokenPath?: string;          // 凭证在登录响应中的 JSON 路径，默认 data.token
  authHeaderName?: string;     // 携带凭证的请求头名，默认 Authorization
  authValueTemplate?: string;  // 请求头值模板，默认 {token}
}

/** 搜索验证码配置（MacCMS dsn2 模板站常见：搜索命中验证码页时引导用户输入图片验证码后重放搜索） */
export interface SearchCaptchaConfig {
  detectSelector: string;         // 命中该选择器说明搜索响应为验证码页
  imageUrlSelector: string;       // 验证码图片选择器（selector@attr 形式；选择器部分留空时回退为 detectSelector+@属性，默认 src，仅当判定元素是 img）
  imageNeedBaseUrl?: boolean;     // 图片地址是否拼接 baseUrl，默认 true
  imageCacheBustParam?: string;   // 获取图片时附加的随机参数名（如 r），拼接 ?r=随机数避免缓存
  verifyUrlTemplate: string;      // 验证码提交地址模板（相对 baseUrl 或绝对），{code} 为用户输入占位
  successContains?: string;       // 提交响应包含该子串视为验证成功（如 "code":1），缺省时仅按重放结果判断
}

/** 解析配置 */
export interface ParserConfig {
  // 解析模式：html（默认，CSS选择器）或 json（JSON 路径 + 模板）
  sourceType?: 'html' | 'json';
  // 请求该源所有接口时附加的自定义请求头（JSON 模式常用，如 X-App-Name）
  requestHeaders?: Record<string, string>;
  search: {
    videos: VideoConfig;
    // 搜索验证码配置（可选）
    captcha?: SearchCaptchaConfig;
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
  author?: string;      // 源作者（导出时随源携带）
  update_time?: string; // 更新日期（YYYY-MM-DD，编辑保存时自动维护）
  enabled: boolean;
  priority: number;
  description: string
  defaultSource: boolean; // 是否为默认数据源
  // 登录配置：配置后源列表长按菜单出现"账号登录"入口
  login?: LoginConfig;
  parserConfig: ParserConfig;
}

// 配置文件接口
export interface DataSourceConfigFile {
  version: string;
  author: string,
  update_time: string
  sources: DataSourceConfig[];
}

