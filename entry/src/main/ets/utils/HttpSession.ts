import Logger from './Logger';
import http from '@ohos.net.http';
import { image } from '@kit.ImageKit';

const USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

/** 响应头原始模型（仅用于承接 set-cookie，字段可能缺失；兼容不同大小写） */
interface HttpResponseHeaderRaw {
  'set-cookie'?: string | string[];
  'Set-Cookie'?: string | string[];
}

/**
 * 带 Cookie 会话的 HTTP 客户端
 * 同一实例的所有请求共享 Cookie（捕获响应 Set-Cookie，后续请求回放 Cookie 头），
 * 用于「搜索 → 获取验证码图片 → 提交验证码 → 重放搜索」这类依赖服务端会话的流程
 */
export default class HttpSession {
  private cookieJar: Map<string, string> = new Map<string, string>();

  /**
   * 从响应头解析并合并 Set-Cookie
   */
  private captureCookies(header: HttpResponseHeaderRaw): void {
    const raw = header['set-cookie'] ?? header['Set-Cookie'];
    if (!raw) {
      return;
    }
    const cookieItems: string[] = Array.isArray(raw)
      ? raw
      // 单个字符串时可能是多个 Cookie 以逗号拼接
      : raw.split(/,(?=[^;]+?=)/);
    cookieItems.forEach((item: string) => {
      const firstPair = item.split(';')[0];
      const eqIndex = firstPair.indexOf('=');
      if (eqIndex > 0) {
        const name = firstPair.substring(0, eqIndex).trim();
        const value = firstPair.substring(eqIndex + 1).trim();
        if (name.length > 0) {
          this.cookieJar.set(name, value);
        }
      }
    });
  }

  /**
   * 拼接当前 Cookie 头
   */
  private buildCookieHeader(): string {
    const pairs: string[] = [];
    this.cookieJar.forEach((value: string, name: string) => {
      pairs.push(`${name}=${value}`);
    });
    return pairs.join('; ');
  }

  /**
   * 发起请求（自动携带/捕获 Cookie）
   */
  private async request(url: string, method: http.RequestMethod, extraData?: string): Promise<http.HttpResponse> {
    const httpRequest = http.createHttp();
    const header: Record<string, string> = {
      'user-agent': USER_AGENT
    };
    const cookie = this.buildCookieHeader();
    if (cookie.length > 0) {
      header['Cookie'] = cookie;
    }
    const options: http.HttpRequestOptions = {
      method: method,
      readTimeout: 20000,
      connectTimeout: 20000,
      header: header
    };
    if (extraData !== undefined) {
      options.extraData = extraData;
    }
    const resp: http.HttpResponse = await httpRequest.request(url, options);
    httpRequest.destroy();
    try {
      const headerRaw = JSON.parse(JSON.stringify(resp.header)) as HttpResponseHeaderRaw;
      this.captureCookies(headerRaw);
    } catch (e) {
      Logger.e('fail', 'HttpSession 捕获Cookie失败', e);
    }
    return resp;
  }

  /**
   * GET 获取文本
   */
  async getString(url: string): Promise<string> {
    const resp = await this.request(url, http.RequestMethod.GET);
    if (resp.result) {
      return resp.result as string;
    }
    throw new Error(resp.responseCode.toString());
  }

  /**
   * POST 获取文本（表单/无明确类型时使用，extraData 为原始请求体字符串）
   */
  async postString(url: string, body?: string): Promise<string> {
    const resp = await this.request(url, http.RequestMethod.POST, body);
    if (resp.result) {
      return resp.result as string;
    }
    throw new Error(resp.responseCode.toString());
  }

  /**
   * GET 获取验证码图片并解码为 PixelMap（请求与文本请求共享同一 Cookie 会话）
   */
  async getImage(url: string): Promise<image.PixelMap> {
    const httpRequest = http.createHttp();
    const header: Record<string, string> = {
      'user-agent': USER_AGENT
    };
    const cookie = this.buildCookieHeader();
    if (cookie.length > 0) {
      header['Cookie'] = cookie;
    }
    const resp: http.HttpResponse = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      readTimeout: 20000,
      connectTimeout: 20000,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      header: header
    });
    httpRequest.destroy();
    try {
      const headerRaw = JSON.parse(JSON.stringify(resp.header)) as HttpResponseHeaderRaw;
      this.captureCookies(headerRaw);
    } catch (e) {
      Logger.e('fail', 'HttpSession 图片响应捕获Cookie失败', e);
    }
    if (!resp.result) {
      throw new Error(`获取验证码图片失败：HTTP ${resp.responseCode}`);
    }
    const source: image.ImageSource = image.createImageSource(resp.result as ArrayBuffer);
    const pixelMap = await source.createPixelMap();
    await source.release();
    return pixelMap;
  }
}
