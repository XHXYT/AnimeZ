// 数据源
import { DramaList } from '../entity/HomepageData';
import HomepageData from '../entity/HomepageData';
import Logger from '../utils/Logger';
import EpisodeInfo from '../entity/EpisodeInfo';
import VideoInfo, { TypeInfo } from '../entity/VideoInfo';
import EpisodeList from '../entity/EpisodeList';
import VideoDetailInfo from '../entity/VideoDetailInfo';
import HttpUtils from '../utils/HttpUtils';
import DataSource from './DataSource';
import {
  select,
  selectAttributeValue,
  selectFirst,
  selectTextContent,
  textContent,
} from '../utils/thirdpart/htmlsoup';
import { AnyNode, HtmlTag } from '../utils/thirdpart/htmlsoup/parse';
import {
  CategoryConfig, EpisodeConfig, ParserConfig, RecommendConfig,
  SelectorConfig, VideoConfig, ProcessConfig, CategoryCardConfig, LoginConfig } from './DataSourceConfig';
import { ScriptProcessor } from './ScriptProcessor';
import AuthStore from '../utils/AuthStore';

// 扩展SelectorConfig类型以支持更灵活的配置
type SelectorValue = string | { selector: string; postProcess?: ProcessConfig };
type ExtendedSelectorConfig = Record<string, SelectorValue>;

export default class GenericDataSource implements DataSource {
  private key: string;
  private name: string;
  private baseUrl: string;
  private enabled: boolean;  // 是否启用
  private priority: number;  // 优先级
  private parserConfig: ParserConfig;
  // JSON 模式支持
  private sourceType: 'html' | 'json';
  private requestHeaders?: Record<string, string>;
  private loginConfig?: LoginConfig;

  constructor(config: any) {
    this.key = config.key;
    this.name = config.name || config.key;
    this.baseUrl = config.baseUrl;
    this.enabled = config.enabled !== false; // 默认为true
    this.priority = config.priority || 0;
    this.parserConfig = config.parserConfig;
    this.sourceType = config.parserConfig?.sourceType || 'html';
    this.requestHeaders = config.parserConfig?.requestHeaders;
    this.loginConfig = config.login;

    // 验证必要字段
    if (!this.key) throw new Error('Missing key in data source configuration');
    if (!this.baseUrl) throw new Error('Missing baseUrl in data source configuration');
    if (!this.parserConfig) throw new Error('Missing parserConfig in data source configuration');
  }

  getKey(): string {
    return this.key;
  }

  getBaseUrl(): string {
    return this.baseUrl
  }

  getName(): string {
    return this.name;
  }

  getPriority(): number {
    return this.priority;
  }

  isEnabled(): boolean {
    return this.enabled;
  }

  /**
   * 是否配置了可用的首页数据规则
   */
  hasHomepageConfig(): boolean {
    const homepage = this.parserConfig?.homepage;
    if (!homepage) {
      return false;
    }
    if (this.isJsonMode()) {
      return !!(homepage.banner?.urlTemplate
        || (homepage.category?.cards && homepage.category.cards.length > 0));
    }
    return !!((homepage.category && homepage.category.videos
      && homepage.category.videos.listSelector)
      || (homepage.category?.cards && homepage.category.cards.length > 0));
  }

  private isJsonMode(): boolean {
    return this.sourceType === 'json';
  }

  async search(keyword: string, page: number): Promise<VideoInfo[]> {
    const config = this.parserConfig.search;
    const url = this.baseUrl + config.videos.urlTemplate
      .replace('{keyword}', encodeURIComponent(keyword))
      .replace('{page}', page.toString());

    const videos: VideoInfo[] = [];
    try {
      if (this.isJsonMode()) {
        const resp = await this.requestJson(url);
        return this.parseJsonVideoList(resp, config.videos.listSelector,
          config.videos.itemSelectors as ExtendedSelectorConfig,
          config.videos.urlNeedBaseUrl, config.videos.enabledHttps);
      }

      const doc = await this.parseHtml(url);
      const list = select(doc, config.videos.listSelector);

      // 使用Promise.all并行处理所有视频项
      const videoPromises = list.map(async (li) => {
        return await this.extractVideoInfo(li, config.videos.itemSelectors as ExtendedSelectorConfig, config.videos.urlNeedBaseUrl, config.videos.enabledHttps);
      });

      const resolvedVideos = await Promise.all(videoPromises);
      videos.push(...resolvedVideos);

      return videos;
    } catch (e) {
      Logger.e('fail', 'GenericDataSource 搜索', e);
      return [];
    }
  }

