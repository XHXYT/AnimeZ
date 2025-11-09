
// 视频历史记录的类型
import { ValuesBucket } from "@kit.ArkData"

// ValuesBucket 数据库类型约束
export interface VideoHistoryInfo extends ValuesBucket {
  id: number | null // 新增时 id 设置为 null ，可实现 id 自增
  // 视频页面链接
  link: string
  title: string
  totalTime: number
  currentTime: number
  coverUrl: string
  // 播放列表序号
  episodeListIndex: number
  // 播放分集序号
  episodeIndex: number
  episodeName: string
  videoUrl: string
  videoProgress: number
  // 视频源
  sourceKey: string
  // 添加时间
  accessTime: number
}