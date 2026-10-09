import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import Logger from '../Logger';
import HttpUtils from '../HttpUtils';

/**
 * TS 剥壳本地代理：部分站点的分片伪装成图片（头部垃圾字节），原生播放器无法解复用。
 * 由 127.0.0.1 代理代抓（带 Referer）、剥离伪装前缀后回吐干净 TS；m3u8 则改写分片行继续走本代理。
 * 无状态设计（远端地址与 Referer 均在 URL 参数中），固定端口，跨重启后历史记录中的地址仍有效。
 * 仅对显式配置 proxy 的源生效，其它源零影响。进程内单例，随进程存活。
 * 播放列表路径带 .m3u8、分片路径带 .ts 后缀：系统播放器（AVPlayer）依赖 URL 后缀识别源格式，
 * 无后缀会报 5400106（unsupport container format）。路径仅作格式提示，参数解析与路径无关。
 */
export default class TsStripProxyServer {
  private static readonly DEFAULT_PORT = 20471
  private static server: socket.TCPSocketServer | null = null
  private static port: number = -1
  private static starting: Promise<void> | null = null

  /**
   * 预热服务（App 启动时调用，失败仅记日志）
   */
  static preheat(): void {
    TsStripProxyServer.ensureServer().catch((e: BusinessError): void => {
      Logger.e('fail', 'TsStripProxyServer preheat failed', e)
    })
  }

  /**
   * 包装远端地址为本地代理地址；服务不可用时返回原地址
   */
  static async wrap(remoteUrl: string, referer: string): Promise<string> {
    await TsStripProxyServer.ensureServer()
    if (TsStripProxyServer.port <= 0 || !TsStripProxyServer.server) {
      return remoteUrl
    }
    let path = '/media.m3u8?u=' + encodeURIComponent(remoteUrl)
    if (referer) {
      path += '&ref=' + encodeURIComponent(referer)
    }
    return 'http://127.0.0.1:' + TsStripProxyServer.port + path
  }

  private static ensureServer(): Promise<void> {
    if (TsStripProxyServer.server) {
      return Promise.resolve()
    }
    if (!TsStripProxyServer.starting) {
      TsStripProxyServer.starting = new Promise<void>((resolve: () => void) => {
        const server = socket.constructTCPSocketServerInstance()
        server.on('connect', (client: socket.TCPSocketConnection) => {
          Logger.d('TsStripProxyServer', 'client connected')
          TsStripProxyServer.handleClient(client)
        })
        server.on('error', (e: BusinessError): void => {
          Logger.e('fail', 'TsStripProxyServer server error', e)
        })
        // 先尝试固定端口（历史记录中的本地地址依赖它），失败再随机回退
        TsStripProxyServer.tryListen(server, TsStripProxyServer.DEFAULT_PORT, 0, resolve)
      })
    }
    return TsStripProxyServer.starting
  }

  private static tryListen(server: socket.TCPSocketServer, port: number, attempt: number, onDone: () => void): void {
    server.listen({ address: '127.0.0.1', port: port }).then((): void => {
      TsStripProxyServer.server = server
      TsStripProxyServer.port = port
      Logger.d('TsStripProxyServer', 'listening 127.0.0.1:' + port)
      onDone()
    }).catch((e: BusinessError): void => {
      Logger.e('fail', 'TsStripProxyServer listen ' + port + ' failed', e)
      if (attempt >= 8) {
        onDone()
        return
      }
      TsStripProxyServer.tryListen(server, 20000 + Math.floor(Math.random() * 20000), attempt + 1, onDone)
    })
  }

