import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import Logger from '../Logger';

/**
 * 本地播放列表 HTTP 服务：mpv 播放后端对本地 m3u8 文件解析异常（只识别第一个分片），
 * 改由 127.0.0.1 临时 HTTP 服务下发过滤后的播放列表，使播放器走与远端完全一致的
 * HTTP 加载路径。进程内单例，随进程存活。
 */
export default class LocalPlaylistServer {
  private static server: socket.TCPSocketServer | null = null
  private static port: number = -1
  private static readonly playlists: Record<string, string> = {}

  /**
   * 注册播放列表内容，返回可播放的本地 HTTP 地址；服务不可用时返回空串
   */
  static async register(content: string, key: string): Promise<string> {
    try {
      await LocalPlaylistServer.ensureServer()
      if (LocalPlaylistServer.port <= 0 || !LocalPlaylistServer.server) {
        return ''
      }
      const path = '/' + key + '.m3u8'
      LocalPlaylistServer.playlists[path] = content
      return 'http://127.0.0.1:' + LocalPlaylistServer.port + path
    } catch (e) {
      Logger.e('fail', 'LocalPlaylistServer register failed', e)
      return ''
    }
  }

  private static ensureServer(): Promise<void> {
    if (LocalPlaylistServer.server) {
      return Promise.resolve()
    }
    return new Promise<void>((resolve: () => void) => {
      const server = socket.constructTCPSocketServerInstance()
      server.on('connect', (client: socket.TCPSocketConnection) => {
        LocalPlaylistServer.handleClient(client)
      })
      LocalPlaylistServer.tryListen(server, 0, resolve)
    })
  }

  private static tryListen(server: socket.TCPSocketServer, attempt: number, onDone: () => void): void {
    const port = 20000 + Math.floor(Math.random() * 20000)
    server.listen({ address: '127.0.0.1', port: port }).then((): void => {
      LocalPlaylistServer.server = server
      LocalPlaylistServer.port = port
      Logger.d('LocalPlaylistServer', 'listening 127.0.0.1:' + port)
      onDone()
    }).catch((e: BusinessError): void => {
      Logger.e('fail', 'LocalPlaylistServer listen ' + port + ' failed', e)
      if (attempt >= 8) {
        onDone()
        return
      }
      LocalPlaylistServer.tryListen(server, attempt + 1, onDone)
    })
  }

  private static handleClient(client: socket.TCPSocketConnection): void {
    let served = false
    client.on('message', (info: socket.SocketMessageInfo): void => {
      if (served) {
        return
      }
      served = true
      let request = ''
      try {
        request = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(info.message))
      } catch (e) {
        Logger.e('fail', 'LocalPlaylistServer decode request failed', e)
        LocalPlaylistServer.respond(client, '', '')
        return
      }
      const lineEnd = request.indexOf('\r\n')
      const firstLine = lineEnd >= 0 ? request.substring(0, lineEnd) : request
      const parts = firstLine.split(' ')
      const path = parts.length >= 2 ? parts[1] : ''
      LocalPlaylistServer.respond(client, path, LocalPlaylistServer.playlists[path] ?? '')
    })
  }

  private static respond(client: socket.TCPSocketConnection, path: string, body: string): void {
    const status = body.length > 0 ? '200 OK' : '404 Not Found'
    Logger.d('LocalPlaylistServer', 'GET ' + path + ' -> ' + status + ' chars=' + body.length)
    try {
      const encoder = new util.TextEncoder()
      const head = 'HTTP/1.1 ' + status +
        '\r\nContent-Type: application/vnd.apple.mpegurl\r\nConnection: close\r\nContent-Length: '
      const payload = head + encoder.encodeInto(body).byteLength + '\r\n\r\n' + body
      client.send({ data: payload }).then((): void => {
        client.close()
      }).catch((e: BusinessError): void => {
        Logger.e('fail', 'LocalPlaylistServer send failed', e)
      })
    } catch (e) {
      Logger.e('fail', 'LocalPlaylistServer respond error', e)
    }
  }
}
