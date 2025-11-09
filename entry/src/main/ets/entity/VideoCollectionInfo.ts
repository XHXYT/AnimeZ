
import { ValuesBucket } from "@kit.ArkData"

// 视频历史记录的类型
// ValuesBucket 数据库类型约束
export interface VideoCollectionInfo extends ValuesBucket {
  id: number | null // 新增时 id 设置为 null ，可实现 id 自增
  // 视频页面链接
  link: string
  title: string
  coverUrl: string
  // 视频源
  sourceKey: string
  // 添加时间
  accessTime: number
}