  async getHomepageData(): Promise<HomepageData> {
    const config = this.parserConfig.homepage;
    try {
      if (this.isJsonMode()) {
        // JSON 模式：banner 与分类卡片各自请求独立接口
        const [bannerList, categoryList] = await Promise.all([
          this.extractJsonBannerList(config.banner),
          this.extractJsonCategoryList(config.category)
        ]);
        return { bannerList, categoryList };
      }

      console.log(`获取主页配置：${JSON.stringify(config)}`)
      const doc = await this.parseHtml(this.baseUrl)
      console.log(`网页doc已获取`)

      // 并行处理banner和category
      const [bannerList, categoryList] = await Promise.all([
        this.extractBannerList(doc, config.banner),
        this.extractHtmlCategoryList(doc, config.category)
      ]);

      return { bannerList, categoryList };
    } catch (e) {
      Logger.e('fail', `获取主页数据`, e);
      throw e;
    }
  }

  async getVideoList(moreUrl: string, page: number): Promise<VideoInfo[]> {
    if (this.isJsonMode()) {
      try {
        // JSON 模式：moreUrl 即数据接口地址，支持 {page} 占位符
        let url = moreUrl;
        if (url.includes('{page}')) {
          url = url.replace('{page}', (page > 0 ? page : 1).toString());
        } else if (page > 0) {
          url += (url.includes('?') ? '&' : '?') + 'page=' + page;
        }
        const videosConfig = this.parserConfig.homepage.category.videos;
        const resp = await this.requestJson(url);
        return this.parseJsonVideoList(resp, videosConfig.listSelector,
          videosConfig.itemSelectors as ExtendedSelectorConfig,
          videosConfig.urlNeedBaseUrl, videosConfig.enabledHttps);
      } catch (e) {
        Logger.e('fail', `获取视频列表(JSON)`, e);
        throw e
      }
    }

    const url = `${moreUrl}${page <= 0 ? '' : page}`;
    Logger.e('tips', "CategoryPage #getVideoList parseHtml url = " + url);

    try {
      const doc = await this.parseHtml(url);
      const videosConfig = this.parserConfig.homepage.category.videos;
      // 优先使用 containerSelector 在整页文档中定位列表容器，
      // 再用 listSelector 在容器内选取条目（避免同选择器在文档层匹配到条目自身）
      const containerSelector = videosConfig.containerSelector || videosConfig.listSelector;
      const drama = selectFirst(doc, containerSelector);

      if (!drama) {
        return [];
      }

      return await this.parseVideoList(drama, this.parserConfig.homepage.category.videos);
    } catch (e) {
      Logger.e('fail', `获取视频列表`, e);
      throw e
    }
  }

  private async parseVideoList(drama: HtmlTag, config: VideoConfig): Promise<VideoInfo[]> {
    const elements = select(drama, config.listSelector);
    Logger.e('tips', 'parseHtml elements=' + elements.length);

    // 并行处理所有视频项
    const videoPromises = elements.map(async (li) => {
      Logger.e('tips', "parseHtml el=" + li);
      return await this.extractVideoInfo(li, config.itemSelectors as ExtendedSelectorConfig, config.urlNeedBaseUrl, config.enabledHttps);
    });

    return await Promise.all(videoPromises);
  }

  async getVideoDetailInfo(url: string, order: "asc" | "desc" = 'asc'): Promise<VideoDetailInfo> {
    if (this.isJsonMode()) {
      try {
        return await this.getJsonVideoDetail(url);
      } catch (e) {
        Logger.e('fail', `获取视频详情(JSON)`, e);
        throw e;
      }
    }

    try {
      console.log(`GenericDataSource.getVideoDetailInfo 等待加载的链接：${url}`)
      const doc = await this.parseHtml(url);
      const config = this.parserConfig.detail;

      // 安全地分割选择器
      const coverSelectorParts = config.coverSelector.split('@');
      const coverSel = coverSelectorParts[0];
      const coverAttr = coverSelectorParts[1];

      // 并行处理所有字段
      const [
        title,
        desc,
        coverUrl,
        category,
        director,
        updateTime,
        protagonist,
        recommends,
        episodesList
      ] = await Promise.all([
        this.selectText(doc, config.titleSelector),
        this.selectText(doc, config.descSelector).then(t => t.trim()),
        this.selectAttribute(doc, coverSel, coverAttr),
        config.categorySelector ? this.selectText(doc, config.categorySelector) : Promise.resolve(''),
        config.directorSelector ? this.selectText(doc, config.directorSelector) : Promise.resolve(''),
        config.updateTimeSelector ? this.selectText(doc, config.updateTimeSelector) : Promise.resolve(''),
        config.protagonistSelector ? this.selectText(doc, config.protagonistSelector) : Promise.resolve(''),
        this.extractRecommends(doc, config.recommends),
        this.extractEpisodes(doc, config.episodes).then(episodes => {
          return episodes.map(episodes => {
            return {
              title: episodes.title,
              // 规范列表保持源站自然顺序，排序仅由显示层处理，
              // 保证历史记录中保存的 episodeIndex 不随排序设置变化
              episodes: episodes.episodes
            }
          });
        })
      ]);

      Logger.e('tips', 'getVideoDetailInfo title=' + title);

      // 封面为相对路径（/upload/...）时拼接 baseUrl（排除协议相对路径 //host）
      const finalCoverUrl = (coverUrl && coverUrl.startsWith('/') && !coverUrl.startsWith('//'))
        ? this.baseUrl + coverUrl : coverUrl;

      const info: VideoDetailInfo = {
        sourceKey: this.key,
        title: title,
        url: url,
        desc: desc,
        coverUrl: finalCoverUrl,
        category: category,
        director: director,
        updateTime: updateTime,
        protagonist: protagonist,
        episodes: episodesList,
        recommends: recommends
      };

      return info;
    } catch (e) {
      Logger.e('fail', `获取视频详情`, e);
      throw e;
    }
  }

