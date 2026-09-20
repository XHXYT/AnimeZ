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
} from '../thirdpart/htmlsoup';
import { AnyNode, HtmlTag } from '../thirdpart/htmlsoup/parse';
import {
  CategoryConfig, EpisodeConfig, ParserConfig, RecommendConfig,
  SelectorConfig, VideoConfig, ProcessConfig } from './DataSourceConfig';
import { sortEpisodesByNumber } from '../utils/SortUtils';
import { ScriptProcessor } from './ScriptProcessor';

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

  constructor(config: any) {
    this.key = config.key;
    this.name = config.name || config.key;
    this.baseUrl = config.baseUrl;
    this.enabled = config.enabled !== false; // 默认为true
    this.priority = config.priority || 0;
    this.parserConfig = config.parserConfig;

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

  async search(keyword: string, page: number): Promise<VideoInfo[]> {
    const config = this.parserConfig.search;
    const url = this.baseUrl + config.videos.urlTemplate
      .replace('{keyword}', encodeURIComponent(keyword))
      .replace('{page}', page.toString());

    const videos: VideoInfo[] = [];
    try {
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
    console.log(`获取主页配置：${JSON.stringify(config)}`)
    try {
      const doc = await this.parseHtml(this.baseUrl)
      console.log(`网页doc已获取`)

      // 并行处理banner和category
      const [bannerList, categoryList] = await Promise.all([
        this.extractBannerList(doc, config.banner),
        this.extractCategoryList(doc, config.category)
      ]);

      return { bannerList, categoryList };
    } catch (e) {
      Logger.e('fail', `获取主页数据`, e);
      throw e;
    }
  }

  async getVideoList(moreUrl: string, page: number): Promise<VideoInfo[]> {
    const url = `${moreUrl}${page <= 0 ? '' : page}`;
    Logger.e('tips', "CategoryPage #getVideoList parseHtml url = " + url);

    try {
      const doc = await this.parseHtml(url);
      const drama = selectFirst(doc, this.parserConfig.homepage.category.videos.listSelector);

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
              episodes: sortEpisodesByNumber(episodes.episodes, order)
            }
          });
        })
      ]);

      Logger.e('tips', 'getVideoDetailInfo title=' + title);

      const info: VideoDetailInfo = {
        sourceKey: this.key,
        title: title,
        url: url,
        desc: desc,
        coverUrl: coverUrl,
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

      if (config.pattern === 'regex' && config.pattern) {
        // 使用正则表达式方式提取URL
        const htmlString = await HttpUtils.getString(link);
        const match = htmlString.match(new RegExp(config.pattern));

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
