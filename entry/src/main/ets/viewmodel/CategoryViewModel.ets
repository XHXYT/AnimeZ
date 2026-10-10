import VideoInfo from '../entity/VideoInfo';
import { ViewState } from '../components/StateView';
import Logger from '../utils/Logger';
import { dataSourceManager } from '../api/DataSourceManager';
import { CategoryDataSource } from '../entity/CategoryData';

/**
 * 视频目录/搜索结果 ViewModel（每页 new）
 * CategoryPage 与 SearchPage 各持一个实例：
 * - CategoryPage 走 loadFirstPage(url) + categoryDataSource
 * - SearchPage 走 search(keyword) + videoList
 * NavDestination 实例栈保证返回时数据自然保留，无需手工恢复逻辑。
 */
@ObservedV2
export class CategoryViewModel {

  @Trace state: number = ViewState.CUSTOM
  @Trace errorMessage: string = ''
  /** 搜索结果列表（SearchPage） */
  @Trace videoList: VideoInfo[] = []
  /** 搜索代际：发起新搜索/返回记录页时自增，丢弃过期批次的流式推送 */
  private searchGeneration: number = 0

  /** 目录页数据源（CategoryPage），引用由 VM 持有，通过 IDataSource 自身通知刷新 */
  readonly categoryDataSource: CategoryDataSource = new CategoryDataSource([])

  /** 目录页当前加载地址（onRetry 重试用） */
  public url: string = ''

  /**
   * 加载目录第一页（原 CategoryPage.loadFirstPage）
   */
  public async loadFirstPage(url: string) {
    this.url = url
    this.state = ViewState.LOADING
    try {
      const data = await dataSourceManager.getVideoList(this.url, 0)
      this.state = ViewState.CONTENT
      this.categoryDataSource.pushData(data)
    } catch (err) {
      this.errorMessage = err.message
      this.state = ViewState.ERROR
      Logger.e('fail', '获取界面视频数据', err)
    }
  }

  /**
   * 搜索（关键词校验与历史记录由调用方处理）
   * 流式填充：不进全屏加载态，每个数据源完成后立即把该批结果推入 videoList
   * @param keyword 关键词
   * @param precise true=精准（标题与关键词完全一致），false=模糊（标题包含关键词，忽略大小写）
   * @param blockWords 结果屏蔽词列表，标题命中即过滤
   * @param sourceKeys 限定参与搜索的数据源 key 列表，为空时搜索全部已启用源
   */
  public async search(keyword: string, precise: boolean = false, blockWords: string[] = [],
    sourceKeys?: string[]) {
    const generation = ++this.searchGeneration
    this.errorMessage = ''
    this.videoList = []
    this.state = ViewState.CONTENT
    try {
      await dataSourceManager.searchStream(keyword, 1, sourceKeys, (batch: VideoInfo[]): void => {
        if (generation !== this.searchGeneration) {
          return
        }
        const filtered = this.filterResults(batch, keyword, precise, blockWords)
        if (filtered.length > 0) {
          this.videoList = this.videoList.concat(filtered)
        }
      })
      if (generation !== this.searchGeneration) {
        return
      }
      if (this.videoList.length == 0) {
        this.state = ViewState.EMPTY
      }
    } catch (e) {
      if (generation !== this.searchGeneration) {
        return
      }
      this.errorMessage = JSON.stringify(e)
      this.state = ViewState.ERROR
    }
  }

  /**
   * 返回搜索记录页（SearchPage 返回拦截时复位状态），并中断进行中的流式搜索
   */
  public backToHistory(): void {
    this.searchGeneration++
    this.videoList = []
    this.errorMessage = ''
    this.state = ViewState.CUSTOM
  }

  /**
   * 结果过滤：精准/模糊匹配 + 屏蔽词
   */
  private filterResults(videoList: VideoInfo[], keyword: string, precise: boolean,
    blockWords: string[]): VideoInfo[] {
    const kw = keyword.trim()
    let result = videoList
    if (precise) {
      result = result.filter((video: VideoInfo): boolean => video.title.trim() === kw)
    } else {
      const lowerKw = kw.toLowerCase()
      result = result.filter((video: VideoInfo): boolean => video.title.toLowerCase().includes(lowerKw))
    }
    if (blockWords.length > 0) {
      const lowerBlockWords = blockWords.map((word: string): string => word.toLowerCase())
      result = result.filter((video: VideoInfo): boolean => {
        const lowerTitle = video.title.toLowerCase()
        return !lowerBlockWords.some((word: string): boolean => lowerTitle.includes(word))
      })
    }
    return result
  }
}
