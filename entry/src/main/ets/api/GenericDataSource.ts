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
  selectFirst,
  selectTextContent,
  textContent,
  parse,
} from '../utils/thirdpart/htmlsoup';
import { AnyNode, HtmlTag } from '../utils/thirdpart/htmlsoup/parse';
import {
  CategoryConfig, EpisodeConfig, ParserConfig, RecommendConfig,
  SelectorConfig, VideoConfig, ProcessConfig, CategoryCardConfig, LoginConfig, SearchCaptchaConfig } from './DataSourceConfig';
import { ScriptProcessor } from './ScriptProcessor';
import AuthStore from '../utils/AuthStore';
import HttpSession from '../utils/HttpSession';
import { CaptchaBridge } from './CaptchaBridge';
import { getConcurrentTaskFns } from './TaskRegistry';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';

// 扩展SelectorConfig类型以支持更灵活的配置
type SelectorValue = string | { selector: string; postProcess?: ProcessConfig };
type ExtendedSelectorConfig = Record<string, SelectorValue>;

/**
 * 将星期标题文本解析为 1-7（周一=1）：支持"星期三/周三/Wednesday/Wed/水曜日"等写法；
 * 无法识别返回 0（该区块不参与星期匹配）。
 */
function parseWeekdayText(text: string): number {
  const t = text.trim();
  if (t === '') {
    return 0;
  }
  const cnMatch = t.match(/(?:星期|周)\s*([一二三四五六日天])/);
  if (cnMatch) {
    const c = cnMatch[1];
    if (c === '日' || c === '天') {
      return 7;
    }
    return '一二三四五六'.indexOf(c) + 1;
  }
  // 日语曜日（如"昨天 (火曜日)"）：月=1 火=2 水=3 木=4 金=5 土=6 日=7
  const jpMatch = t.match(/([月火水木金土日])曜/);
  if (jpMatch) {
    return '月火水木金土日'.indexOf(jpMatch[1]) + 1;
  }
  const enNames: string[] = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
  const lower = t.toLowerCase();
  for (let i = 0; i < enNames.length; i++) {
    if (lower.includes(enNames[i])) {
      return i + 1;
    }
  }
  return 0;
}

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
  // 验证码会话：搜索验证码流程共享 Cookie（首次搜索种下会话，验证通过后同会话重放）
  private captchaSession: HttpSession = new HttpSession();

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
    const rawUrl = config.videos.urlTemplate
      .replace('{keyword}', encodeURIComponent(keyword))
      .replace('{page}', page.toString());
    // POST 型端点（如 Connect-RPC）地址可能为绝对地址（独立接口域名），不再强拼 baseUrl
    const url = rawUrl.startsWith('http') ? rawUrl : this.baseUrl + rawUrl;

    const videos: VideoInfo[] = [];
    try {
      if (this.isJsonMode()) {
        const body = config.videos.body
          ? this.renderJsonBodyTemplate(config.videos.body, { keyword: keyword, page: page })
          : undefined;
        const resp = await this.requestJson(url, true, config.videos.method, body);
        return this.parseJsonVideoList(resp, config.videos.listSelector,
          config.videos.itemSelectors as ExtendedSelectorConfig,
          config.videos.urlNeedBaseUrl, config.videos.enabledHttps);
      }

      let doc: AnyNode;
      if (config.captcha) {
        doc = await this.searchWithCaptcha(url, config.captcha);
      } else {
        doc = await this.parseHtml(url);
      }
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

  /**
   * 验证码感知搜索：检测到验证码页时，经 UI 桥引导用户输入验证码，
   * 提交校验成功后用同一会话重放搜索；整个流程复用实例级 captchaSession 保持 Cookie
   */
  private async searchWithCaptcha(url: string, captcha: SearchCaptchaConfig): Promise<AnyNode> {
    const session = this.captchaSession;
    const doc = parse(await session.getString(url));
    if (select(doc, captcha.detectSelector).length === 0) {
      return doc;
    }
    Logger.d('tips', `searchWithCaptcha ${this.name} 命中验证码页，引导用户输入`);
    const maxAttempts = 3;
    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      const imageUrl = this.resolveCaptchaImageUrl(doc, captcha);
      const pixelMap = await session.getImage(this.cacheBust(imageUrl, captcha.imageCacheBustParam));
      const code = await CaptchaBridge.prompt({
        sourceName: this.name,
        pixelMap: pixelMap,
        refresh: async (): Promise<image.PixelMap> => {
          return await session.getImage(this.cacheBust(imageUrl, captcha.imageCacheBustParam));
        }
      });
      const verifyTemplate = captcha.verifyUrlTemplate.includes('http')
        ? captcha.verifyUrlTemplate
        : this.baseUrl + captcha.verifyUrlTemplate;
      const verifyResp = await session.postString(verifyTemplate.replace('{code}', encodeURIComponent(code)));
      if (captcha.successContains && !verifyResp.includes(captcha.successContains)) {
        Logger.d('tips', `searchWithCaptcha 校验未通过：${verifyResp}`);
        continue;
      }
      const retryDoc = parse(await session.getString(url));
      if (select(retryDoc, captcha.detectSelector).length === 0) {
        return retryDoc;
      }
      Logger.d('tips', `searchWithCaptcha 重放搜索仍为验证码页（第${attempt + 1}次）`);
    }
    throw new Error('验证码校验失败，请稍后重试');
  }

  /**
   * 解析验证码图片地址（imageUrlSelector 为 selector@attr 形式；
   * 选择器部分留空（含仅填 @属性）时回退为 detectSelector + 该属性（默认 src），
   * 仅当判定元素本身是 img 时生效）
   */
  private resolveCaptchaImageUrl(doc: AnyNode, captcha: SearchCaptchaConfig): string {
    // 固定图片地址模板兜底（相对路径拼 baseUrl）：用于验证码图片由站点 JS 注入、响应里没有 img 元素的站点
    const resolveTemplate = (): string => {
      const tpl = captcha.imageUrlTemplate || '';
      if (!tpl) {
        return '';
      }
      return tpl.includes('http') ? tpl : this.baseUrl + tpl;
    };
    let imageSelector = captcha.imageUrlSelector || '';
    let parts = imageSelector.split('@');
    if (parts[0].trim() === '') {
      const detected = selectFirst(doc, captcha.detectSelector);
      if (detected && detected.type.toLowerCase() === 'img') {
        const attr = parts.length > 1 && parts[1].trim() !== '' ? parts[1].trim() : 'src';
        imageSelector = captcha.detectSelector + '@' + attr;
        parts = imageSelector.split('@');
        Logger.d('tips', `searchWithCaptcha imageUrlSelector 未配置，回退为 ${imageSelector}`);
      }
    }
    if (parts.length < 2 || parts[0].trim() === '') {
      const tpl = resolveTemplate();
      if (tpl) {
        return tpl;
      }
      throw new Error('captcha.imageUrlSelector 需为 selector@attr 形式');
    }
    const el = selectFirst(doc, parts[0]);
    const imageUrl = el ? el.attr(parts[1]) : '';
    if (!imageUrl) {
      const tpl = resolveTemplate();
      if (tpl) {
        return tpl;
      }
      throw new Error('未找到验证码图片');
    }
    if (captcha.imageNeedBaseUrl !== false && !imageUrl.includes('http')) {
      return this.baseUrl + imageUrl;
    }
    return imageUrl;
  }

  /**
   * 为 URL 附加随机参数避免缓存（验证码图片每次获取都需最新）
   */
  private cacheBust(url: string, param?: string): string {
    if (!param) {
      return url;
    }
    const sep = url.includes('?') ? '&' : '?';
    return `${url}${sep}${param}=${Math.random()}`;
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

      // HTML 模式：网络请求留在主线程（异步不阻塞 UI），
      // parse + 字段提取整体移入 taskpool 子线程，避免大页面解析卡住主线程
      const cards = config.category?.cards;
      const homepageHtml = await HttpUtils.getString(this.baseUrl);
      // banner.urlTemplate 配置时轮播图独立请求该页面（HTML=轮播页地址，如复用剧场版/电影列表页），
      // 未配置时沿用首页文档（旧源 urlTemplate 为 '' 或 '/'，'/' 仍取首页，行为不变）
      const bannerTpl = config.banner ? config.banner.urlTemplate : '';
      const bannerHtml = bannerTpl
        ? await HttpUtils.getString(bannerTpl.startsWith('http') ? bannerTpl : this.baseUrl + bannerTpl)
        : homepageHtml;
      if (cards && cards.length > 0) {
        // 卡片模式：每个卡片独立请求自己的页面，解析在子线程
        const [bannerList, categoryList] = await Promise.all([
          getConcurrentTaskFns().homepageBannerParseInTask(bannerHtml, this.baseUrl, this.key, config.banner),
          Promise.all(cards.map(card => this.processHtmlCategoryCard(card)))
        ]);
        return { bannerList, categoryList };
      }

      if (bannerHtml !== homepageHtml) {
        // 同页模式 + 轮播图独立页面：分类照常解析首页文档（banner 结果丢弃），轮播图单独解析
        const [bannerList, homepageData] = await Promise.all([
          getConcurrentTaskFns().homepageBannerParseInTask(bannerHtml, this.baseUrl, this.key, config.banner),
          getConcurrentTaskFns().parseHomepageInTask(homepageHtml, this.baseUrl, this.key, config.banner, config.category)
        ]);
        return { bannerList, categoryList: homepageData.categoryList };
      }

      // 同页模式：banner 与分类在同一首页文档中
      return await getConcurrentTaskFns().parseHomepageInTask(homepageHtml, this.baseUrl, this.key, config.banner, config.category);
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
        const moreBody = videosConfig.body
          ? this.renderJsonBodyTemplate(videosConfig.body, { page: page > 0 ? page : 1 })
          : undefined;
        const resp = await this.requestJson(url, true, videosConfig.method, moreBody);
        return this.parseJsonVideoList(resp, videosConfig.listSelector,
          videosConfig.itemSelectors as ExtendedSelectorConfig,
          videosConfig.urlNeedBaseUrl, videosConfig.enabledHttps);
      } catch (e) {
        Logger.e('fail', `获取视频列表(JSON)`, e);
        throw e
      }
    }

    let pageUrl: string;
    if (moreUrl.includes('{page}')) {
      pageUrl = moreUrl.replace('{page}', (page > 0 ? page : 1).toString());
    } else {
      pageUrl = `${moreUrl}${page <= 0 ? '' : page}`;
    }
    Logger.e('tips', "CategoryPage #getVideoList parseHtml url = " + pageUrl);

    try {
      // 网络请求留在主线程（异步不阻塞 UI），parse + 字段提取移入 taskpool 子线程
      const html = await HttpUtils.getString(pageUrl);
      return await getConcurrentTaskFns().videoListParseInTask(html, this.baseUrl, this.key, this.parserConfig.homepage.category.videos);
    } catch (e) {
      Logger.e('fail', `获取视频列表`, e);
      throw e
    }
  }

  /**
   * 是否配置了可用的周表规则（未配置则应用隐藏周表入口）
   * 单列表模式（urlTemplate+listSelector）/ 首页多区块模式（额外需要星期区块+标题选择器）；
   * JSON 模式 listSelector 可省略（空=响应根数组）。
   */
  hasScheduleConfig(): boolean {
    const schedule = this.parserConfig?.schedule;
    if (!schedule || !schedule.urlTemplate) {
      return false
    }
    if (this.isJsonMode()) {
      return true
    }
    if (schedule.weekdayBlocksSelector) {
      return !!(schedule.weekdayTitleSelector && schedule.listSelector)
    }
    return !!schedule.listSelector
  }

  /**
   * 获取周表数据（weekday: 1-7，周一=1）
   */
  async getSchedule(weekday: number): Promise<VideoInfo[]> {
    const schedule = this.parserConfig.schedule;
    if (!schedule || !schedule.urlTemplate) {
      throw new Error('当前源未配置周表规则');
    }
    if (!this.isJsonMode() && !schedule.listSelector) {
      throw new Error('当前源未配置周表规则');
    }
    // {weekday}=1-7（周一=1）；{weekday0}=0-6（周一=0，适配 0 起始的星期字段/接口）
    const weekdayUrl = schedule.urlTemplate
      .replace('{weekday0}', (weekday - 1).toString())
      .replace('{weekday}', weekday.toString());
    const url = weekdayUrl.startsWith('http') ? weekdayUrl : this.baseUrl + weekdayUrl;
    try {
      if (this.isJsonMode()) {
        const scheduleBody = schedule.body
          ? this.renderJsonBodyTemplate(schedule.body, { weekday: weekday, weekday0: weekday - 1 })
          : undefined;
        const resp = await this.requestJson(url, true, schedule.method, scheduleBody);
        return this.parseJsonVideoList(resp, schedule.listSelector,
          schedule.itemSelectors as ExtendedSelectorConfig,
          schedule.urlNeedBaseUrl, schedule.enabledHttps);
      }
      // HTML 模式：请求周表页面，按 CSS 选择器提取条目（同搜索列表）
      const doc = await this.parseHtml(url);
      let list: HtmlTag[];
      if (schedule.weekdayBlocksSelector && schedule.weekdayTitleSelector) {
        // 首页多区块形态：按区块内星期标题定位当天区块，再在区块内提取条目
        const blocks = select(doc, schedule.weekdayBlocksSelector);
        list = [];
        for (const block of blocks) {
          const blockWeekday = parseWeekdayText(selectTextContent(block, schedule.weekdayTitleSelector));
          if (blockWeekday === weekday) {
            list = select(block, schedule.listSelector);
            break;
          }
        }
        if (list.length === 0) {
          // 页面无对应星期区块：视为当天无更新
          return [];
        }
      } else {
        list = select(doc, schedule.listSelector);
      }
      const videoPromises = list.map(async (li) => {
        return await this.extractVideoInfo(li, schedule.itemSelectors as ExtendedSelectorConfig, schedule.urlNeedBaseUrl, schedule.enabledHttps);
      });
      return await Promise.all(videoPromises);
    } catch (e) {
      Logger.e('fail', `获取周表数据(weekday=${weekday})`, e);
      throw e;
    }
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
        this.extractDetailTextField(doc, config.titleSelector),
        this.extractDetailTextField(doc, config.descSelector).then(t => t.trim()),
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

      // 详情扩展字段
      if (config.extra) {
        await this.applyDetailExtra(info, config.extra,
          (selector: string) => this.extractSimpleValue(doc, selector));
      }

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
        const urlBody = config.body ? this.renderJsonBodyTemplate(config.body, { link: link }) : undefined;
        const resp = await this.requestJson(link, true, config.method, urlBody);
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

    if (postProcess.includes("base64Decode")) {
      processedUrl = this.base64Decode(processedUrl);
    }

    if (postProcess.includes("decodeUri")) {
      try {
        processedUrl = decodeURIComponent(processedUrl);
      } catch (e) {
        Logger.e('fail', 'decodeUri 失败', e);
      }
    }

    // JSON 字符串解码：处理播放地址中的 \/ 与 \uXXXX 转义（如 MacCMS player_aaaa 的中文路径）
    if (postProcess.includes("jsonDecode")) {
      try {
        processedUrl = JSON.parse('"' + processedUrl + '"') as string;
      } catch (e) {
        Logger.e('fail', 'jsonDecode 失败', e);
      }
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
   * Base64 解码（UTF-8），用于 MacCMS player_aaaa encrypt=2 等播放地址解密
   */
  private base64Decode(input: string): string {
    try {
      const helper = new util.Base64Helper();
      const bytes = helper.decodeSync(input);
      const decoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(bytes);
    } catch (e) {
      Logger.e('fail', 'base64Decode 失败', e);
      return input;
    }
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
   * 应用详情扩展字段（播放量/年份/月份/导演/演员/标签）
   * HTML 模式传 CSS 提取函数，JSON 模式传模板渲染函数
   */
  private async applyDetailExtra(info: VideoDetailInfo, extra: SelectorConfig,
    extract: (selector: string) => Promise<string>): Promise<void> {
    const entries = Object.entries(extra);
    for (const entry of entries) {
      const key = entry[0];
      const config = entry[1];
      if (config === undefined || config === null) {
        continue;
      }
      let value = '';
      if (typeof config === 'string') {
        value = await extract(config);
      } else if (config.selector) {
        value = await extract(config.selector);
        if (config.postProcess && value) {
          value = await ScriptProcessor.execute<string>(value, config.postProcess);
        }
      }
      if (value) {
        this.setDetailExtra(info, key, value);
      }
    }
  }

  private setDetailExtra(info: VideoDetailInfo, key: string, value: string): void {
    if (key === 'playCount') { info.playCount = value; return; }
    if (key === 'year') { info.year = value; return; }
    if (key === 'month') { info.month = value; return; }
    if (key === 'director') { info.director = value; return; }
    if (key === 'actors') { info.actors = value; return; }
    if (key === 'protagonist') { info.protagonist = value; return; }
    if (key === 'tags') { info.tags = value; return; }
  }

  /**
   * 提取简单值
   */
  private async extractSimpleValue(element: AnyNode, selector: string): Promise<string> {
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
   * HTML 模式：处理单个分类卡片（请求留在主线程，页面解析在 taskpool 子线程）
   * 失败或解析为空时重试一次（站点偶发限流/超时导致卡片空白）
   */
  private async processHtmlCategoryCard(card: CategoryCardConfig): Promise<DramaList> {
    let videoList: VideoInfo[] = [];
    const maxAttempts = 2;
    for (let attempt = 0; attempt < maxAttempts && videoList.length === 0; attempt++) {
      try {
        const pageUrl = card.url.includes('http') ? card.url : this.baseUrl + card.url;
        const html = await HttpUtils.getString(pageUrl);
        videoList = await getConcurrentTaskFns().homepageCardParseInTask(html, this.baseUrl, this.key, card);
      } catch (e) {
        Logger.e('fail', `解析分类卡片(HTML): ${card.title}`, e);
        if (attempt < maxAttempts - 1) {
          await this.sleep(300);
        }
      }
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
    return await HttpUtils.getHtml(this.upgradeSchemeToBaseUrl(url));
  }

  /**
   * 源 baseUrl 为 https 时，把页面内硬编码的同域 http:// 明文链接升级为 https：
   * 部分站点（如 AGE）列表链接写死 http，但其 80 端口已失联，
   * 直接请求会一直等到连接超时；升级为与源同协议可立即正常访问
   */
  private upgradeSchemeToBaseUrl(url: string): string {
    if (!url.startsWith('http://') || !this.baseUrl.startsWith('https://')) {
      return url;
    }
    const urlHost = url.substring('http://'.length).split('/')[0];
    const baseHost = this.baseUrl.substring('https://'.length).split('/')[0];
    if (urlHost === baseHost) {
      return 'https://' + url.substring('http://'.length);
    }
    return url;
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
   * JSON 字符串值转义：请求体模板占位符取值后安全嵌入（引号/反斜杠/控制字符）
   */
  private jsonEscapeValue(value: string): string {
    let escaped = '';
    for (const ch of value) {
      if (ch === '"') {
        escaped += '\\"';
      } else if (ch === '\\') {
        escaped += '\\\\';
      } else if (ch === '\n') {
        escaped += '\\n';
      } else if (ch === '\r') {
        escaped += '\\r';
      } else if (ch === '\t') {
        escaped += '\\t';
      } else if (ch.charCodeAt(0) < 0x20) {
        escaped += '\\u' + ch.charCodeAt(0).toString(16).padStart(4, '0');
      } else {
        escaped += ch;
      }
    }
    return escaped;
  }

  /**
   * 渲染 POST 请求体模板：与 renderTemplate 同构，
   * 但占位符取值做 JSON 字符串转义（而非直接拼接），保证请求体始终为合法 JSON
   */
  private renderJsonBodyTemplate(template: string, context: object | null): string {
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
      return this.jsonEscapeValue(String(value));
    });
  }

  /**
   * 请求 JSON 接口：自动拼接 baseUrl、附加自定义请求头与登录凭证，
   * method 为 POST 时按 body 发送 JSON 请求体（支持 Connect-RPC 等 POST 型接口），
    * 响应 code 非 0 时抛出业务错误（200 视为成功，兼容 code:200 的接口约定）
    */
  private async requestJson(urlOrPath: string, needAuth: boolean = true,
    method?: string, body?: string): Promise<any> {
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
    const isPost = method !== undefined && method.toUpperCase() === 'POST';
    const text = isPost
      ? await HttpUtils.postJson(url, body ?? '', headers)
      : await HttpUtils.getString(url, headers);
    const parsed = JSON.parse(text);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)
      && parsed.code !== undefined && parsed.code !== 0 && parsed.code !== 200) {
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
      const resp = await this.requestJson(url, true, config.method, config.body);
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
    const maxAttempts = 2;
    for (let attempt = 0; attempt < maxAttempts && videoList.length === 0; attempt++) {
      try {
        const resp = await this.requestJson(card.url, true, card.method, card.body);
        videoList = await this.parseJsonVideoList(resp, card.listPath,
          card.itemSelectors as ExtendedSelectorConfig,
          card.urlNeedBaseUrl ?? false, card.enabledHttps ?? true);
      } catch (e) {
        Logger.e('fail', `解析分类卡片(JSON): ${card.title}`, e);
        if (attempt < maxAttempts - 1) {
          await this.sleep(300);
        }
      }
    }
    if (card.maxItems && card.maxItems > 0 && videoList.length > card.maxItems) {
      videoList = videoList.slice(0, card.maxItems);
    }
    return {
      title: card.title,
      moreUrl: card.moreUrl || '',
      videoList: videoList
    };
  }

  /**
   * 简单延时（卡片重试间隔）
   */
  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout((): void => {
        resolve();
      }, ms);
    });
  }

  /**
   * JSON 模式：获取视频详情（url 即详情接口地址；配置 urlTemplate 时以 {link}=条目url 渲染端点地址）
   */
  private async getJsonVideoDetail(url: string): Promise<VideoDetailInfo> {
    const config = this.parserConfig.detail;
    const detailBody = config.body ? this.renderJsonBodyTemplate(config.body, { link: url }) : undefined;
    const requestUrl = config.urlTemplate ? this.renderTemplate(config.urlTemplate, { link: url }) : url;
    const resp = await this.requestJson(requestUrl, true, config.method, detailBody);
    // dataPath 未配置（undefined）时默认 data；显式配置为空字符串表示响应根对象
    const data = this.getJsonPath(resp, config.dataPath === undefined ? 'data' : config.dataPath);
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
      const rawDesc = this.renderTemplate(typeof config.descSelector === 'string' ? config.descSelector : config.descSelector.selector, data);
    const desc = rawDesc
      .replace(/<[^>]*>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .trim();

    const info: VideoDetailInfo = {
      sourceKey: this.key,
      title: this.renderTemplate(typeof config.titleSelector === 'string' ? config.titleSelector : config.titleSelector.selector, data),
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

    // 详情扩展字段
    if (config.extra) {
      await this.applyDetailExtra(info, config.extra,
        (template: string) => Promise.resolve(this.renderTemplate(template, data)));
    }

    return info;
  }

  /**
   * JSON 模式：解析选集路线（如 play_from），逐路线请求选集接口
   */
  private async extractJsonEpisodes(detailData: object): Promise<EpisodeList[]> {
    const config = this.parserConfig.detail.episodes;
    const episodes: EpisodeList[] = [];
    if (!config.jsonRoutesPath && !config.jsonListPath) {
      return episodes;
    }

    // 单路线模式：未配置路线数组时，详情数据自身作为唯一路线（选集内嵌于详情响应）
    let routes: any = null;
    if (config.jsonRoutesPath) {
      routes = this.getJsonPath(detailData, config.jsonRoutesPath);
    } else {
      routes = [detailData];
    }
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
          const sectionsBody = config.body ? this.renderJsonBodyTemplate(config.body, context) : undefined;
          const resp = await this.requestJson(sectionsUrl, true, config.method, sectionsBody);
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
      const recommendBody = config.body ? this.renderJsonBodyTemplate(config.body, detailData) : undefined;
      const resp = await this.requestJson(url, true, config.method, recommendBody);
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
   * 详情字段提取：字符串形式支持 selector@attr（取属性值），对象形式可附加 postProcess
   */
  private async extractDetailTextField(doc: AnyNode,
    selector: string | { selector: string; postProcess?: ProcessConfig }): Promise<string> {
    const sel = typeof selector === 'string' ? selector : selector.selector;
    const postProcess = typeof selector === 'string' ? undefined : selector.postProcess;
    const at = sel.lastIndexOf('@');
    if (at >= 0) {
      return this.selectAttribute(doc, sel.substring(0, at), sel.substring(at + 1), postProcess);
    }
    return this.selectText(doc, sel, postProcess);
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
