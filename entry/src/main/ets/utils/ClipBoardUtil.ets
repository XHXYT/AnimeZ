
import { pasteboard,BusinessError } from '@kit.BasicServicesKit';
import { ToastUtil } from './ToastUtils';

/**
 * 复制工具 From 冲浪喵
 */
export function Copy(content: string) {
  let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
  let pasteData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, content);
  systemPasteboard.setData(pasteData).then(() => {
    console.info('Copy Succeeded in setting PasteData.');
    ToastUtil.showToast({ message: '复制到剪贴板成功' })
  }).catch((err: BusinessError) => {
    console.error('Copy Failed to set PasteData. Cause: ' + err.message);
    ToastUtil.showToast({ message: '复制到剪贴板失败，message：' + err.message})
  })
}