  async parseVideoUrl(link: string): Promise<string> {
    Logger.d('tips', 'parseVideoUrl link= ' + link);

    try {
      const config = this.parserConfig.videoUrl;
      let url = ''

      if (config.pattern === 'json') {
        // JSON 模式：link 即播放地址接口，直接请求并按路径取值
        const resp = await this.requestJson(link);
        const valuePath = config.valuePath || 'data.url';
        const value = this.getJsonPath(resp, valuePath);
        if (value === null || value === undefined || String(value) === '') {
          throw new Error('播放地址解析失败，接口未返回播放地址');
        }
        url = String(value);

        if (config.postProcess) {
          url = await this.applyLegacyPostProcess(url, config.postProcess);
        }
      } else if (config.pattern === 'link') {
        // link 模式：link 本身即为播放页地址，直接透传（通常配合 iframeSelector 交给 WebView 解析）
        url = link;
      } else if (config.pattern === 'regex' && config.urlSelector) {
        // 使用正则表达式方式提取URL（pattern 为 regex 时，urlSelector 字段即正则表达式）
        const htmlString = await HttpUtils.getString(link);
        const match = htmlString.match(new RegExp(config.urlSelector));

        if (match && match[1]) {
          url = match[1];

          // 应用后处理
          if (config.postProcess) {
            url = await this.applyLegacyPostProcess(url, config.postProcess);
          }
        }
      } else if (config.urlSelector) {
        // 使用选择器方式提取URL
        const doc = await HttpUtils.getHtml(link);

        // 安全地分割选择器
        const urlSelectorParts = config.urlSelector.split('@');
        const urlSel = urlSelectorParts[0];
        const urlAttr = urlSelectorParts[1];

        url = await this.selectAttribute(doc, urlSel, urlAttr);
        Logger.e('tips', `parseVideoUrl extracted attribute value url = ${url}`);

        if (url == '') {
          Logger.e('tips', `parseVideoUrl 解析失败，输入url为空`)
          throw ('parseVideoUrl 解析失败，输入url为空')
        }

        if (url && config.postProcess) {
          url = await this.applyLegacyPostProcess(url, config.postProcess);
        }

        Logger.e('tips', `parseVideoUrl final url = ${url}`);
      }

      // 如果存在内嵌提取配置（webview）
      if (config.iframeSelector) {
        console.log(`parseVideoUrl 存在内嵌视频解析配置`)
        // 获取iframe页 视频URL (传递到UI层去解析)
        const iframeUrl = `${url}_|_${config.iframeSelector}`
        console.log(`parseVideoUrl 内嵌视频解析为link：${iframeUrl}`)
        url = iframeUrl
      }
      return url;
    } catch (e) {
      Logger.e('fail', `解析视频URL`, e);
      throw new Error('无法解析视频URL, err: ' + e);
    }
  }

  /**
   * 应用旧版后处理（向后兼容）
   */
  private async applyLegacyPostProcess(url: string, postProcess: string): Promise<string> {
    let processedUrl = url;

    if (postProcess.includes("substringBetween")) {
      const [start, end] = postProcess
        .replace("substringBetween('", "")
        .replace("')", "")
        .split("', '");

      const startIndex = processedUrl.indexOf(start) + start.length;
      const endIndex = processedUrl.indexOf(end, startIndex);
      processedUrl = processedUrl.substring(startIndex, endIndex);
    }

    if (postProcess.includes("replaceAll")) {
      const [search, replace] = postProcess
        .replace("replaceAll('", "")
        .replace("')", "")
        .split("', '");

      processedUrl = processedUrl.replace(new RegExp(search, 'g'), replace);
    }

    return processedUrl;
  }

