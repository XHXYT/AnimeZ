
/**
 * 视频信息
 */
export default interface VideoInfo {

    /**
     * 数据源key
     */
    sourceKey: string
    /**
     * 视频标题
     */
    title: string;
    /**
     * 图片链接
     */
    imgUrl?: string;
    /**
     * 页面链接
     */
    url?: string;
    /**
     * 更新时间
     */
    updateTime?: string;
    /**
     * 剧集数
     */
    episode?: string;
    /**
     * 播放量（可选，如 "1.2万"）
     */
    playCount?: string;
    /**
     * 播出年份（可选，如 "2012"）
     */
    year?: string;
    /**
     * 播出月份（可选，如 "04"）
     */
    month?: string;
    /**
     * 导演（可选）
     */
    director?: string;
    /**
     * 演员（可选，多个以分隔符连接）
     */
    actors?: string;
    /**
     * 标签（可选，多个以分隔符连接）
     */
    tags?: string;
    /**
     * 演员信息
     */
    protagonist?: string;
    /**
     * 视频类型
     */
    videoType?: TypeInfo[]
    /**
     * 视频简介
     */
    videoIntroduction?: string
}



export interface TypeInfo {

    typeName: string

    typeUrl?: string
}