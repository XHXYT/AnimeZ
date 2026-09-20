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
      Logger.d('CategoryViewModel', '#loadFirstPage list=' + JSON.stringify(data))
      this.state = ViewState.CONTENT
      this.categoryDataSource.pushData(data)
    } catch (err) {
      this.errorMessage = err.message
      this.state = ViewState.ERROR
      Logger.e('fail', '获取界面视频数据', err)
    }
  }

  /**
   * 搜索（原 SearchPage.doSearch 的搜索部分；关键词校验与历史记录由调用方处理）
   */
  public async search(keyword: string) {
    this.state = ViewState.LOADING
    try {
      const videoList = await dataSourceManager.search(keyword, 1)
      this.videoList = videoList
      if (this.videoList.length == 0) {
        this.state = ViewState.EMPTY
      } else {
        this.state = ViewState.CONTENT
      }
    } catch (e) {
      this.errorMessage = JSON.stringify(e)
      this.state = ViewState.ERROR
    }
  }
}
