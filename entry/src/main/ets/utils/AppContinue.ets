/**
 * @projectName:    AnimeZ 
 * @fileName:      AppContinue
 * @author:     SummerKaze
 * @description:  应用接续类
 * @date:    2025/10/29 14:26
 * @version:    1.0
 */
import { VideoNavigateInfo } from "../entity/VideoNavigateInfo";

export interface IAppContinue {
  currentPage: string;
  currentPageParams: VideoNavigateInfo;
}

class AppContinue {
  private currentPage: string = '';
  private currentPageParams: VideoNavigateInfo = {} as VideoNavigateInfo;

  /**
   * 跳转页面的时候保存一份当前页面信息 -> 接续时需要手动恢复
   * @param page 当前页面
   * @param params 页面参数
   */
  public jumpVideoDetail(page: string, params: VideoNavigateInfo) {
    this.currentPage = page;
    this.currentPageParams = params;
  }

  /**
   * 获取当前页面信息
   * @returns 当前页面信息
   */
  public getCurrentVideoPageDetail(): IAppContinue {
    return {
      currentPage: this.currentPage,
      currentPageParams: this.currentPageParams
    }
  }
}

export const appContinue = new AppContinue();