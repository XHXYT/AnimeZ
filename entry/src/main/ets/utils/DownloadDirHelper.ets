import { common } from '@kit.AbilityKit'
import { fileUri, picker } from '@kit.CoreFileKit'
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
 * 公共下载目录 Download/<bundleName>/ 并非静默授权：首次必须经 DocumentViewPicker 的
 * DOWNLOAD 模式（不弹文件选择界面）创建目录并获得持久化 URI 授权，之后 fs 才能按路径
 * 直接读写；未授权前按路径访问会被拒绝，getDownloadDir 回退沙箱保证下载可用。
 */
export class DownloadDirHelper {

  /** 公共下载目录（Download/包名/）的绝对路径 */
  static getPublicDownloadDir(context: common.UIAbilityContext): string {
    const uri = 'file://docs/storage/Users/currentUser/Download/' + context.abilityInfo.bundleName
    return new fileUri.FileUri(uri).path
  }

  /** 同步探测公共下载目录当前是否可直接访问（此前已完成 DOWNLOAD 模式授权）；不可访问返回 '' */
  static probePublicDir(context: common.UIAbilityContext): string {
    const dir = DownloadDirHelper.getPublicDownloadDir(context)
    try {
      if (fs.accessSync(dir)) {
        return dir
      }
    } catch (e) {
      // 无权限或路径不可达
    }
    return ''
  }

  /**
   * 确保公共下载目录可用：已授权则直接返回目录绝对路径；
   * 否则经 DocumentViewPicker DOWNLOAD 模式静默创建 Download/<包名>/ 并获得持久化授权，
   * 返回授权后的目录路径；失败返回空串。
   */
  static async ensurePublicDir(context: common.UIAbilityContext): Promise<string> {
    const dir = DownloadDirHelper.probePublicDir(context)
    if (dir) {
      return dir
    }
    try {
      const saveOptions = new picker.DocumentSaveOptions()
      saveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD
      const documentViewPicker = new picker.DocumentViewPicker(context)
      const result: Array<string> = await documentViewPicker.save(saveOptions)
      if (result.length > 0 && result[0]) {
        const granted = new fileUri.FileUri(result[0]).path
        Logger.i('tips', '公共下载目录 DOWNLOAD 模式授权成功: ' + granted)
        return granted
      }
      return ''
    } catch (e) {
      Logger.e('fail', '公共下载目录授权失败', e)
      return ''
    }
  }

  /** 当前生效的下载根目录（末尾带 /）：配置为公共目录但不可达时回退沙箱，保证下载可用 */
  static getDownloadDir(context: common.UIAbilityContext): string {
    if (appSettings.download_location === DownloadLocationType.PUBLIC) {
      const dir = DownloadDirHelper.probePublicDir(context)
      if (dir) {
        return dir + '/'
      }
    }
    return context.filesDir + '/download/'
  }

  /**
   * 番剧名转安全的文件夹名：替换文件系统非法字符，压缩空白，限长，空名回退
   */
  static sanitizeDirName(name: string): string {
    const sanitized = name.replace(/[\\/:*?"<>|\r\n\t]/g, '_').replace(/\s+/g, ' ').trim().replace(/^\.+$/, '_')
    if (!sanitized) {
      return '未命名'
    }
    return sanitized.length > 80 ? sanitized.substring(0, 80) : sanitized
  }
}
