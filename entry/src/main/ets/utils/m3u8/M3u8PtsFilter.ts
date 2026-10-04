import http from '@ohos.net.http';
import Logger from '../Logger';
import M3U8Utils from './M3U8Utils';

const USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

const PTS_TAG = '#EXT-X-DISCONTINUITY'
const EXTINF_PREFIX = '#EXTINF'
const ENDLIST_TAG = '#EXT-X-ENDLIST'

/** 每组首分片探测字节数（首分片头部必含 PAT/PMT 与首个视频 PES/SPS） */
const PROBE_BYTES = 65536
const PROBE_TIMEOUT_MS = 10000
const PROBE_CONCURRENCY = 6
/** 整体分析超时：超时放行原列表，不阻塞播放 */
const OVERALL_TIMEOUT_MS = 20000
/** 组间 PTS 连续性判定容差（秒） */
const PTS_TOLERANCE_SEC = 2.0
/** 分组数超限直接放弃分析（控制探测成本） */
const MAX_ANALYZE_GROUPS = 150
/** 单个连续剔除段最大时长（秒）：广告中插一般远小于此，90 秒 OP/ED 不受误伤 */
const MAX_AD_RUN_SEC = 60
/** 剔除总时长占播放列表总时长比例上限 */
const MAX_REMOVED_RATIO = 0.25
/** 主时间线时长占比下限，低于此视为多段拼接内容，放弃过滤 */
const MIN_MAIN_RATIO = 0.4
/** PMT 中的视频流类型：MPEG1/MPEG2/H.264/HEVC/AVS */
const VIDEO_STREAM_TYPES: number[] = [0x01, 0x02, 0x1b, 0x24, 0x42]

interface M3u8PtsGroup {
  /** 组内原始行（不含 DISCONTINUITY 标记） */
  lines: string[]
  /** 组内分片总时长（EXTINF 累加） */
  duration: number
  /** 首个分片地址（相对或绝对） */
  firstSegUrl: string
}

interface M3u8PtsPlaylist {
  header: string[]
  groups: M3u8PtsGroup[]
  tail: string[]
}

interface M3u8PtsProbe {
  /** 组首分片首个视频 PES 的 PTS（秒） */
  ptsSec: number
  /** SPS 解析出的宽高（解析失败为 0） */
  width: number
  height: number
}

/**
 * PTS 连续性广告过滤：针对分片文件名无 URL 特征的混入广告（如 agedm 经 jx 解析服务
 * 生成的 mixed.m3u8，广告与正片同主机同路径、文件名为 hex 哈希）。
 *
 * 原理：正片分片按 EXT-X-DISCONTINUITY 分组后 PTS 时钟全程连续，广告组拥有独立的
 * PTS 时钟。对每组首分片做 Range 小流量探测，解析首个视频 PES 的 PTS，用动态规划
 * 选出时长最长的 PTS 连续链作为主时间线（允许跨组跳跃衔接，即跳过中插广告），
 * 不在主链上的组再经分辨率复核（广告常为不同分辨率重编码，与正片同分辨率时保守
 * 保留，避免误伤 OP/ED 等独立编码片段）后剔除，重写播放列表。
 *
 * 安全阀：加密/BYTERANGE/MAP 列表、分组数超限、任一探测失败、剔除段超 60 秒、
 * 剔除总量超 25%、主链占比不足 40%、整体超时——任一命中即原样放行，不影响播放。
 */
export default class M3u8PtsFilter {

  /** 入口：返回过滤后的播放列表内容；任何失败均原样返回入参 content */
  static async filter(content: string, playlistUrl: string): Promise<string> {
    const task = M3u8PtsFilter.filterInternal(content, playlistUrl)
    const fallback = new Promise<string>((resolve: (value: string) => void) => {
      setTimeout((): void => {
        resolve(content)
      }, OVERALL_TIMEOUT_MS)
    })
    return Promise.race([task, fallback])
  }