  /**
   * 提取视频信息
   */
  private async extractVideoInfo(element: HtmlTag, selectors: ExtendedSelectorConfig, urlNeedBaseUrl: boolean, enabledHttps: boolean = true): Promise<VideoInfo> {
    const info: VideoInfo = {
      sourceKey: this.key,
      url: '',
      imgUrl: '',
      title: '',
      episode: ''
    };

    // 并行处理所有字段
    const promises = Object.entries(selectors).map(async ([key, config]) => {
      let value: string;

      if (typeof config === 'string') {
        // 简单选择器（向后兼容）
        value = await this.extractSimpleValue(element, config);
      } else if (config && config.selector) {
        // 复杂配置
        value = await this.extractSimpleValue(element, config.selector);

        // 应用后处理
        if (config.postProcess) {
          value = await ScriptProcessor.execute<string>(value, config.postProcess);
        }
      } else {
        return { key, value: '' };
      }

      // URL处理逻辑
      if (key === 'url' && value && !value.startsWith('http') && urlNeedBaseUrl) {
        value = this.baseUrl + value;
      }

      // 图片相对路径（/upload/...）同样需要拼接 baseUrl（排除协议相对路径 //host）
      if (key === 'imgUrl' && value && urlNeedBaseUrl
        && value.startsWith('/') && !value.startsWith('//')) {
        value = this.baseUrl + value;
      }

      if (value.startsWith('http://') && enabledHttps) {
        value = 'https://' + value.substring(7);
      }

      return { key, value };
    });

    // 等待所有处理完成
    const results = await Promise.all(promises);

    // 设置结果
    results.forEach(({ key, value }) => {
      (info as any)[key] = value;
    });

    return info;
  }

  /**
   * 提取简单值
   */
  private async extractSimpleValue(element: HtmlTag, selector: string): Promise<string> {
    if (selector.includes('@')) {
      // 处理带属性提取的选择器（如 "img@src"）
      const [sel, attr] = selector.split('@');
      const el = selectFirst(element, sel);
      return el ? el.attr(attr) : '';
    } else {
      // 处理纯文本选择器（如 "h1"）
      return selectTextContent(element, selector) || '';
    }
  }

  /**
   * 提取Banner列表
   */
  private async extractBannerList(doc: AnyNode, config: VideoConfig): Promise<VideoInfo[]> {
    if (!config) return [];

    const list = select(doc, config.listSelector);
    console.log(`解析到的BannerList数目：${list.length}`)

    // 并行处理所有banner项
    const bannerPromises = list.map(async (li) => {
      return await this.extractVideoInfo(li, config.itemSelectors as ExtendedSelectorConfig, config.urlNeedBaseUrl, config.enabledHttps);
    });

    return await Promise.all(bannerPromises);
  }

  /**
   * HTML 模式：提取分类列表
   * 配置了 cards 时每个卡片独立请求自己的页面；否则回退到首页同页解析
   */
  private async extractHtmlCategoryList(doc: AnyNode, categoriesConfig: CategoryConfig): Promise<DramaList[]> {
    const cards = categoriesConfig?.cards;
    if (cards && cards.length > 0) {
      return await Promise.all(cards.map(card => this.processHtmlCategoryCard(card)));
    }
    return await this.extractCategoryList(doc, categoriesConfig);
  }

  /**
   * HTML 模式：处理单个分类卡片（独立请求卡片页面并解析列表）
   */
  private async processHtmlCategoryCard(card: CategoryCardConfig): Promise<DramaList> {
    let videoList: VideoInfo[] = [];
    try {
      const pageUrl = card.url.includes('http') ? card.url : this.baseUrl + card.url;
      const doc = await this.parseHtml(pageUrl);
      const listSelector = card.listSelector || card.listPath || '';
      const items = select(doc, listSelector);
      videoList = await Promise.all(items.map(async (li) => {
        return await this.extractVideoInfo(li, card.itemSelectors as ExtendedSelectorConfig,
          card.urlNeedBaseUrl ?? true, card.enabledHttps ?? true);
      }));
    } catch (e) {
      Logger.e('fail', `解析分类卡片(HTML): ${card.title}`, e);
    }
    let moreUrl = card.moreUrl || '';
    if (moreUrl && !moreUrl.includes('http')) {
      moreUrl = this.baseUrl + moreUrl;
    }
    return {
      title: card.title,
      moreUrl: moreUrl,
      videoList: videoList
    };
  }

  /**
   * 提取分类列表
   */
  private async extractCategoryList(doc: AnyNode, categoriesConfig: CategoryConfig): Promise<DramaList[]> {
    if (!categoriesConfig) return [];

    const titles = select(doc, categoriesConfig.titles);
    const videoLists = select(doc, categoriesConfig.videoLists);
    const count = Math.min(titles.length, videoLists.length);
    console.log(`GenericDataSource.extractCategoryList 解析到的标题数：${titles.length}, 番剧列表数：${videoLists.length}, 最后取值：${count}`)

    const categoryPromises = [];
    for (let i = 0; i < count; i++) {
      const title = titles[i];
      const list = videoLists[i];

      categoryPromises.push(this.processCategoryItem(title, list, categoriesConfig));
    }

    return await Promise.all(categoryPromises);
  }

