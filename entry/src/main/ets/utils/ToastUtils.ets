import { ComponentContent, promptAction } from "@kit.ArkUI"
import { AsyncCallback } from "@kit.BasicServicesKit"
import { BusinessError } from "@kit.BasicServicesKit";
import { InputCustomDialog } from "../components/dialog/InputDialog";
import { PromptActionClass } from "../entity/PromptActionClass";

class ToastUtils {

  UIContext: UIContext | undefined

  initContext(UIContext: UIContext) {
    this.UIContext = UIContext
    PromptActionClass.setContext(this.UIContext)
    PromptActionClass.setOptions({ alignment: DialogAlignment.Center, offset: { dx: 0, dy: 50 } });
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

  showInputDialog(title: string, placeholder: string, onValueChange: (value: string) => void, textValue?: string, key?: string) {
    if (!this.UIContext) {
      console.error(`#showInputDialog ${key}: UIContext未初始化`)
      throw new Error('UIContext未初始化')
    }
    const contentNode: ComponentContent<Object> =
      new ComponentContent(this.UIContext, wrapBuilder(buildInput), new Params(title, placeholder, onValueChange, textValue));
    PromptActionClass.setContentNode(contentNode)
    PromptActionClass.openDialog()
  }

}

export const ToastUtil = new ToastUtils()

class Params {
  title: string = ''
  textValue?: string = ''
  placeholder: string = ''
  onValueChange: (value: string) => void

  constructor(title: string, placeholder: string, onValueChange: (value: string) => void, textValue?: string) {
    this.title = title;
    this.placeholder = placeholder
    this.textValue = textValue
    this.onValueChange = onValueChange
  }
}

@Builder
function buildInput(params: Params) {
  InputCustomDialog({
    title: params.title,
    placeholder: params.placeholder,
    textValue: params.textValue,
    close: () => {
      PromptActionClass.closeDialog()
    },
    onValueChange: (value) => {
      params.onValueChange(value)
    }
  })
}