  private static async filterInternal(content: string, playlistUrl: string): Promise<string> {
    try {
      if (content.indexOf(PTS_TAG) < 0 || content.indexOf(ENDLIST_TAG) < 0) {
        return content
      }
      // 加密/字节范围/初始化段列表：探测语义复杂，直接放行
      if (content.indexOf('#EXT-X-KEY') >= 0 || content.indexOf('#EXT-X-BYTERANGE') >= 0
        || content.indexOf('#EXT-X-MAP') >= 0) {
        return content
      }
      const parsed = M3u8PtsFilter.parseGroups(content)
      if (!parsed || parsed.groups.length < 2 || parsed.groups.length > MAX_ANALYZE_GROUPS) {
        return content
      }
      const probes = await M3u8PtsFilter.probeAllGroups(parsed.groups, playlistUrl)
      if (!probes) {
        return content
      }
      const durations: number[] = []
      for (const g of parsed.groups) {
        durations.push(g.duration)
      }
      const ptsList: number[] = []
      for (const p of probes) {
        ptsList.push(p.ptsSec)
      }
      const chain = M3u8PtsFilter.selectMainChain(durations, ptsList)
      const removal = M3u8PtsFilter.verifyResolution(chain.keep, probes)
      if (removal.length === 0) {
        return content
      }
      if (!M3u8PtsFilter.checkSafety(parsed.groups, chain.keep, removal)) {
        return content
      }
      const rebuilt = M3u8PtsFilter.rebuild(parsed, removal)
      let removedSec = 0
      for (const idx of removal) {
        removedSec += parsed.groups[idx].duration
      }
      Logger.d('M3u8PtsFilter', 'PTS 广告过滤：分组 ' + parsed.groups.length + '，剔除广告组 '
        + removal.length + ' 组共 ' + removedSec.toFixed(1) + 's，正片时长 '
        + chain.mainDuration.toFixed(1) + 's')
      return rebuilt
    } catch (e) {
      Logger.e('fail', 'M3u8PtsFilter 分析失败，放行原列表', e)
      return content
    }
  }

  /**
   * 将播放列表切分为头部行、DISCONTINUITY 分组、尾部行；
   * 返回 null 表示结构异常
   */
  private static parseGroups(content: string): M3u8PtsPlaylist | null {
    const lines: string[] = content.split('\n')
    const header: string[] = []
    const groups: M3u8PtsGroup[] = []
    const tail: string[] = []
    let pending: string[] = []
    let cur: M3u8PtsGroup | null = null
    let inTail = false
    let inHeader = true
    for (const raw of lines) {
      const line = raw.trim()
      if (line === PTS_TAG) {
        if (cur) {
          groups.push(cur)
          cur = null
        }
        pending = []
      } else if (line.startsWith(EXTINF_PREFIX)) {
        if (inTail) {
          return null
        }
        const match = /^#EXTINF:([\d.]+),/.exec(line)
        if (!cur) {
          cur = { lines: pending.slice(), duration: 0, firstSegUrl: '' }
          pending = []
          inHeader = false
        }
        if (match) {
          cur.duration += parseFloat(match[1])
        }
        cur.lines.push(raw)
      } else if (line.length > 0 && !line.startsWith('#')) {
        if (inTail) {
          return null
        }
        if (!cur) {
          cur = { lines: pending.slice(), duration: 0, firstSegUrl: '' }
          pending = []
          inHeader = false
        }
        if (cur.firstSegUrl.length === 0) {
          cur.firstSegUrl = line
        }
        cur.lines.push(raw)
      } else if (line === ENDLIST_TAG) {
        if (cur) {
          groups.push(cur)
          cur = null
        }
        inTail = true
        tail.push(...pending)
        tail.push(raw)
        pending = []
      } else if (inHeader) {
        header.push(raw)
      } else if (cur) {
        cur.lines.push(raw)
      } else if (inTail) {
        tail.push(raw)
      } else {
        pending.push(raw)
      }
    }
    if (cur) {
      groups.push(cur)
    }
    tail.push(...pending)
    const valid: M3u8PtsGroup[] = groups.filter((g: M3u8PtsGroup): boolean => g.firstSegUrl.length > 0)
    return { header: header, groups: valid, tail: tail }
  }

  /** 探测所有分组首分片；任一失败返回 null（整体放行） */
  private static async probeAllGroups(groups: M3u8PtsGroup[],
    playlistUrl: string): Promise<M3u8PtsProbe[] | null> {
    const results: (M3u8PtsProbe | null)[] = new Array(groups.length).fill(null)
    let next = 0
    let failed = false
    const workers: Promise<void>[] = []
    const workerCount = Math.min(PROBE_CONCURRENCY, groups.length)
    for (let w = 0; w < workerCount; w++) {
      const worker = (async (): Promise<void> => {
        while (next < groups.length && !failed) {
          const idx = next++
          const probe = await M3u8PtsFilter.probeFirstSegment(
            M3U8Utils.getM3U8MasterUrl(playlistUrl, groups[idx].firstSegUrl))
          if (!probe) {
            failed = true
            return
          }
          results[idx] = probe
        }
      })()
      workers.push(worker)
    }
    await Promise.all(workers)
    if (failed) {
      Logger.d('M3u8PtsFilter', '分组探测失败，放行原列表')
      return null
    }
    const probes: M3u8PtsProbe[] = []
    for (const r of results) {
      if (!r) {
        return null
      }
      probes.push(r)
    }
    return probes
  }

