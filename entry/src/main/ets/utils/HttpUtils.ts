import Logger from './Logger';
import http from '@ohos.net.http';
import { parse } from '../thirdpart/htmlsoup';
import { AnyNode } from '../thirdpart/htmlsoup/parse';

const USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

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
    static async getString(url: string, headers?: object): Promise<string> {
        let httpRequest = http.createHttp()
       // Logger.d('HttpUtils.getString', `已使用 ${url} 创建Http`)

        let header = {
            'user-agent': USER_AGENT
        }
        if (headers) {
            header = Object.assign(header, headers)
        }
       // Logger.d('HttpUtils.getString', '请求头 = ' + JSON.stringify(header))

        const resp: http.HttpResponse = await httpRequest.request(url, {
            method: http.RequestMethod.GET,
            readTimeout: 20000,
            connectTimeout: 20000,
            expectDataType: http.HttpDataType.STRING,
            header: header
        })
        // Logger.d('HttpUtils.getString', `响应Code = ${resp.responseCode}`)
        if (resp.result) {
           Logger.d('HttpUtils.getString', 'resp.result = ' + JSON.stringify(resp.result, null, 2))
           return resp.result as string
        } else {
            throw new Error(resp.responseCode.toString())
        }
    }

}