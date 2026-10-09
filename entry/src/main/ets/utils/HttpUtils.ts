import http from '@ohos.net.http';
import { parse } from './thirdpart/htmlsoup';
import { AnyNode } from './thirdpart/htmlsoup/parse';

const USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

/** JSON POST 完整响应（postJsonFull 返回）：响应文本 + 原始 Set-Cookie 列表 */
export interface HttpFullResponse {
    text: string;
    setCookies: string[];
}

/**
 * 网络工具类
 */
export default class HttpUtils {

    /**
     * 获取网页内容，转换为Document对象
     * @param url
     */
    static async getHtml(url: string, headers?: object): Promise<AnyNode> {
        const str = await this.getString(url, headers)
        if (str) {
           // Logger.d('tips', 'HttpUtils.getHtml 解析前str = ' + str)
            return parse(str)
        } else {
            throw new Error("content is empty!")
        }
    }

    /**
     * 获取网页内容
     * @param url
     */
    /**
     * URL 规范化：非 ASCII 字符（如中文查询参数）百分号编码。
     * http 模块与 AVPlayer 均要求编码后的 URL，原始中文会直接抛错；
     * encodeURI 不动 & = ? / : 与已有 %XX，不会二次编码。
     */
    static normalizeUrl(url: string): string {
        return /[^\x00-\x7F]/.test(url) ? encodeURI(url) : url
    }

    static async getString(url: string, headers?: object): Promise<string> {
        try {
            return await HttpUtils.doGetString(url, headers)
        } catch (e) {
            // http 明文链接可能已被站点弃用（80 端口失联导致连接超时），失败时升级 https 重试一次
            if (url.startsWith('http://')) {
                return await HttpUtils.doGetString('https://' + url.substring('http://'.length), headers)
            }
            throw e
        }
    }

    private static async doGetString(url: string, headers?: object): Promise<string> {
        let httpRequest = http.createHttp()
       // Logger.d('HttpUtils.getString', `已使用 ${url} 创建Http`)

        let header = {
            'user-agent': USER_AGENT
        }
        if (headers) {
            header = Object.assign(header, headers)
        }
       // Logger.d('HttpUtils.getString', '请求头 = ' + JSON.stringify(header))

        const resp: http.HttpResponse = await httpRequest.request(HttpUtils.normalizeUrl(url), {
            method: http.RequestMethod.GET,
            readTimeout: 20000,
            connectTimeout: 20000,
            expectDataType: http.HttpDataType.STRING,
            header: header
        })
        httpRequest.destroy()
        if (resp.result) {
            return resp.result as string
        } else {
            throw new Error(resp.responseCode.toString())
        }
    }

    /**
     * 获取二进制响应体（如视频分片），可带自定义请求头（如 Referer）
     */
    static async getBytes(url: string, headers?: object): Promise<ArrayBuffer> {
        let httpRequest = http.createHttp()
        let header = {
            'user-agent': USER_AGENT
        }
        if (headers) {
            header = Object.assign(header, headers)
        }
        const resp: http.HttpResponse = await httpRequest.request(HttpUtils.normalizeUrl(url), {
            method: http.RequestMethod.GET,
            connectTimeout: 15000,
            readTimeout: 30000,
            expectDataType: http.HttpDataType.ARRAY_BUFFER,
            header: header
        })
        httpRequest.destroy()
        if (resp.result) {
            return resp.result as ArrayBuffer
        }
        throw new Error('HTTP ' + resp.responseCode)
    }

    /**
     * 发送 JSON POST 请求，返回响应文本
     * @param url 请求地址
     * @param body JSON 字符串请求体
     * @param headers 额外请求头
     */
    static async postJson(url: string, body: string, headers?: object): Promise<string> {
        let httpRequest = http.createHttp()

        let header = {
            'user-agent': USER_AGENT,
            'content-type': 'application/json'
        }
        if (headers) {
            header = Object.assign(header, headers)
        }

        const resp: http.HttpResponse = await httpRequest.request(url, {
            method: http.RequestMethod.POST,
            readTimeout: 20000,
            connectTimeout: 20000,
            expectDataType: http.HttpDataType.STRING,
            header: header,
            extraData: body
        })
        httpRequest.destroy()
        if (resp.result) {
            return resp.result as string
        } else {
            throw new Error(resp.responseCode.toString())
        }
    }

    /**
     * JSON POST 完整响应：响应文本 + 响应 Set-Cookie 列表，
     * 用于 cookie 登录（登录成功后从响应头捕获会话 Cookie）
     */
    static async postJsonFull(url: string, body: string, headers?: object): Promise<HttpFullResponse> {
        let httpRequest = http.createHttp()

        let header = {
            'user-agent': USER_AGENT,
            'content-type': 'application/json'
        }
        if (headers) {
            header = Object.assign(header, headers)
        }

        const resp: http.HttpResponse = await httpRequest.request(url, {
            method: http.RequestMethod.POST,
            readTimeout: 20000,
            connectTimeout: 20000,
            expectDataType: http.HttpDataType.STRING,
            header: header,
            extraData: body
        })
        httpRequest.destroy()
        const setCookies: string[] = [];
        const raw = resp.header['set-cookie'] ?? resp.header['Set-Cookie'];
        if (raw) {
            const cookieItems: string[] = Array.isArray(raw)
                ? raw
                // 单个字符串时可能是多个 Cookie 以逗号拼接
                : raw.split(/,(?=[^;]+?=)/);
            cookieItems.forEach((item: string) => {
                if (item && item.trim().length > 0) {
                    setCookies.push(item);
                }
            });
        }
        const text = resp.result ? resp.result as string : '';
        if (!text && setCookies.length === 0) {
            throw new Error(resp.responseCode.toString());
        }
        return { text: text, setCookies: setCookies };
    }

    /**
     * 发送 DELETE 请求，返回响应文本
     * @param url 请求地址
     * @param headers 额外请求头
     */
    static async deleteRequest(url: string, headers?: object): Promise<string> {
        let httpRequest = http.createHttp()

        let header = {
            'user-agent': USER_AGENT
        }
        if (headers) {
            header = Object.assign(header, headers)
        }

        const resp: http.HttpResponse = await httpRequest.request(url, {
            method: http.RequestMethod.DELETE,
            readTimeout: 20000,
            connectTimeout: 20000,
            expectDataType: http.HttpDataType.STRING,
            header: header
        })
        httpRequest.destroy()
        if (resp.result) {
            return resp.result as string
        } else {
            throw new Error(resp.responseCode.toString())
        }
    }

}