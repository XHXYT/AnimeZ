// HomepageExtractor.ts
// 首页 HTML 解析与字段提取（纯函数：无网络、无实例状态、不依赖 UI）
// 供 taskpool 子线程调用：主线程仅发起网络请求并传入 HTML 字符串与解析配置，
// parse + select + 字段提取在本模块内完成后回传纯数据（HtmlTag 树不出本模块）
import { select, selectFirst, selectTextContent, parse } from '../utils/thirdpart/htmlsoup';
import { AnyNode } from '../utils/thirdpart/htmlsoup/parse';
import { VideoConfig, CategoryConfig, CategoryCardConfig, ProcessConfig } from './DataSourceConfig';
import { ScriptProcessor } from './ScriptProcessor';
import VideoInfo from '../entity/VideoInfo';
import { DramaList } from '../entity/HomepageData';
import HomepageData from '../entity/HomepageData';

type SelectorValue = string | { selector: string; postProcess?: ProcessConfig };
type ExtendedSelectorConfig = Record<string, SelectorValue>;

/**
 * 提取简单值（selector@attr 取属性，否则取文本），同 GenericDataSource.extractSimpleValue
 */
function extractSimpleValueFromNode(element: AnyNode, selector: string): string {
  if (selector.includes('@')) {
    const parts = selector.split('@');
    const el = selectFirst(element, parts[0]);
    return el ? el.attr(parts[1]) : '';
  }
  return selectTextContent(element, selector) || '';
}

/**
 * 提取单个视频信息（同 GenericDataSource.extractVideoInfo，参数显式传入替代 this）
 */
async function extractVideoInfoFromNode(element: AnyNode, selectors: ExtendedSelectorConfig,
  baseUrl: string, sourceKey: string, urlNeedBaseUrl: boolean, enabledHttps: boolean): Promise<VideoInfo> {
  const info: VideoInfo = {
    sourceKey: sourceKey,
    url: '',
    imgUrl: '',
    title: '',
    episode: ''
  };

  const entries = Object.entries(selectors);
  for (const entry of entries) {
    const key = entry[0];
    const config = entry[1];
    let value: string;

    if (typeof config === 'string') {
      value = extractSimpleValueFromNode(element, config);
    } else if (config && config.selector) {
      value = extractSimpleValueFromNode(element, config.selector);
      if (config.postProcess) {
        value = await ScriptProcessor.execute<string>(value, config.postProcess);
      }
    } else {
      continue;
    }

    if (key === 'url' && value && !value.startsWith('http') && urlNeedBaseUrl) {
      value = baseUrl + value;
    }
    if (key === 'imgUrl' && value && urlNeedBaseUrl
      && value.startsWith('/') && !value.startsWith('//')) {
      value = baseUrl + value;
    }
    if (value.startsWith('http://') && enabledHttps) {
      value = 'https://' + value.substring(7);
    }

    (info as any)[key] = value;
  }

  return info;
}

/**
 * 从文档中提取 Banner 列表（同 GenericDataSource.extractBannerList）
 */
async function extractBannerListFromDoc(doc: AnyNode, config: VideoConfig,
  baseUrl: string, sourceKey: string): Promise<VideoInfo[]> {
  if (!config) {
    return [];
  }
  const list = select(doc, config.listSelector);
  const banners: VideoInfo[] = [];
  for (const li of list) {
    banners.push(await extractVideoInfoFromNode(li, config.itemSelectors as ExtendedSelectorConfig,
      baseUrl, sourceKey, config.urlNeedBaseUrl, config.enabledHttps));
  }
  return banners;
}

/**
 * 处理单个分类项（同 GenericDataSource.processCategoryItem，剔除调试日志）
 */
