import HomepageData from '../entity/HomepageData';
import VideoInfo from '../entity/VideoInfo';
import VideoDetailInfo from '../entity/VideoDetailInfo';

/**
 * 数据源
 */
export default interface DataSource {

    /**
     * 获取key
     */
    getKey(): string

    /**
     * 搜索视频
     */
    search(keyword: string, page: number): Promise<VideoInfo[]>

    /**
     * 获取主页数据
     */
    getHomepageData(): Promise<HomepageData>

    /**
     * 是否配置了周表
     */
    hasScheduleConfig(): boolean

    /**
     * 获取周表数据（weekday: 1-7，周一=1）
     */
    getSchedule(weekday: number): Promise<VideoInfo[]>

    /**
     * 获取片源列表数据
     */
    getVideoList(moreUrl: string, page: number): Promise<VideoInfo[]>

    /**
     * 获取视频详情
     */
    getVideoDetailInfo(url: string): Promise<VideoDetailInfo>

    /**
     * 解析视频链接
     */
    parseVideoUrl(link: string): Promise<string>


}