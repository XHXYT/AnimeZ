// ConcurrentTasks.ets
// taskpool 并发任务（@Concurrent 必须位于 .ets 文件，编译器才会生成并发标记）
// 主线程仅发起网络请求，将 HTML 字符串与解析配置传入子线程；
// htmlsoup parse + select + 字段提取在子线程完成后回传纯数据，
// 避免 HtmlTag DOM 树（含 parent 循环引用）跨线程传递。
// .ts 调用方无法 import 本文件，经 TaskRegistry 在启动时注入获取。
import { taskpool } from '@kit.ArkTS';
import { CategoryCardConfig, CategoryConfig, VideoConfig } from './DataSourceConfig';
import HomepageData from '../entity/HomepageData';
import VideoInfo from '../entity/VideoInfo';
import { extractBannerFromHtml, extractCardItemsFromHtml, extractVideoListFromHtml, parseHomepageDocument } from './HomepageExtractor';
import { ConcurrentTaskFns, registerConcurrentTaskFns } from './TaskRegistry';

/** 同页模式：整页解析任务（banner + 分类） */
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

/** 视频列表页解析任务（分类页"更多"列表） */
@Concurrent
async function videoListParseTask(html: string, baseUrl: string, sourceKey: string,
  config: VideoConfig): Promise<VideoInfo[]> {
  return await extractVideoListFromHtml(html, baseUrl, sourceKey, config);
}

async function parseHomepageInTaskImpl(html: string, baseUrl: string, sourceKey: string,
  banner: VideoConfig, category: CategoryConfig): Promise<HomepageData> {
  const result: Object = await taskpool.execute(homepageParseTask, html, baseUrl, sourceKey, banner, category);
  return result as HomepageData;
}

async function homepageBannerParseInTaskImpl(html: string, baseUrl: string, sourceKey: string,
  banner: VideoConfig): Promise<VideoInfo[]> {
  const result: Object = await taskpool.execute(homepageBannerParseTask, html, baseUrl, sourceKey, banner);
  return result as VideoInfo[];
}

async function homepageCardParseInTaskImpl(html: string, baseUrl: string, sourceKey: string,
  card: CategoryCardConfig): Promise<VideoInfo[]> {
  const result: Object = await taskpool.execute(homepageCardParseTask, html, baseUrl, sourceKey, card);
  return result as VideoInfo[];
}

async function videoListParseInTaskImpl(html: string, baseUrl: string, sourceKey: string,
  config: VideoConfig): Promise<VideoInfo[]> {
  const result: Object = await taskpool.execute(videoListParseTask, html, baseUrl, sourceKey, config);
  return result as VideoInfo[];
}

/** 应用启动时调用（EntryAbility.onCreate），把任务封装注入 TaskRegistry 供 .ts 调用方获取 */
export function initConcurrentTasks(): void {
  const fns: ConcurrentTaskFns = {
    parseHomepageInTask: parseHomepageInTaskImpl,
    homepageBannerParseInTask: homepageBannerParseInTaskImpl,
    homepageCardParseInTask: homepageCardParseInTaskImpl,
    videoListParseInTask: videoListParseInTaskImpl
  };
  registerConcurrentTaskFns(fns);
}
