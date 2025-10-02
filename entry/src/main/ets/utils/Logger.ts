import hilog from '@ohos.hilog'

const DOMAIN: number = 0xFF00
const PREFIX: string = '[AnimeZ]'
const FORMAT: string = '%{public}s, %{public}s'

/**
 * 日志工具类
 */
export default class Logger {
    /**
     * debug
     */
    static d(tag: any, ...args: string[]) {
        hilog.debug(DOMAIN, PREFIX, FORMAT, this.wrapArgs(tag, args))
    }

    /**
     * info
     */
    static i(tag: any, ...args: string[]) {
        hilog.info(DOMAIN, PREFIX, FORMAT, this.wrapArgs(tag, args))
    }

    /**
     * warn
     */
    static w(tag: any, ...args: string[]) {
        hilog.warn(DOMAIN, PREFIX, FORMAT, this.wrapArgs(tag, args))
    }

    /**
     * error
     */
    static e(type: 'fail' | 'tips' = 'tips', descr?: string, err?: any) {
        if (type === 'fail') {
            hilog.error(DOMAIN, PREFIX, FORMAT, `${descr}失败，code: ${err.code} message: ${err.messsage}`)
        } else {
            hilog.error(DOMAIN, PREFIX, FORMAT, descr)
        }
    }

    /**
     * 将tag转换为字符串
     * 1、如果tag是Object类型，转换为获取构造方法名称
     * 2、如实是Function类型，调用toString
     * 3、其他类型，type+tag拼接
     */
    static wrapArgs(tag: any, args: string[]): string[] {
        let name: string;
        if ((typeof tag) == 'string') {
            name = tag
        } else if ((typeof tag) == 'function') {
            name = tag.name;
        } else if ((typeof tag) == 'object') {
            name = tag.constructor.name;
        } else {
            name = (typeof tag) + '-' + tag;
        }
        if (name) {
            if (args) {
                args.splice(0, 0, name);
            } else {
                args = [name];
            }
        }
        return args;
    }
}