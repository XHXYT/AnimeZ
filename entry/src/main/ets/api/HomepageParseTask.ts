import { taskpool } from '@kit.ArkTS';
import { CategoryCardConfig, CategoryConfig, VideoConfig } from './DataSourceConfig';
import HomepageData from '../entity/HomepageData';
import VideoInfo from '../entity/VideoInfo';
import { extractBannerFromHtml, extractCardItemsFromHtml, parseHomepageDocument } from './HomepageExtractor';

/**
 * 首页解析任务（taskpool 子线程）
 * 主线程仅发起网络请求，将 HTML 字符串与解析配置传入子线程；
 * htmlsoup parse + select + 字段提取在子线程完成后回传纯数据，
 * 避免 HtmlTag DOM 树（含 parent 循环引用）跨线程传递。
 */
@Concurrent
async function homepageParseTask(html: string, baseUrl: string, sourceKey: string,
  banner: VideoConfig, category: CategoryConfig): Promise<HomepageData> {
  return await parseHomepageDocument(html, baseUrl, sourceKey, banner, category);
}

/** 卡片模式：首页 banner 提取任务 */
@Concurrent
async function homepageBannerParseTask(html: string, baseUrl: string, sourceKey: string,
  banner: VideoConfig): Promise<VideoInfo[]> {
  return await extractBannerFromHtml(html, baseUrl, sourceKey, banner);
}

/** 卡片模式：单个卡片页面解析任务 */
@Concurrent
async function homepageCardParseTask(html: string, baseUrl: string, sourceKey: string,
  card: CategoryCardConfig): Promise<VideoInfo[]> {
  return await extractCardItemsFromHtml(html, baseUrl, sourceKey, card);
}

/** 同页模式：整页解析（banner + 分类）移入子线程 */
export async function parseHomepageInTask(html: string, baseUrl: string, sourceKey: string,
  banner: VideoConfig, category: CategoryConfig): Promise<HomepageData> {
  const result: Object = await taskpool.execute(homepageParseTask, html, baseUrl, sourceKey, banner, category);
  return result as HomepageData;
}

/** 卡片模式：banner 提取移入子线程 */
export async function homepageBannerParseInTask(html: string, baseUrl: string, sourceKey: string,
  banner: VideoConfig): Promise<VideoInfo[]> {
  const result: Object = await taskpool.execute(homepageBannerParseTask, html, baseUrl, sourceKey, banner);
  return result as VideoInfo[];
}

/** 卡片模式：单卡片解析移入子线程 */
export async function homepageCardParseInTask(html: string, baseUrl: string, sourceKey: string,
  card: CategoryCardConfig): Promise<VideoInfo[]> {
  const result: Object = await taskpool.execute(homepageCardParseTask, html, baseUrl, sourceKey, card);
  return result as VideoInfo[];
}
