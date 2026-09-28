import VideoInfo from '../entity/VideoInfo';
import { DramaList } from '../entity/HomepageData';
import { ViewState } from '../components/StateView';
import { SOURCE_CHANGED_EVENT } from '../utils/EventBus';
import Logger from '../utils/Logger';
import { dataSourceManager } from '../api/DataSourceManager';

/**
 * 首页 ViewModel（单例）
 * 从 Homepage 页面抽离的数据加载逻辑；常驻订阅数据源变更事件，替代页面 aboutToAppear/aboutToDisappear 订阅对。
 */
@ObservedV2
export class HomeViewModel {

  @Trace bannerList: VideoInfo[] = []
  @Trace categoryList: DramaList[] = []
  @Trace state: number = ViewState.CUSTOM
  @Trace errorMessage: string = ''

  constructor() {
    // 常驻订阅数据源变更，替代原页面级订阅/退订
    SOURCE_CHANGED_EVENT.on(() => {
      this.loadHomepageData()
    })
  }

  /**
   * 加载首页数据（原 Homepage.loadNextPage）
   */
  public loadHomepageData() {
    // 未配置任何视频源：首页直接引导导入配置，不发起数据请求
    if (dataSourceManager.getAllDataSourceConfigs().length === 0) {
      this.state = ViewState.EMPTY
      this.errorMessage = '请导入配置后使用'
      return
    }
    this.state = ViewState.LOADING
    dataSourceManager.getHomepageData()
      .then((data) => {
        this.bannerList = data.bannerList
        this.categoryList = data.categoryList
        this.state = ViewState.CONTENT
      })
      .catch((e: Error) => {
        this.errorMessage = e.message
        this.state = ViewState.ERROR
        console.log(`主页state状态：${this.state}`)
        Logger.e('fail', '主页数据加载', e)
      })
  }
}

export const homeViewModel: HomeViewModel = new HomeViewModel()