async function processCategoryNode(title: AnyNode, list: AnyNode, categoriesConfig: CategoryConfig,
  baseUrl: string, sourceKey: string): Promise<DramaList> {
  const lis = select(list, categoriesConfig.videos.listSelector);
  const videos: VideoInfo[] = [];
  for (const li of lis) {
    videos.push(await extractVideoInfoFromNode(li, categoriesConfig.videos.itemSelectors as ExtendedSelectorConfig,
      baseUrl, sourceKey, categoriesConfig.videos.urlNeedBaseUrl, categoriesConfig.videos.enabledHttps));
  }

  // 解析更多链接（moreUrl 为 selector@attr 形式）
  const moreUrlParts = categoriesConfig.moreUrl.split('@');
  const moreEl = selectFirst(title, moreUrlParts[0]);
  let rawMoreUrl = moreEl ? moreEl.attr(moreUrlParts[1] || '') : '';
  if (rawMoreUrl.startsWith('http://')) {
    rawMoreUrl = 'https://' + rawMoreUrl.substring(7);
  }

  // 提取原始项标题并过滤"更多"等杂质
  const rawTitle = selectTextContent(title, categoriesConfig.title) || '';
  const cleanTitle = rawTitle
    .replace(/^\s*(更多|More|查看更多|View All|全部)\s*[»→...->>>>]*\s*|\s*(更多|More|查看更多|View All|全部)\s*[»→...->>>>]*\s*$/g, '')
    .trim();

  return {
    title: cleanTitle,
    moreUrl: categoriesConfig.moreUrlNeedBaseUrl ? (baseUrl + rawMoreUrl) : rawMoreUrl,
    videoList: videos
  };
}

/**
 * 同页模式：从首页文档提取分类列表（同 GenericDataSource.extractCategoryList）
 */
async function extractCategoryListFromDoc(doc: AnyNode, categoriesConfig: CategoryConfig,
  baseUrl: string, sourceKey: string): Promise<DramaList[]> {
  if (!categoriesConfig) {
    return [];
  }
  const titles = select(doc, categoriesConfig.titles);
  const videoLists = select(doc, categoriesConfig.videoLists);
  const count = Math.min(titles.length, videoLists.length);

  const categories: DramaList[] = [];
  for (let i = 0; i < count; i++) {
    categories.push(await processCategoryNode(titles[i], videoLists[i], categoriesConfig, baseUrl, sourceKey));
  }
  return categories;
}

/**
 * 同页模式入口：parse 整个首页 HTML 并提取 banner + 分类
 */
export async function parseHomepageDocument(html: string, baseUrl: string, sourceKey: string,
  banner: VideoConfig, category: CategoryConfig): Promise<HomepageData> {
  const doc = parse(html);
  const [bannerList, categoryList] = await Promise.all([
    extractBannerListFromDoc(doc, banner, baseUrl, sourceKey),
    extractCategoryListFromDoc(doc, category, baseUrl, sourceKey)
  ]);
  return { bannerList, categoryList };
}

/**
 * 卡片模式：从首页 HTML 中仅提取 banner
 */
export async function extractBannerFromHtml(html: string, baseUrl: string, sourceKey: string,
  banner: VideoConfig): Promise<VideoInfo[]> {
  if (!banner) {
    return [];
  }
  const doc = parse(html);
  return await extractBannerListFromDoc(doc, banner, baseUrl, sourceKey);
}

/**
 * 卡片模式：解析单个卡片页面并提取条目（maxItems 截断，同 processHtmlCategoryCard 解析部分）
 */
export async function extractCardItemsFromHtml(html: string, baseUrl: string, sourceKey: string,
  card: CategoryCardConfig): Promise<VideoInfo[]> {
  const listSelector = card.listSelector || card.listPath || '';
  let items = select(parse(html), listSelector);
  if (card.maxItems && card.maxItems > 0 && items.length > card.maxItems) {
    items = items.slice(0, card.maxItems);
  }
  const videos: VideoInfo[] = [];
  for (const li of items) {
    videos.push(await extractVideoInfoFromNode(li, card.itemSelectors as ExtendedSelectorConfig,
      baseUrl, sourceKey, card.urlNeedBaseUrl ?? true, card.enabledHttps ?? true));
  }
  return videos;
}
