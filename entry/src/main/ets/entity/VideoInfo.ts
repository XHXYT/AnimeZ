
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