  /** Range 请求首分片头部，解析首个视频 PTS 与 SPS 分辨率 */
  private static async probeFirstSegment(segUrl: string): Promise<M3u8PtsProbe | null> {
    if (!segUrl || segUrl.indexOf('http') !== 0) {
      return null
    }
    const httpRequest = http.createHttp()
    try {
      const resp: http.HttpResponse = await httpRequest.request(segUrl, {
        method: http.RequestMethod.GET,
        readTimeout: PROBE_TIMEOUT_MS,
        connectTimeout: PROBE_TIMEOUT_MS,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        header: {
          'user-agent': USER_AGENT,
          'range': 'bytes=0-' + (PROBE_BYTES - 1)
        }
      })
      if (resp.responseCode !== 200 && resp.responseCode !== 206) {
        return null
      }
      const body = resp.result
      if (!(body instanceof ArrayBuffer) || body.byteLength === 0) {
        return null
      }
      // 服务器忽略 Range 且分片过大：放弃分析，避免探测流量失控
      if (resp.responseCode === 200 && body.byteLength > PROBE_BYTES * 8) {
        Logger.d('M3u8PtsFilter', '服务器不支持 Range（code=200 size=' + body.byteLength + '），放行原列表')
        return null
      }
      const bytes = new Uint8Array(body)
      const pts = M3u8PtsFilter.extractFirstVideoPts(bytes)
      if (pts === null || pts < 0) {
        return null
      }
      const res = M3u8PtsFilter.extractAvcResolution(bytes)
      return {
        ptsSec: pts,
        width: res ? res.width : 0,
        height: res ? res.height : 0
      }
    } catch (e) {
      return null
    } finally {
      httpRequest.destroy()
    }
  }

  // ---------- TS / PES / PTS 解析 ----------

  private static detectPacketSize(bytes: Uint8Array): number {
    if (bytes.length < 192) {
      return 0
    }
    if (bytes[0] === 0x47) {
      return 188
    }
    if (bytes[4] === 0x47) {
      return 192
    }
    return 0
  }

  private static parsePatPmtPid(bytes: Uint8Array, p: number, end: number): number {
    if (p + 5 > end) {
      return -1
    }
    const q = p + 1 + bytes[p]
    if (q + 12 > end || bytes[q] !== 0x00) {
      return -1
    }
    const sectionLen = ((bytes[q + 1] & 0x0f) << 8) | bytes[q + 2]
    const limit = Math.min(q + 3 + sectionLen, end)
    let s = q + 8
    while (s + 4 <= limit) {
      const programNumber = (bytes[s] << 8) | bytes[s + 1]
      const pid = ((bytes[s + 2] & 0x1f) << 8) | bytes[s + 3]
      if (programNumber !== 0) {
        return pid
      }
      s += 4
    }
    return -1
  }

  private static parsePmtVideoPid(bytes: Uint8Array, p: number, end: number): number {
    if (p + 5 > end) {
      return -1
    }
    const q = p + 1 + bytes[p]
    if (q + 12 > end || bytes[q] !== 0x02) {
      return -1
    }
    const sectionLen = ((bytes[q + 1] & 0x0f) << 8) | bytes[q + 2]
    const limit = Math.min(q + 3 + sectionLen, end)
    const progInfoLen = ((bytes[q + 10] & 0x0f) << 8) | bytes[q + 11]
    let s = q + 12 + progInfoLen
    while (s + 5 <= limit) {
      const streamType = bytes[s]
      const pid = ((bytes[s + 1] & 0x1f) << 8) | bytes[s + 2]
      const esInfoLen = ((bytes[s + 3] & 0x0f) << 8) | bytes[s + 4]
      if (VIDEO_STREAM_TYPES.indexOf(streamType) >= 0) {
        return pid
      }
      s += 5 + esInfoLen
    }
    return -1
  }

