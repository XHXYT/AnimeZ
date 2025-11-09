

// 搜索历史记录的类型
import { ValuesBucket } from "@kit.ArkData"

// ValuesBucket 数据库类型约束
export interface SearchHistoryInfo extends ValuesBucket {
  id: number | null // 新增时 id 设置为 null ，可实现 id 自增
  // 搜索词
  keyword: string
  // 添加时间
  accessTime: number
}