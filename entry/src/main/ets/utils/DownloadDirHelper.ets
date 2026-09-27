import { common } from '@kit.AbilityKit'
import { fileUri } from '@kit.CoreFileKit'
import fs from '@ohos.file.fs'
import Logger from './Logger'
import { appSettings } from '../entryability/Settings'

/** 下载保存位置：sandbox=应用沙箱目录 public=公共下载目录(Download/包名/) */
export enum DownloadLocationType {
  SANDBOX = 'sandbox',
  PUBLIC = 'public'
}

/**
 * 下载目录解析：按设置返回新任务的下载根目录。
 * 公共下载目录为系统静默授权：应用可直接访问 Download/<bundleName>/（file://docs/storage/Users/currentUser/Download/<bundleName>），
 * 目录不存在时创建，无需申请权限或拉起选择器。
 */
export class DownloadDirHelper {

  /** 公共下载目录（Download/包名/）的绝对路径 */
  static getPublicDownloadDir(context: common.UIAbilityContext): string {
    const uri = 'file://docs/storage/Users/currentUser/Download/' + context.abilityInfo.bundleName
    return new fileUri.FileUri(uri).path
  }

  /** 确保公共下载目录可用（不存在则创建），返回目录绝对路径；失败返回空串 */
  static ensurePublicDir(context: common.UIAbilityContext): string {
    const dir = DownloadDirHelper.getPublicDownloadDir(context)
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir)
      }
      return dir
    } catch (e) {
      Logger.e('fail', '公共下载目录不可用: ' + dir, e)
      return ''
    }
  }

  /** 当前生效的下载根目录（末尾带 /）：配置为公共目录但不可达时回退沙箱，保证下载可用 */
  static getDownloadDir(context: common.UIAbilityContext): string {
    if (appSettings.download_location === DownloadLocationType.PUBLIC) {
      const dir = DownloadDirHelper.ensurePublicDir(context)
      if (dir) {
        return dir + '/'
      }
    }
    return context.filesDir + '/download/'
  }
}