  /**
   * 处理单个分类项
   */
  private async processCategoryItem(title: AnyNode, list: AnyNode, categoriesConfig: CategoryConfig): Promise<DramaList> {
    const lis = select(list, categoriesConfig.videos.listSelector);
    console.log(`解析到CategoryList番剧数目：${lis.length}`)

    // 并行处理所有视频项
    const videoPromises = lis.map(async (li) => {
      return await this.extractVideoInfo(li, categoriesConfig.videos.itemSelectors as ExtendedSelectorConfig, categoriesConfig.videos.urlNeedBaseUrl, categoriesConfig.videos.enabledHttps);
    });

    const videos = await Promise.all(videoPromises);

    // 解析更多链接
    let rawMoreUrl = await this.selectAttribute(title, categoriesConfig.moreUrl);
    if (rawMoreUrl.startsWith('http://')) {
      rawMoreUrl = 'https://' + rawMoreUrl.substring(7);
    }

    // 提取原始项标题
    const rawTitle = await this.selectText(title, categoriesConfig.title);
    console.log(`GenericDataSource.extractCategoryList 原始项标题: ${rawTitle}`)

    // 使用更通用的正则表达式，同时处理开头和结尾的情况, 过滤掉"更多"等杂质
    const cleanTitle = rawTitle.replace(/^\s*(更多|More|查看更多|View All|全部)\s*[»→...->>>>]*\s*|\s*(更多|More|查看更多|View All|全部)\s*[»→...->>>>]*\s*$/g, '').trim();
    console.log(`GenericDataSource.extractCategoryList 过滤后项标题: ${cleanTitle}`)

    // 推送目录列表
    return {
      title: cleanTitle,
      moreUrl: categoriesConfig.moreUrlNeedBaseUrl ? (this.baseUrl + rawMoreUrl) : rawMoreUrl,
      videoList: videos
    };
  }

  /**
   * 提取剧集列表
   */
  private async extractEpisodes(doc: AnyNode, config: EpisodeConfig): Promise<EpisodeList[]> {
    const episodes: EpisodeList[] = [];

    if (config.routeTitlesSelector && config.routeContainersSelector) {
      // 多路线情况
      const routeTitles = select(doc, config.routeTitlesSelector);
      const routeContainers = select(doc, config.routeContainersSelector);

      for (let i = 0; i < Math.min(routeTitles.length, routeContainers.length); i++) {
        const title = textContent(routeTitles[i]);
        const container = routeContainers[i];

        const items = select(container, config.itemSelector);
        const episodeInfos = await Promise.all(items.map(async (item) => {
          const urlSelector = config.itemSelectors.url;
          const titleSelector = config.itemSelectors.title;

          // 安全地获取URL选择器
          const urlSelectorStr = typeof urlSelector === 'string' ? urlSelector : urlSelector.selector;
          const urlSelectorParts = urlSelectorStr.split('@');
          const urlSel = urlSelectorParts[0];
          const urlAttr = urlSelectorParts[1];

          const url = await this.selectAttribute(item, urlSel, urlAttr);

          // 安全地获取标题选择器
          const titleSelectorStr = typeof titleSelector === 'string' ? titleSelector : titleSelector.selector;
          const title = await this.selectText(item, titleSelectorStr);

          console.log(`extractEpisodes 多路线 视频详情链接是否拼接baseUrl：${url.includes('http') } 提取的url：${url} link：${url.includes('http') ? url : (this.baseUrl + url)}`)
          return {
            link: url.includes('http') ? url : (this.baseUrl + url),
            title,
            desc: title
          };
        }));

        episodes.push({ title, episodes: episodeInfos });
      }
    } else if (config.containerSelector) {
      // 单路线情况
      const container = selectFirst(doc, config.containerSelector);
      if (container) {
        const items = select(container, config.itemSelector);
        const episodeInfos = await Promise.all(items.map(async (item) => {
          const urlSelector = config.itemSelectors.url;
          const titleSelector = config.itemSelectors.title;

          // 安全地获取URL选择器
          const urlSelectorStr = typeof urlSelector === 'string' ? urlSelector : urlSelector.selector;
          const urlSelectorParts = urlSelectorStr.split('@');
          const urlSel = urlSelectorParts[0];
          const urlAttr = urlSelectorParts[1];

          const url = await this.selectAttribute(item, urlSel, urlAttr);

          // 安全地获取标题选择器
          const titleSelectorStr = typeof titleSelector === 'string' ? titleSelector : titleSelector.selector;
          const title = await this.selectText(item, titleSelectorStr);

          console.log(`extractEpisodes 单路线 视频详情链接是否拼接baseUrl：${url.includes('http') } 提取的url：${url} link：${url.includes('http') ? url : (this.baseUrl + url)}`)
          return {
            link: url.includes('http') ? url : (this.baseUrl + url),
            title,
            desc: title
          };
        }));

        episodes.push({ title: "剧集列表", episodes: episodeInfos });
      }
    }

    return episodes;
  }