  private static parsePesPts(bytes: Uint8Array, p: number, end: number): number | null {
    if (p + 14 > end) {
      return null
    }
    if (bytes[p] !== 0x00 || bytes[p + 1] !== 0x00 || bytes[p + 2] !== 0x01) {
      return null
    }
    const streamId = bytes[p + 3]
    if ((streamId & 0xf0) !== 0xe0) {
      return null
    }
    const ptsDtsFlags = (bytes[p + 7] >> 6) & 0x03
    if ((ptsDtsFlags & 0x02) === 0) {
      return null
    }
    const b0 = bytes[p + 9]
    const b1 = bytes[p + 10]
    const b2 = bytes[p + 11]
    const b3 = bytes[p + 12]
    const b4 = bytes[p + 13]
    if ((b0 & 0x01) !== 1 || (b2 & 0x01) !== 1 || (b4 & 0x01) !== 1) {
      return null
    }
    const pts = ((b0 >> 1) & 0x07) * 1073741824 + b1 * 4194304
      + ((b2 >> 1) & 0x7fff) * 32768 + b3 * 128 + (b4 >> 1)
    return pts / 90000
  }

  /** 提取缓冲区中首个视频 PES 的 PTS（秒） */
  private static extractFirstVideoPts(bytes: Uint8Array): number | null {
    const packetSize = M3u8PtsFilter.detectPacketSize(bytes)
    if (!packetSize) {
      return null
    }
    const syncOffset = packetSize === 192 ? 4 : 0
    let pmtPid = -1
    let videoPid = -1
    for (let off = 0; off + packetSize <= bytes.length; off += packetSize) {
      const base = off + syncOffset
      if (bytes[base] !== 0x47) {
        continue
      }
      const pid = ((bytes[base + 1] & 0x1f) << 8) | bytes[base + 2]
      const pusi = (bytes[base + 1] & 0x40) !== 0
      if (!pusi) {
        continue
      }
      const afc = (bytes[base + 3] >> 4) & 0x03
      if (afc === 0 || afc === 2) {
        continue
      }
      let p = base + 4
      if ((afc & 0x02) !== 0) {
        p += 1 + bytes[base + 4]
      }
      const end = base + 188
      if (p >= end) {
        continue
      }
      if (pid === 0 && pmtPid < 0) {
        pmtPid = M3u8PtsFilter.parsePatPmtPid(bytes, p, end)
      } else if (pmtPid >= 0 && pid === pmtPid && videoPid < 0) {
        videoPid = M3u8PtsFilter.parsePmtVideoPid(bytes, p, end)
      } else if (videoPid >= 0 && pid === videoPid) {
        const pts = M3u8PtsFilter.parsePesPts(bytes, p, end)
        if (pts !== null) {
          return pts
        }
      }
    }
    return null
  }

  // ---------- H.264 SPS 分辨率解析 ----------

  private static findNextStartCode(bytes: Uint8Array, from: number, end: number): number {
    for (let i = from; i + 3 < end; i++) {
      if (bytes[i] === 0 && bytes[i + 1] === 0 && bytes[i + 2] === 1) {
        return i
      }
    }
    return end
  }

  private static stripEmulationPrevention(bytes: Uint8Array, start: number, end: number): Uint8Array {
    const out: number[] = []
    let i = start
    while (i < end) {
      if (i + 2 < end && bytes[i] === 0 && bytes[i + 1] === 0 && bytes[i + 2] === 3) {
        out.push(0, 0)
        i += 3
      } else {
        out.push(bytes[i])
        i++
      }
    }
    return new Uint8Array(out)
  }

