/**
 * @projectName:    AnimeZ 
 * @fileName:      appContinueModel
 * @author:     SummerKaze
 * @description:  应用接续类
 * @date:    2025/10/29 14:26
 * @version:    1.0
 */
import { VideoNavigateInfo } from "../entity/VideoNavigateInfo";
import { hilog } from "@kit.PerformanceAnalysisKit";

export interface IAppContinue {
  currentPage: string;
  currentPageParams: VideoNavigateInfo;
  currentVideoDuration: number;
}

const TAG = 'AppContinueModel'

/** @description 应用接续数据模型 */
class AppContinueModel {
  /** @description 是否恢复过进度 */
  isContinue: boolean = false;
  /** @description 当前路由信息 */
  private currentPage: string = '';
  /** @description 当前页面参数 */
  private currentPageParams: VideoNavigateInfo = {} as VideoNavigateInfo;
  /** @description 当前播放视频的进度 */
  private currentVideoDuration: number = 0;

  /**
   * 跳转页面的时候保存一份当前页面信息 -> 接续时需要手动恢复
   * @param page 当前页面
   * @param params 页面参数
   */
  public jumpVideoDetail(page: string, params: VideoNavigateInfo) {
    this.currentPage = page;
    this.currentPageParams = params;
    hilog.warn(0x0001, TAG, 'jumpVideoDetail - page=' + this.currentPage + ' params=' + JSON.stringify(this.currentPageParams))
  }

  /**
   * 保存当前播放视频的进度
   * @param duration 当前播放视频的进度
   */
  public setCurrentVideoDuration(duration: number) {
    hilog.info(0x0001, TAG, 'set - duration=' + duration)
    this.currentVideoDuration = duration;
  }

  /**
   * 获取当前播放视频的进度
   * @returns 当前播放视频的进度
   */
  public getCurrentVideoDuration(): number {
    // TODO 获取到的数据存在问题，需要处理 都为 0
    const duration = this.currentVideoDuration;
    hilog.warn(0x0001, TAG, 'get - duration=' + duration)
    return duration;
  }

  /**
   * 获取当前页面信息
   * @returns 当前页面信息
   */
  public getCurrentVideoPageDetail(): IAppContinue {
    return {
      currentPage: this.currentPage,
      currentPageParams: this.currentPageParams,
      currentVideoDuration: this.currentVideoDuration
    }
  }

  /**
   * 接续数据恢复
   * @param data 接续数据
   */
  public RecoverData (data: IAppContinue) {
    hilog.warn(0x0001, TAG, 'RecoverData =' + JSON.stringify(data))

    this.currentPage = data.currentPage;
    this.currentPageParams = data.currentPageParams;
    this.currentVideoDuration = data.currentVideoDuration;
  }
}

export const appContinueModel = new AppContinueModel();