  /**
   * 提取推荐列表
   */
  private async extractRecommends(doc: AnyNode, config: RecommendConfig): Promise<VideoInfo[]> {
    const items = select(doc, config.listSelector);

    // 并行处理所有推荐项
    const recommendPromises = items.map(async (item) => {
      return await this.extractVideoInfo(item, config.itemSelectors as ExtendedSelectorConfig, config.urlNeedBaseUrl, config.enabledHttps);
    });

    return await Promise.all(recommendPromises);
  }

  private async parseHtml(url: string): Promise<AnyNode> {
    return await HttpUtils.getHtml(url);
  }

  // ==================== JSON 模式 ====================

  /**
   * 按点分路径从 JSON 对象中取值，支持数组索引（如 data.list.0.videos）
   */
  private getJsonPath(root: object | null, path: string): any {
    if (root === null || root === undefined) {
      return null;
    }
    if (!path) {
      return root;
    }
    let current: any = root;
    const parts = path.split('.');
    for (const part of parts) {
      if (current === null || current === undefined) {
        return null;
      }
      if (Array.isArray(current)) {
        const index = parseInt(part, 10);
        current = isNaN(index) ? current[part] : current[index];
      } else if (typeof current === 'object') {
        current = current[part];
      } else {
        return null;
      }
    }
    return current === undefined ? null : current;
  }

  /**
   * 渲染字段模板：{baseUrl} 为源根地址，其余占位符按点分路径从上下文取值；
   * 取到数组时以 / 连接
   */
  private renderTemplate(template: string, context: object | null): string {
    if (!template) {
      return '';
    }
    return template.replace(/\{([^{}]+)\}/g, (match, key: string) => {
      const name = key.trim();
      if (name === 'baseUrl') {
        return this.baseUrl;
      }
      const value = this.getJsonPath(context, name);
      if (value === null || value === undefined) {
        return '';
      }
      if (Array.isArray(value)) {
        return value.filter(item => item !== null && item !== undefined).map(item => String(item)).join('/');
      }
      return String(value);
    });
  }

