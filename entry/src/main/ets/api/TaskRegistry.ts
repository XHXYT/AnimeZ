// TaskRegistry.ts
// 并发任务注册表：@Concurrent 任务必须定义在 .ets 文件中（.ts 中的 @Concurrent
// 编译通过但运行时无并发标记，taskpool.execute 会报 10200014 "not marked as concurrent"），
// 而 .ts 文件又不能 import .ets —— 因此由 ConcurrentTasks.ets 在应用启动时
// 把任务封装注入本注册表，GenericDataSource.ts 等 .ts 调用方经此获取。
import { CategoryCardConfig, CategoryConfig, VideoConfig } from './DataSourceConfig';
import HomepageData from '../entity/HomepageData';
import VideoInfo from '../entity/VideoInfo';

/** 首页/列表页解析任务封装（由 ConcurrentTasks.ets 提供） */
export interface ConcurrentTaskFns {
  /** 同页模式：整页解析（banner + 分类）移入子线程 */
  parseHomepageInTask: (html: string, baseUrl: string, sourceKey: string,
    banner: VideoConfig, category: CategoryConfig) => Promise<HomepageData>;
  /** 卡片模式：banner 提取移入子线程 */
  homepageBannerParseInTask: (html: string, baseUrl: string, sourceKey: string,
    banner: VideoConfig) => Promise<VideoInfo[]>;
  /** 卡片模式：单卡片解析移入子线程 */
  homepageCardParseInTask: (html: string, baseUrl: string, sourceKey: string,
    card: CategoryCardConfig) => Promise<VideoInfo[]>;
  /** 视频列表页解析移入子线程 */
  videoListParseInTask: (html: string, baseUrl: string, sourceKey: string,
    config: VideoConfig) => Promise<VideoInfo[]>;
}

let taskFns: ConcurrentTaskFns | null = null;

/** 由 ConcurrentTasks.ets 在应用启动时调用（EntryAbility.onCreate -> initConcurrentTasks） */
export function registerConcurrentTaskFns(fns: ConcurrentTaskFns): void {
  taskFns = fns;
}

export function getConcurrentTaskFns(): ConcurrentTaskFns {
  if (taskFns === null) {
    throw new Error('并发任务未注册：需在 EntryAbility 启动时调用 initConcurrentTasks');
  }
  return taskFns;
}
