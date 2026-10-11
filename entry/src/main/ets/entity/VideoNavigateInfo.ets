

/**
 * 路由时的视频信息
 */
export interface VideoNavigateInfo {
  id: number | null, // 新增时 id 设置为 null ，可实现 id 自增
  url: string,
  sourceKey: string,
  title: string,
  cover: string,
  /** 画中画恢复进入：以小窗实时进度续播 */
  isPiPRestore?: boolean,
  /** 画中画恢复时的播放位置（毫秒） */
  pipPosition?: number,
  /** 画中画恢复：小窗最后播放的剧集列表索引（小窗内切过集时与历史不一致） */
  pipEpisodeListIndex?: number,
  /** 画中画恢复：小窗最后播放的集索引 */
  pipEpisodeIndex?: number,
  /** 画中画恢复：小窗最后播放的集名 */
  pipEpisodeName?: string
}

/**
 * 视频目录路由
 */
export interface VideoCategoryNavigateInfo {
  sourceKey: string,
  url: string,
  title: string,
}