  /**
   * 请求 JSON 接口：自动拼接 baseUrl、附加自定义请求头与登录凭证，
   * 响应 code 非 0 时抛出业务错误
   */
  private async requestJson(urlOrPath: string, needAuth: boolean = true): Promise<any> {
    const url = urlOrPath.startsWith('http') ? urlOrPath : this.baseUrl + urlOrPath;
    const headers: Record<string, string> = {};
    if (this.requestHeaders) {
      Object.assign(headers, this.requestHeaders);
    }
    if (needAuth && this.loginConfig) {
      const token = await AuthStore.getToken(this.key);
      if (token) {
        const headerName = this.loginConfig.authHeaderName || 'Authorization';
        headers[headerName] = (this.loginConfig.authValueTemplate || '{token}').replace('{token}', token);
      }
    }
    const text = await HttpUtils.getString(url, headers);
    const parsed = JSON.parse(text);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)
      && parsed.code !== undefined && parsed.code !== 0) {
      throw new Error(parsed.msg || `接口返回错误码 ${parsed.code}`);
    }
    return parsed;
  }

  /**
   * 从 JSON 响应中解析视频列表（listPath 定位数组，itemSelectors 为字段模板）
   */
  private async parseJsonVideoList(resp: object, listPath: string,
    selectors: ExtendedSelectorConfig, urlNeedBaseUrl: boolean, enabledHttps: boolean): Promise<VideoInfo[]> {
    const videos: VideoInfo[] = [];
    const list = this.getJsonPath(resp, listPath);
    if (Array.isArray(list)) {
      for (const item of list) {
        if (item && typeof item === 'object') {
          videos.push(await this.mapJsonItem(item, selectors, urlNeedBaseUrl, enabledHttps));
        }
      }
    }
    return videos;
  }

  /**
   * 将单个 JSON 对象按字段模板映射为 VideoInfo
   */
  private async mapJsonItem(item: object, selectors: ExtendedSelectorConfig,
    urlNeedBaseUrl: boolean, enabledHttps: boolean): Promise<VideoInfo> {
    const info: VideoInfo = {
      sourceKey: this.key,
      url: '',
      imgUrl: '',
      title: '',
      episode: ''
    };

    for (const [key, config] of Object.entries(selectors)) {
      const template = typeof config === 'string' ? config : (config && config.selector ? config.selector : '');
      let value = this.renderTemplate(template, item);

      if (typeof config !== 'string' && config && config.postProcess && value) {
        try {
          value = await ScriptProcessor.execute<string>(value, config.postProcess);
        } catch (e) {
          Logger.e('fail', `mapJsonItem postProcess ${key}`, e);
        }
      }

      if (key === 'url' && value && !value.startsWith('http') && urlNeedBaseUrl) {
        value = this.baseUrl + value;
      }
      if (key === 'imgUrl' && value && urlNeedBaseUrl
        && value.startsWith('/') && !value.startsWith('//')) {
        value = this.baseUrl + value;
      }
      if (value.startsWith('http://') && enabledHttps) {
        value = 'https://' + value.substring(7);
      }

      (info as any)[key] = value;
    }

    return info;
  }

  /**
   * 今天是周几（1=周一 ... 7=周日），用于 {today} 占位符
   */
  private getTodayWeekday(): number {
    const day = new Date().getDay(); // 0=周日
    return day === 0 ? 7 : day;
  }

  /**
   * JSON 模式：解析轮播图（追番周表当天数据等）
   */
  private async extractJsonBannerList(config: VideoConfig): Promise<VideoInfo[]> {
    if (!config || !config.urlTemplate) {
      return [];
    }
    try {
      const url = config.urlTemplate.replace('{today}', this.getTodayWeekday().toString());
      // listSelector 以 regex: 开头时：先取原始文本，再用正则捕获 JSON 数组（用于 RSC/flight 等非纯 JSON 响应）
      if (config.listSelector && config.listSelector.startsWith('regex:')) {
        const fullUrl = url.startsWith('http') ? url : this.baseUrl + url;
        const headers: Record<string, string> = {};
        if (this.requestHeaders) {
          Object.assign(headers, this.requestHeaders);
        }
        const text = await HttpUtils.getString(fullUrl, headers);
        const match = text.match(new RegExp(config.listSelector.substring(6)));
        if (!match || !match[1]) {
          Logger.e('tips', 'extractJsonBannerList regex 未匹配到轮播数据');
          return [];
        }
        const bannerArray = JSON.parse(match[1]);
        if (!Array.isArray(bannerArray)) {
          return [];
        }
        return this.parseJsonVideoList(bannerArray, '',
          config.itemSelectors as ExtendedSelectorConfig, config.urlNeedBaseUrl, config.enabledHttps);
      }
      const resp = await this.requestJson(url);
      return this.parseJsonVideoList(resp, config.listSelector,
        config.itemSelectors as ExtendedSelectorConfig, config.urlNeedBaseUrl, config.enabledHttps);
    } catch (e) {
      Logger.e('fail', `解析轮播图(JSON)`, e);
      return [];
    }
  }

  /**
   * JSON 模式：按配置卡片数组解析首页分类列表（每卡片对应独立接口）
   */
  private async extractJsonCategoryList(categoriesConfig: CategoryConfig): Promise<DramaList[]> {
    const cards = categoriesConfig?.cards;
    if (!cards || cards.length === 0) {
      return [];
    }
    return await Promise.all(cards.map(card => this.processJsonCategoryCard(card)));
  }

  private async processJsonCategoryCard(card: CategoryCardConfig): Promise<DramaList> {
    let videoList: VideoInfo[] = [];
    try {
      const resp = await this.requestJson(card.url);
      videoList = await this.parseJsonVideoList(resp, card.listPath,
        card.itemSelectors as ExtendedSelectorConfig,
        card.urlNeedBaseUrl ?? false, card.enabledHttps ?? true);
    } catch (e) {
      Logger.e('fail', `解析分类卡片(JSON): ${card.title}`, e);
    }
    return {
      title: card.title,
      moreUrl: card.moreUrl || '',
      videoList: videoList
    };
  }

  /**
   * JSON 模式：获取视频详情（url 即详情接口地址）
   */
  private async getJsonVideoDetail(url: string): Promise<VideoDetailInfo> {
    const config = this.parserConfig.detail;
    const resp = await this.requestJson(url);
    const data = this.getJsonPath(resp, 'data');
    if (!data || typeof data !== 'object') {
      throw new Error('详情数据为空');
    }

    const episodes = await this.extractJsonEpisodes(data);
    const recommends = await this.extractJsonRecommends(data);

    let coverUrl = this.renderTemplate(config.coverSelector, data);
    // 封面地址后处理（如改写为站点图片代理）
    if (config.coverPostProcess && coverUrl) {
      try {
        coverUrl = await ScriptProcessor.execute<string>(coverUrl, config.coverPostProcess);
      } catch (e) {
        Logger.e('fail', `详情封面后处理`, e);
      }
    }
    const finalCoverUrl = (coverUrl && coverUrl.startsWith('/') && !coverUrl.startsWith('//'))
      ? this.baseUrl + coverUrl : coverUrl;

    // 简介字段可能内嵌 HTML 标签与实体，去除标签并解码常见实体
    const rawDesc = this.renderTemplate(config.descSelector, data);
    const desc = rawDesc
      .replace(/<[^>]*>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .trim();

    return {
      sourceKey: this.key,
      title: this.renderTemplate(config.titleSelector, data),
      url: url,
      desc: desc,
      coverUrl: finalCoverUrl,
      category: config.categorySelector ? this.renderTemplate(config.categorySelector, data) : '',
      director: config.directorSelector ? this.renderTemplate(config.directorSelector, data) : '',
      updateTime: config.updateTimeSelector ? this.renderTemplate(config.updateTimeSelector, data) : '',
      protagonist: config.protagonistSelector ? this.renderTemplate(config.protagonistSelector, data) : '',
      episodes: episodes,
      recommends: recommends
    };
  }

  /**
   * JSON 模式：解析选集路线（如 play_from），逐路线请求选集接口
   */
  private async extractJsonEpisodes(detailData: object): Promise<EpisodeList[]> {
    const config = this.parserConfig.detail.episodes;
    const episodes: EpisodeList[] = [];
    if (!config.jsonRoutesPath) {
      return episodes;
    }

    const routes = this.getJsonPath(detailData, config.jsonRoutesPath);
    if (!Array.isArray(routes) || routes.length === 0) {
      return episodes;
    }

    const listPath = config.jsonListPath || 'data.list';
    const titleTemplate = config.jsonRouteTitleTemplate || '{title}';
    const sectionsUrlTemplate = config.jsonSectionsUrlTemplate || '';

    for (let routeIndex = 0; routeIndex < routes.length; routeIndex++) {
      const route = routes[routeIndex];
      if (!route || typeof route !== 'object') {
        continue;
      }
      // 插值上下文：详情字段 + 路线项字段（路线项优先）
      const context = Object.assign({}, detailData, route);
      const routeTitle = this.renderTemplate(titleTemplate, context);
      try {
        let list: object | null = null;
        if (sectionsUrlTemplate) {
          // 每条路线独立请求选集接口
          const sectionsUrl = this.renderTemplate(sectionsUrlTemplate, context);
          const resp = await this.requestJson(sectionsUrl);
          list = this.getJsonPath(resp, listPath);
        } else {
          // 未配置选集接口：剧集列表内嵌在路线对象中（jsonListPath 相对路线项取值）
          list = this.getJsonPath(route, listPath);
        }
        const episodeInfos: EpisodeInfo[] = [];
        if (Array.isArray(list)) {
          for (const item of list) {
            if (!item || typeof item !== 'object') {
              continue;
            }
            // 插值上下文：详情字段 + 路线字段 + 剧集字段（剧集优先）+ 路线索引
            const itemContext = Object.assign({}, detailData, route, item, { routeIndex: routeIndex });
            const mapped = await this.mapJsonItem(itemContext, config.itemSelectors as ExtendedSelectorConfig, false, false);
            episodeInfos.push({
              link: mapped.url,
              title: mapped.title,
              desc: mapped.title
            });
          }
        }
        episodes.push({ title: routeTitle, episodes: episodeInfos });
      } catch (e) {
        Logger.e('fail', `解析选集(JSON) 路线 ${routeTitle}`, e);
      }
    }

    return episodes;
  }

  /**
   * JSON 模式：解析相关推荐
   */
  private async extractJsonRecommends(detailData: object): Promise<VideoInfo[]> {
    const config = this.parserConfig.detail.recommends;
    if (!config || !config.jsonUrlTemplate) {
      return [];
    }
    try {
      const url = this.renderTemplate(config.jsonUrlTemplate, detailData);
      const resp = await this.requestJson(url);
      return this.parseJsonVideoList(resp, config.listSelector,
        config.itemSelectors as ExtendedSelectorConfig, config.urlNeedBaseUrl, config.enabledHttps);
    } catch (e) {
      Logger.e('fail', `解析推荐(JSON)`, e);
      return [];
    }
  }

  private extractVideoUrlFromScript(html: string, pattern: string): string | null {
    // 使用正则表达式匹配视频URL
    const regex = new RegExp(pattern);
    const match = html.match(regex);

    if (match && match[1]) {
      return match[1];
    }

    return null;
  }

  /**
   * 选择文本
   */
  private async selectText(context: AnyNode, selector: string, postProcess?: ProcessConfig): Promise<string> {
    let text = selectTextContent(context, selector) || '';

    if (postProcess) {
      text = await ScriptProcessor.execute<string>(text, postProcess);
    }

    return text;
  }

  /**
   * 选择属性
   */
  private async selectAttribute(context: AnyNode, selector: string, attribute?: string, postProcess?: ProcessConfig): Promise<string> {
    console.log(`selectAttribute 属性值选择器 sel：${selector}，attribute：${attribute}`)
    const element = selectFirst(context, selector);
    let value = element ? element.attr(attribute || '') : '';

    if (postProcess) {
      value = await ScriptProcessor.execute<string>(value, postProcess);
    }

    return value;
  }

}
