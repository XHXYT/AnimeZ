import { Downloader } from './Downloader';
import Logger from '../Logger'
import Globals from '../Globals'

/**
 * ZDownloader，管理所有下载器
 * @author Z-P-J
 */
export class ZDownloader {

    /**
     * 根据下载器的类创建或获取全局唯一的下载器
     * @param clazz
     */
    static get<T extends Downloader>(clazz: { new(): T }): T {
        Logger.d(this, 'get clazz type=' + (typeof clazz))
        return Globals.getOrCreate('downloader_' + clazz.name, () => {
            return new clazz();
        })
    }
}