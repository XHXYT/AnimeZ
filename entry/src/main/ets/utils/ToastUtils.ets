import { promptAction } from "@kit.ArkUI"
import { AsyncCallback } from "@kit.BasicServicesKit"
import { BusinessError } from "@kit.BasicServicesKit";

class ToastUtils {

  UIContext: UIContext | undefined

  initContext(UIContext: UIContext) {
    this.UIContext = UIContext
  }

  showToast(options: promptAction.ShowToastOptions, key?: string){
    try {
      if (!this.UIContext) {
        console.error(`#showToast ${key}: UIContext未初始化`)
        throw new Error('UIContext未初始化')
      }
      this.UIContext.getPromptAction().showToast(options)
    } catch (error) {
      console.error(`${key} 发送通知失败 code: ${error.code} message: ${error.message}`)
    }
  }

  animateTo(value: AnimateParam, event: () => void, key?: string) {
    try {
      if (!this.UIContext) {
        console.error(`#animateTo ${key}: UIContext未初始化`)
        throw new Error('UIContext未初始化')
      }
      this.UIContext.animateTo(value, () => {
        event()
      })
    } catch (error) {
      console.error(`${key} 动画加载失败 code: ${error.code} message: ${error.message}`)
    }
  }

  showDialog(options: promptAction.ShowDialogOptions, callback: AsyncCallback<promptAction.ShowDialogSuccessResponse, void>, key?: string) {
    try {
      if (!this.UIContext) {
        console.error(`#showDialog ${key}: UIContext未初始化`)
        throw new Error('UIContext未初始化')
      }
      this.UIContext.getPromptAction().showDialog(options, callback)
    } catch (error) {
      let message = (error as BusinessError).message
      let code = (error as BusinessError).code
      console.error(`${key} showDialog error code is ${code}, message is ${message}`)
    }
  }

  showAlertDialog(options: AlertDialogParamWithConfirm | AlertDialogParamWithButtons | AlertDialogParamWithOptions, key?: string) {
    try {
      if (!this.UIContext) {
        console.error(`#showAlertDialog ${key}: UIContext未初始化`)
        throw new Error('UIContext未初始化')
      }
      this.UIContext.showAlertDialog(options)
    } catch (error) {
      let message = (error as BusinessError).message
      let code = (error as BusinessError).code
      console.error(`${key} showDialog error code is ${code}, message is ${message}`)
    }
  }

}

export const ToastUtil = new ToastUtils()