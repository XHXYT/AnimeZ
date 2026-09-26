/**
 * 数据源标签配色工具（同一数据源固定使用同一颜色）
 */
const SOURCE_BADGE_COLORS: string[] = [
  '#e91e63', '#9c27b0', '#673ab7', '#3f51b5', '#2196f3',
  '#03a9f4', '#009688', '#4caf50', '#ff9800', '#f44336'
]

/**
 * 按源 key 生成稳定的标签颜色
 */
export function sourceBadgeColor(key: string): string {
  let hash: number = 0
  for (let i = 0; i < key.length; i++) {
    hash = (hash * 31 + key.charCodeAt(i)) % 1000000007
  }
  return SOURCE_BADGE_COLORS[hash % SOURCE_BADGE_COLORS.length]
}
