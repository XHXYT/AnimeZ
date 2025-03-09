import EpisodeList from './EpisodeList';
import VideoInfo from './VideoInfo';

/**
 * 视频详情信息
 */
export default interface VideoDetailInfo extends VideoInfo {

    /**
     * 封面链接
     */
    coverUrl: string
    /**
     * 视频描述
     */
    desc?: string
    /**
     * 分类信息
     */
    category?: string
    /**
     * 导演信息
     */
    director?: string
    /**
     * 播放列表
     */
    episodes: EpisodeList[];
    /**
     * 推荐视频
     */
    recommends: VideoInfo[];

}

/**
 * 路由时的视频信息
 */
export interface VideoNavigateInfo {
    id: number | null, // 新增时 id 设置为 null ，可实现 id 自增
    url: string,
    sourceKey: string,
    title: string,
    cover: string
}