  private static handleClient(client: socket.TCPSocketConnection): void {
    let served = false
    let received = ''
    client.on('message', (info: socket.SocketMessageInfo): void => {
      if (served) {
        return
      }
      try {
        received += util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(info.message))
      } catch (e) {
        Logger.e('fail', 'TsStripProxyServer decode request failed', e)
        served = true
        TsStripProxyServer.respondError(client, 400)
        return
      }
      // 请求头未接收完整且未超限时继续等待（请求可能分多个 TCP 包到达）
      if (received.indexOf('\r\n\r\n') < 0 && received.length < 16384) {
        return
      }
      served = true
      const lineEnd = received.indexOf('\r\n')
      const firstLine = lineEnd >= 0 ? received.substring(0, lineEnd) : received
      const parts = firstLine.split(' ')
      const method = parts.length >= 1 ? parts[0].toUpperCase() : 'GET'
      const userAgent = TsStripProxyServer.extractHeader(received, 'User-Agent')
      Logger.d('TsStripProxyServer', 'request: ' + firstLine + (userAgent ? ' ua=' + userAgent : ''))
      const query = TsStripProxyServer.parseQuery(parts.length >= 2 ? parts[1] : '')
      const target = query['u'] ?? ''
      const referer = query['ref'] ?? ''
      if (!target) {
        TsStripProxyServer.respondError(client, 404)
        return
      }
      TsStripProxyServer.serveMedia(client, target, referer, method === 'HEAD')
    })
    client.on('close', (): void => {
      Logger.d('TsStripProxyServer', 'client closed')
    })
    client.on('error', (e: BusinessError): void => {
      Logger.e('fail', 'TsStripProxyServer client error', e)
    })
  }

  /** 从请求头文本中提取指定头域值（大小写敏感的头名匹配，找不到返回空串） */
  private static extractHeader(request: string, name: string): string {
    const marker = '\r\n' + name + ':'
    const idx = request.indexOf(marker)
    if (idx < 0) {
      return ''
    }
    const lineEnd = request.indexOf('\r\n', idx + marker.length)
    const line = lineEnd >= 0 ? request.substring(idx + marker.length, lineEnd)
      : request.substring(idx + marker.length)
    return line.trim()
  }

  private static parseQuery(path: string): Record<string, string> {
    const out: Record<string, string> = {}
    const q = path.indexOf('?')
    if (q < 0) {
      return out
    }
    const params = path.substring(q + 1).split('&')
    for (const p of params) {
      const eq = p.indexOf('=')
      if (eq > 0) {
        try {
          out[p.substring(0, eq)] = decodeURIComponent(p.substring(eq + 1))
        } catch (e) {
          // 非法编码忽略该参数
        }
      }
    }
    return out
  }

  private static async serveMedia(client: socket.TCPSocketConnection, target: string, referer: string,
    headOnly: boolean): Promise<void> {
    try {
      const headers: Record<string, string> = {}
      if (referer) {
        headers['Referer'] = referer
      }
      const body = new Uint8Array(await HttpUtils.getBytes(target, headers))
      if (TsStripProxyServer.looksLikeM3u8(body)) {
        const text = util.TextDecoder.create('utf-8').decodeToString(body)
        const rewritten = TsStripProxyServer.rewritePlaylist(text, target, referer)
        Logger.d('TsStripProxyServer', 'm3u8 rewritten: ' + target + ' segments='
          + TsStripProxyServer.countSegments(rewritten) + ' length=' + rewritten.length)
        await TsStripProxyServer.respondText(client, rewritten, headOnly)
      } else {
        const stripped = TsStripProxyServer.stripToTs(body)
        Logger.d('TsStripProxyServer', 'segment ' + (stripped === body ? 'passthrough' : 'stripped')
          + ' bytes=' + body.length + '->' + stripped.length)
        await TsStripProxyServer.respondBytes(client, stripped, headOnly)
      }
    } catch (e) {
      Logger.e('fail', 'TsStripProxyServer serveMedia failed: ' + target, e)
      TsStripProxyServer.respondError(client, 502)
    }
  }

  /** 统计播放列表中的分片行数（非注释、非空行） */
  private static countSegments(text: string): number {
    let count = 0
    const lines = text.split('\n')
    for (const line of lines) {
      const t = line.trim()
      if (t && !t.startsWith('#')) {
        count++
      }
    }
    return count
  }

  private static looksLikeM3u8(body: Uint8Array): boolean {
    const head = [0x23, 0x45, 0x58, 0x54, 0x4D, 0x33, 0x55] // #EXTM3U
    if (body.length < head.length) {
      return false
    }
    for (let i = 0; i < head.length; i++) {
      if (body[i] !== head[i]) {
        return false
      }
    }
    return true
  }

  private static rewritePlaylist(text: string, baseUrl: string, referer: string): string {
    const lines = text.split('\n')
    const out: string[] = []
    for (const line of lines) {
      const t = line.trim()
      if (t && !t.startsWith('#')) {
        out.push(TsStripProxyServer.proxySegmentPath(baseUrl, t, referer))
      } else if (t.startsWith('#EXT-X-KEY:') || t.startsWith('#EXT-X-MAP:')) {
        // AES-128 密钥 / fMP4 初始化段与分片同源防盗链：URI 一并改写走本代理，
        // 否则播放器直连取 key 被 403，解密失败无法播放（密钥为 16 字节随机数据，走代抓透传不受剥壳影响）
        const uriMatch = t.match(/URI="([^"]+)"/)
        if (uriMatch !== null && uriMatch[1] && !uriMatch[1].startsWith('/segment.ts?')) {
          out.push(t.replace(uriMatch[0], 'URI="' + TsStripProxyServer.proxySegmentPath(baseUrl, uriMatch[1], referer) + '"'))
        } else {
          out.push(line)
        }
      } else {
        out.push(line)
      }
    }
    return out.join('\n')
  }

  /**
   * 把基于 m3u8 地址的相对/绝对分片（或密钥）地址解析为绝对地址并包装成本代理路径
   */
  private static proxySegmentPath(baseUrl: string, ref: string, referer: string): string {
    const resolved = TsStripProxyServer.resolveUrl(baseUrl, ref)
    let path = '/segment.ts?u=' + encodeURIComponent(resolved)
    if (referer) {
      path += '&ref=' + encodeURIComponent(referer)
    }
    return path
  }

  /**
   * 相对分片地址基于 m3u8 地址解析为绝对地址（常见三种：绝对、协议相对、路径相对）
   */
  private static resolveUrl(base: string, ref: string): string {
    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      return ref
    }
    const schemeEnd = base.indexOf('://')
    if (schemeEnd < 0) {
      return ref
    }
    if (ref.startsWith('//')) {
      return base.substring(0, schemeEnd) + ':' + ref
    }
    const pathStart = base.indexOf('/', schemeEnd + 3)
    const origin = pathStart >= 0 ? base.substring(0, pathStart) : base
    if (ref.startsWith('/')) {
      return origin + ref
    }
    const baseDirEnd = base.lastIndexOf('/')
    return baseDirEnd >= 0 ? base.substring(0, baseDirEnd + 1) + ref : origin + '/' + ref
  }

  /**
   * 在前 8KB 内寻找 TS 同步头（0x47 以 188 字节为周期三连出现），剥掉伪装前缀；找不到则原样透传
   */
  private static stripToTs(body: Uint8Array): Uint8Array {
    const limit = Math.min(body.length - 376, 8192)
    for (let i = 0; i <= limit; i++) {
      if (body[i] === 0x47 && body[i + 188] === 0x47 && body[i + 376] === 0x47) {
        return i > 0 ? body.slice(i) : body
      }
    }
    return body
  }

  private static async respondText(client: socket.TCPSocketConnection, body: string, headOnly: boolean): Promise<void> {
    try {
      const encoder = new util.TextEncoder()
      const byteLength = encoder.encodeInto(body).byteLength
      const head = 'HTTP/1.1 200 OK' +
        '\r\nContent-Type: application/vnd.apple.mpegurl\r\nConnection: close\r\nContent-Length: '
        + byteLength + '\r\n\r\n'
      await client.send({ data: headOnly ? head : head + body })
      Logger.d('TsStripProxyServer', 'responded playlist' + (headOnly ? ' (head only)' : '')
        + ' bytes=' + byteLength)
      client.close()
    } catch (e) {
      Logger.e('fail', 'TsStripProxyServer respondText failed', e)
    }
  }

  private static async respondBytes(client: socket.TCPSocketConnection, data: Uint8Array,
    headOnly: boolean): Promise<void> {
    try {
      const head = 'HTTP/1.1 200 OK' +
        '\r\nContent-Type: video/mp2t\r\nConnection: close\r\nContent-Length: ' + data.byteLength + '\r\n\r\n'
      await client.send({ data: head })
      if (!headOnly) {
        const CHUNK = 256 * 1024
        for (let off = 0; off < data.length; off += CHUNK) {
          const chunk = data.slice(off, Math.min(off + CHUNK, data.length))
          await client.send({ data: chunk.buffer })
        }
      }
      Logger.d('TsStripProxyServer', 'responded segment' + (headOnly ? ' (head only)' : '')
        + ' bytes=' + data.byteLength)
      client.close()
    } catch (e) {
      Logger.e('fail', 'TsStripProxyServer respondBytes failed', e)
    }
  }

  private static respondError(client: socket.TCPSocketConnection, code: number): void {
    try {
      client.send({ data: 'HTTP/1.1 ' + code + ' Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n' })
        .then((): void => {
          client.close()
        }).catch((e: BusinessError): void => {
          Logger.e('fail', 'TsStripProxyServer respondError send failed', e)
        })
    } catch (e) {
      Logger.e('fail', 'TsStripProxyServer respondError failed', e)
    }
  }
}
