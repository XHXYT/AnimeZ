

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

/**
 * 视频目录路由
 */
export interface VideoCategoryNavigateInfo {
  sourceKey: string,
  url: string,
  title: string,
}