// GenericDataSource.ts
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
  SelectorConfig, VideoConfig } from './DataSourceConfig';
import { sortEpisodesByNumber } from '../utils/SortUtils';


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

      list.forEach((li) => {
        videos.push(this.extractVideoInfo(li, config.videos.itemSelectors, config.videos.urlNeedBaseUrl, config.videos.enabledHttps));
      });

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
      const bannerList = this.extractBannerList(doc, config.banner);
      const categoryList = this.extractCategoryList(doc, config.category);

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

      return this.parseVideoList(drama, this.parserConfig.homepage.category.videos);
    } catch (e) {
      Logger.e('fail', `获取视频列表`, e);
      throw e
    }
  }

  private async parseVideoList(drama: HtmlTag, config: VideoConfig): Promise<VideoInfo[]> {
    const elements = select(drama, config.listSelector);
    Logger.e('tips', 'parseHtml elements=' + elements.length);

    const videoList: VideoInfo[] = [];
    elements.forEach((li) => {
      Logger.e('tips', "parseHtml el=" + li);
      videoList.push(this.extractVideoInfo(li, config.itemSelectors, config.urlNeedBaseUrl, config.enabledHttps));
    });

    return videoList;
  }

  async getVideoDetailInfo(url: string, order: "asc" | "desc" = 'asc'): Promise<VideoDetailInfo> {
    try {
      console.log(`GenericDataSource.getVideoDetailInfo 等待加载的链接：${url}`)
      const doc = await this.parseHtml(url);
      const config = this.parserConfig.detail;

      const title = this.selectText(doc, config.titleSelector);
      Logger.e('tips', 'getVideoDetailInfo title=' + title);

      const recommends = this.extractRecommends(doc, config.recommends);
      const episodesList = this.extractEpisodes(doc, config.episodes).map(episodes => {
        return {
          title: episodes.title,
          episodes: sortEpisodesByNumber(episodes.episodes, order)
        }
      });
      const [sel, attr] = config.coverSelector.split('@')
      const info: VideoDetailInfo = {
        sourceKey: this.key,
        title: title,
        url: url,
        desc: this.selectText(doc, config.descSelector).trim(),
        coverUrl: this.selectAttribute(doc, sel, attr),
        category: config.categorySelector ? this.selectText(doc, config.categorySelector) : '',
        director: config.directorSelector ? this.selectText(doc, config.directorSelector) : '',
        updateTime: config.updateTimeSelector ? this.selectText(doc, config.updateTimeSelector) : '',
        protagonist: config.protagonistSelector ? this.selectText(doc, config.protagonistSelector) : '',
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
          let url = match[1];

          // 应用后处理
          if (config.postProcess) {
            if (config.postProcess.includes("substringBetween")) {
              const [start, end] = config.postProcess
                .replace("substringBetween('", "")
                .replace("')", "")
                .split("', '");

              const startIndex = url.indexOf(start) + start.length;
              const endIndex = url.indexOf(end, startIndex);
              url = url.substring(startIndex, endIndex);
            }

            if (config.postProcess.includes("replaceAll")) {
              const [search, replace] = config.postProcess
                .replace("replaceAll('", "")
                .replace("')", "")
                .split("', '");

              url = url.replace(new RegExp(search, 'g'), replace);
            }
          }
        }
      } else
        if (config.urlSelector) {
        // 使用选择器方式提取URL
        const doc = await HttpUtils.getHtml(link);
        url = this.selectAttribute(doc, config.urlSelector);
        Logger.e('tips', `parseVideoUrl extracted attribute value url = ${url}`);

        if (url == '') {
          Logger.e('tips', `parseVideoUrl 解析失败，输入url为空`)
          throw ('parseVideoUrl 解析失败，输入url为空')
        }

        if (url && config.postProcess) {
          // 应用后处理
          if (config.postProcess.includes("substringBetween")) {
            const [start, end] = config.postProcess
              .replace("substringBetween('", "")
              .replace("')", "")
              .split("', '");

            const startIndex = url.indexOf(start) + start.length;
            const endIndex = url.indexOf(end, startIndex);
            url = url.substring(startIndex, endIndex);
          }

          if (config.postProcess.includes("replaceAll")) {
            const [search, replace] = config.postProcess
              .replace("replaceAll('", "")
              .replace("')", "")
              .split("', '");

            url = url.replace(new RegExp(search, 'g'), replace);
          }
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
   * 提取视频信息
   */
  private extractVideoInfo(element: HtmlTag, selectors: SelectorConfig, urlNeedBaseUrl: boolean, enabledHttps: boolean = true): VideoInfo {
    const info: VideoInfo = {
      sourceKey: this.key,
      url: '',
      imgUrl: '',
      title: '',
      episode: ''
    };

    // 遍历选择器配置
    for (const [key, selector] of Object.entries(selectors)) {
      if (selector.includes('@')) {
        // 处理带属性提取的选择器（如 "img@src"）
        const value = this.selectAttribute(element, selector);
        info[key as keyof VideoInfo] = value as any;
      } else {
        // 处理纯文本选择器（如 "h1"）
        const value = this.selectText(element, selector);
        info[key as keyof VideoInfo] = value as any;
      }
      // 片源URL自动补全
      if (key === 'url' && info[key] && !info[key]?.startsWith('http') && urlNeedBaseUrl) {
        info[key] = this.baseUrl + info[key];
      }
      console.log(`extractVideoInfo 是否使用https ${enabledHttps}`)
      // 把http替换成https
      if (info[key].startsWith('http://') && enabledHttps) {
        info[key] =  'https://' + info[key].substring(7);
      }
      console.log(`extractVideoInfo 提取 ${key} 信息：${info[key]}`)
    }

    return info;
  }

  private extractBannerList(doc: AnyNode, config: VideoConfig): VideoInfo[] {
    if (!config) return [];

    const bannerList: VideoInfo[] = [];
    const list = select(doc, config.listSelector);
    console.log(`解析到的BannerList数目：${list.length}`)
    list.forEach((li) => {
      bannerList.push(this.extractVideoInfo(li, config.itemSelectors, config.urlNeedBaseUrl, config.enabledHttps));
    });

    return bannerList;
  }

  private extractCategoryList(doc: AnyNode, categoriesConfig: CategoryConfig): DramaList[] {
    if (!categoriesConfig) return [];

    const categoryList: DramaList[] = [];
    const titles = select(doc, categoriesConfig.titles);
    const videoLists = select(doc, categoriesConfig.videoLists);
    const count = Math.min(titles.length, videoLists.length);
    console.log(`GenericDataSource.extractCategoryList 解析到的标题数：${titles.length}, 番剧列表数：${videoLists.length}, 最后取值：${count}`)
    for (let i = 0; i < count; i++) {
      const title = titles[i];
      const list = videoLists[i];
      const videos: VideoInfo[] = [];

      const lis = select(list, categoriesConfig.videos.listSelector);
      console.log(`解析到第${i}项CategoryList番剧数目：${lis.length}`)
      // 推送目录内的片源列表
      lis.forEach((li) => {
        videos.push(this.extractVideoInfo(li, categoriesConfig.videos.itemSelectors, categoriesConfig.videos.urlNeedBaseUrl, categoriesConfig.videos.enabledHttps));
      });

      // 解析更多链接
      let rawMoreUrl = this.selectAttribute(title, categoriesConfig.moreUrl);
      if (rawMoreUrl.startsWith('http://')) {
        rawMoreUrl =  'https://' + rawMoreUrl.substring(7);
      }
      // 提取原始项标题
      const rawTitle = this.selectText(title, categoriesConfig.title);
      console.log(`GenericDataSource.extractCategoryList 原始项标题: ${rawTitle}`)
      // 使用更通用的正则表达式，同时处理开头和结尾的情况, 过滤掉“更多”等杂质
      const cleanTitle = rawTitle.replace(/^\s*(更多|More|查看更多|View All|全部)\s*[»→...->>>>]*\s*|\s*(更多|More|查看更多|View All|全部)\s*[»→...->>>>]*\s*$/g, '').trim();
      console.log(`GenericDataSource.extractCategoryList 过滤后项标题: ${cleanTitle}`)
      // 推送目录列表
      categoryList.push({
        title: cleanTitle,
        moreUrl: categoriesConfig.moreUrlNeedBaseUrl ? (this.baseUrl + rawMoreUrl) : rawMoreUrl,
        videoList: videos
      });
    }

    return categoryList;
  }

  private extractEpisodes(doc: AnyNode, config: EpisodeConfig): EpisodeList[] {
    const episodes: EpisodeList[] = [];

    if (config.routeTitlesSelector && config.routeContainersSelector) {
      // 多路线情况
      const routeTitles = select(doc, config.routeTitlesSelector);
      const routeContainers = select(doc, config.routeContainersSelector);

      for (let i = 0; i < Math.min(routeTitles.length, routeContainers.length); i++) {
        const title = textContent(routeTitles[i]);
        const container = routeContainers[i];

        const items = select(container, config.itemSelector);
        const episodeInfos: EpisodeInfo[] = items.map(item => {
          const url = this.selectAttribute(item, config.itemSelectors.url);
          const title = this.selectText(item, config.itemSelectors.title);
          console.log(`extractEpisodes 多路线 视频详情链接是否拼接baseUrl：${url.includes('http') } 提取的url：${url} link：${url.includes('http') ? url : (this.baseUrl + url)}`)
          return {
            link: url.includes('http') ? url : (this.baseUrl + url),
            title,
            desc: title
          };
        });

        episodes.push({ title, episodes: episodeInfos });
      }
    } else if (config.containerSelector) {
      // 单路线情况
      const container = selectFirst(doc, config.containerSelector);
      if (container) {
        const items = select(container, config.itemSelector);
        const episodeInfos: EpisodeInfo[] = items.map(item => {
          const [sel, attr] = config.itemSelectors.url.split('@')
          const url = this.selectAttribute(item, sel, attr);
          const title = this.selectText(item, config.itemSelectors.title);
          console.log(`extractEpisodes 单路线 视频详情链接是否拼接baseUrl：${url.includes('http') } 提取的url：${url} link：${url.includes('http') ? url : (this.baseUrl + url)}`)
          return {
            link: url.includes('http') ? url : (this.baseUrl + url),
            title,
            desc: title
          };
        });

        episodes.push({ title: "剧集列表", episodes: episodeInfos });
      }
    }

    return episodes;
  }

  private extractRecommends(doc: AnyNode, config: RecommendConfig): VideoInfo[] {
    const items = select(doc, config.listSelector);
    return items.map(item => this.extractVideoInfo(item, config.itemSelectors, config.urlNeedBaseUrl, config.enabledHttps));
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

  // 选择文本
  private selectText(context: AnyNode, selector: string): string {
    const element = selectTextContent(context, selector);
    return element ? element : '';
  }

  // 选择属性
  private selectAttribute(context: AnyNode, selector: string, attribute?: string): string {
    const [sel, attr] = selector.split('@');
    console.log(`selectAttribute 属性值选择器 sel：${sel}，attribute：${attribute || attr}`)
    const element = selectFirst(context, sel);
    return element ? element.attr(attribute || attr) : '';
  }

}