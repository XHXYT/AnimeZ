import EpisodeInfo from '../entity/EpisodeInfo';

/**
 * 从字符串中提取第一个数字
 * @param str 输入的字符串
 * @returns 提取出的数字，如果找不到则返回 0
 */
function extractNumberFromTitle(str: string): number {
  const match = str.match(/\d+/);
  return match ? parseInt(match[0], 10) : 0;
}

/**
 * 根据 title 中的数字对剧集数组进行排序
 * @param episodes 剧集数组
 * @param order 'asc' 为升序 (默认), 'desc' 为降序
 */
export function sortEpisodesByNumber(episodes: EpisodeInfo[], order: 'asc' | 'desc' = 'asc'): EpisodeInfo[] {
  const sortedEpisodes = [...episodes].sort((a, b) => {
    const numA = extractNumberFromTitle(a.title);
    const numB = extractNumberFromTitle(b.title);

    if (order === 'asc') {
      return numA - numB;
    } else {
      return numB - numA;
    }
  });

  return sortedEpisodes;
}