  private static parseAvcSps(bytes: Uint8Array, start: number, end: number): M3u8PtsProbe | null {
    const rbsp = M3u8PtsFilter.stripEmulationPrevention(bytes, start, end)
    const reader = new M3u8BitReader(rbsp)
    const profileIdc = reader.readBits(8)
    reader.readBits(8)
    reader.readBits(8)
    reader.readUE()
    let chromaFormatIdc = 1
    if (profileIdc === 100 || profileIdc === 110 || profileIdc === 122 || profileIdc === 244
      || profileIdc === 44 || profileIdc === 83 || profileIdc === 86 || profileIdc === 118
      || profileIdc === 128 || profileIdc === 138 || profileIdc === 139 || profileIdc === 134
      || profileIdc === 135) {
      chromaFormatIdc = reader.readUE()
      if (chromaFormatIdc === 3) {
        reader.readBit()
      }
      reader.readUE()
      reader.readUE()
      reader.readBit()
      if (reader.readBit() === 1) {
        const listCount = chromaFormatIdc === 3 ? 12 : 8
        for (let s = 0; s < listCount; s++) {
          if (reader.readBit() !== 1) {
            continue
          }
          const size = s < 6 ? 16 : 64
          let lastScale = 8
          let nextScale = 8
          for (let j = 0; j < size; j++) {
            if (nextScale !== 0) {
              const delta = reader.readSE()
              nextScale = (lastScale + delta + 256) % 256
            }
            if (nextScale !== 0) {
              lastScale = nextScale
            }
          }
        }
      }
    }
    reader.readUE()
    const pocType = reader.readUE()
    if (pocType === 0) {
      reader.readUE()
    } else if (pocType === 1) {
      reader.readBit()
      reader.readSE()
      reader.readSE()
      const refCycleCount = reader.readUE()
      for (let k = 0; k < refCycleCount; k++) {
        reader.readSE()
      }
    }
    reader.readUE()
    reader.readBit()
    const picWidthMbs = reader.readUE() + 1
    const picHeightMapUnits = reader.readUE() + 1
    const frameMbsOnly = reader.readBit()
    if (frameMbsOnly !== 1) {
      reader.readBit()
    }
    reader.readBit()
    let cropLeft = 0
    let cropRight = 0
    let cropTop = 0
    let cropBottom = 0
    if (reader.readBit() === 1) {
      cropLeft = reader.readUE()
      cropRight = reader.readUE()
      cropTop = reader.readUE()
      cropBottom = reader.readUE()
    }
    let width = picWidthMbs * 16
    let height = (2 - frameMbsOnly) * picHeightMapUnits * 16
    const cropUnitX = chromaFormatIdc === 1 || chromaFormatIdc === 2 ? 2 : 1
    const cropUnitY = (chromaFormatIdc === 1 ? 2 : 1) * (2 - frameMbsOnly)
    width -= (cropLeft + cropRight) * cropUnitX
    height -= (cropTop + cropBottom) * cropUnitY
    if (width < 16 || width > 8192 || height < 16 || height > 8192
      || width % 2 !== 0 || height % 2 !== 0) {
      return null
    }
    return { ptsSec: 0, width: width, height: height }
  }

  /** 提取缓冲区中 H.264 SPS 的分辨率；未找到或解析失败返回 null */
  private static extractAvcResolution(bytes: Uint8Array): M3u8PtsProbe | null {
    const len = bytes.length
    for (let i = 0; i + 4 < len; i++) {
      if (bytes[i] === 0 && bytes[i + 1] === 0 && bytes[i + 2] === 1) {
        if ((bytes[i + 3] & 0x1f) === 7) {
          return M3u8PtsFilter.parseAvcSps(bytes, i + 4, M3u8PtsFilter.findNextStartCode(bytes, i + 4, len))
        }
      } else if (bytes[i] === 0 && bytes[i + 1] === 0 && bytes[i + 2] === 0 && bytes[i + 3] === 1) {
        if ((bytes[i + 4] & 0x1f) === 7) {
          return M3u8PtsFilter.parseAvcSps(bytes, i + 5, M3u8PtsFilter.findNextStartCode(bytes, i + 5, len))
        }
      }
    }
    return null
  }

  // ---------- 主时间线选择与重建 ----------

  /**
   * 动态规划选出时长最长的 PTS 连续链（允许跳过中间不连续的组衔接），
   * 主时间线之外的组为广告候选
   */
  private static selectMainChain(durations: number[], ptsList: number[]): { keep: boolean[], mainDuration: number } {
    const n = durations.length
    const best: number[] = new Array(n)
    const prev: number[] = new Array(n)
    for (let i = 0; i < n; i++) {
      best[i] = durations[i]
      prev[i] = -1
    }
    for (let j = 1; j < n; j++) {
      for (let i = 0; i < j; i++) {
        if (Math.abs(ptsList[j] - (ptsList[i] + durations[i])) <= PTS_TOLERANCE_SEC) {
          if (best[i] + durations[j] > best[j]) {
            best[j] = best[i] + durations[j]
            prev[j] = i
          }
        }
      }
    }
    let end = 0
    for (let i = 1; i < n; i++) {
      if (best[i] > best[end]) {
        end = i
      }
    }
    const keep: boolean[] = new Array(n).fill(false)
    let k = end
    while (k >= 0) {
      keep[k] = true
      k = prev[k]
    }
    return { keep: keep, mainDuration: best[end] }
  }

  /** 主时间线分辨率取多数派；剔除候选必须与其不同，分辨率未知的候选保守保留 */
  private static verifyResolution(keep: boolean[], probes: M3u8PtsProbe[]): number[] {
    const counter = new Map<string, number>()
    for (let i = 0; i < probes.length; i++) {
      if (!keep[i] || probes[i].width === 0) {
        continue
      }
      const key = probes[i].width + 'x' + probes[i].height
      const count = counter.get(key) ?? 0
      counter.set(key, count + 1)
    }
    let refKey: string | null = null
    let refCount = 0
    counter.forEach((count: number, key: string): void => {
      if (count > refCount) {
        refCount = count
        refKey = key
      }
    })
    if (!refKey) {
      return []
    }
    const removal: number[] = []
    for (let i = 0; i < probes.length; i++) {
      if (keep[i] || probes[i].width === 0) {
        continue
      }
      const key = probes[i].width + 'x' + probes[i].height
      if (key !== refKey) {
        removal.push(i)
      }
    }
    return removal
  }

  /** 数值安全阀：连续剔除段超 60s、总量超 25%、主链占比不足 40% 时放弃过滤 */
  private static checkSafety(groups: M3u8PtsGroup[], keep: boolean[], removal: number[]): boolean {
    let total = 0
    for (const g of groups) {
      total += g.duration
    }
    if (total <= 0) {
      return false
    }
    let removedTotal = 0
    for (const idx of removal) {
      removedTotal += groups[idx].duration
    }
    if (removedTotal <= 0 || removedTotal > total * MAX_REMOVED_RATIO) {
      return false
    }
    const removalSet = new Set<number>(removal)
    let run = 0
    for (let i = 0; i < groups.length; i++) {
      if (removalSet.has(i)) {
        run += groups[i].duration
        if (run > MAX_AD_RUN_SEC) {
          return false
        }
      } else {
        run = 0
      }
    }
    let mainTotal = 0
    for (let i = 0; i < groups.length; i++) {
      if (keep[i]) {
        mainTotal += groups[i].duration
      }
    }
    return mainTotal >= total * MIN_MAIN_RATIO
  }

  /**
   * 重建播放列表：剔除广告组；保留组之间始终保留 DISCONTINUITY 标记——
   * PTS 连续不等于编码参数一致（片头与正片可能来自不同编码），省略标记会导致部分解码器中断
   */
  private static rebuild(parsed: M3u8PtsPlaylist, removal: number[]): string {
    const removalSet = new Set<number>(removal)
    const groups = parsed.groups
    const out: string[] = []
    for (const h of parsed.header) {
      out.push(h)
    }
    let emitted = false
    for (let i = 0; i < groups.length; i++) {
      if (removalSet.has(i)) {
        continue
      }
      if (emitted) {
        out.push(PTS_TAG)
      }
      for (const line of groups[i].lines) {
        out.push(line)
      }
      emitted = true
    }
    for (const t of parsed.tail) {
      out.push(t)
    }
    return out.join('\n')
  }
}

/** SPS RBSP 比特流读取器（Exp-Golomb 解码） */
class M3u8BitReader {
  private bytes: Uint8Array
  private pos: number

  constructor(bytes: Uint8Array) {
    this.bytes = bytes
    this.pos = 0
  }

  readBit(): number {
    const byteIndex = this.pos >> 3
    if (byteIndex >= this.bytes.length) {
      return 0
    }
    const bit = (this.bytes[byteIndex] >> (7 - (this.pos & 7))) & 1
    this.pos++
    return bit
  }

  readBits(count: number): number {
    let value = 0
    for (let i = 0; i < count; i++) {
      value = (value << 1) | this.readBit()
    }
    return value
  }

  readUE(): number {
    let zeros = 0
    while (this.readBit() === 0 && zeros < 32) {
      zeros++
    }
    if (zeros === 0) {
      return 0
    }
    if (zeros > 31) {
      return 0
    }
    return (1 << zeros) - 1 + this.readBits(zeros)
  }

  readSE(): number {
    const k = this.readUE()
    return (k & 1) === 1 ? (k + 1) / 2 : -(k / 2)
  }
}
