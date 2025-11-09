import Logger from '../utils/Logger';
import Webview from '@ohos.web.webview';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { GoToWeb } from '../utils/GoOutWeb';
import TitleBar from '../components/TitleBar';

// 系统路由
@Builder
export function WebPageBuilder(name: string, param: Object) {
  WebPage()
}

// User Agent modification from westinyang
const PAD_USER_AGENT: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTMl, like Gecko) Chrome/99.0.4844.88 Safari/537.36'
const PHONE_USER_AGENT: string =
  'Mozilla/5.0 (Linux; Android 10.0; ohos) AppleWebKit/537.36 (KHTMl, like Gecko) Chrome/99.0.4844.88 HuaweiBrowser/13.0.4.302 Mobile Safari/537.36'

@Component
struct WebPage {
  @State title: string = ''
  @State info: string = ''
  @State theUA: number = -1
  @State defaultUserUA: string = ''
  @State loadingProgress: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  // 顶部避让高度
  @StorageProp('topRectHeight') topHeight: number = 0
  // 底部避让高度
  @StorageProp('bottomRectHeight') bottomHeight: number = 0
  private readonly controller: Webview.WebviewController = new Webview.WebviewController()
  private url: string | Resource = ''
  @StorageLink('currentColorMode') currentMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT

  build() {
    NavDestination() {
      TitleBar({
        title: this.title,
        subtitle: this.info,
        button: () => {
          this.FunctionButton()
        }
      })

      if (this.loadingProgress < 100) {
        Progress({ value: this.loadingProgress, total: 100, type: ProgressType.Linear })
          .color($r('app.color.primary_color'))
          .width('100%').height(4)
      }
      Web({ src: this.url, controller: this.controller })
        .javaScriptAccess(true)
        .darkMode(this.currentMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? WebDarkMode.On : WebDarkMode.Off)
        .backgroundColor($r('app.color.background_color_accent'))
        .forceDarkAccess(true)
        .onControllerAttached(() => {
          console.log("WebTest #onControllerAttached")
          try {
            this.defaultUserUA = this.controller.getUserAgent()
          } catch (error) {
            Logger.e('fail', '获取用户当前UA', error)
          }
        })
        .onTitleReceive((event) => {
          this.title = event.title
        })
        .onProgressChange((event) => {
          this.loadingProgress = event.newProgress
        })
        .onPageBegin(event => {
          Logger.d(this, "onPageBegin url=" + event.url)
          if (!event.url.startsWith('file:')) {
            this.info = event.url
          }
        })
        .onPageEnd(event => {
          let url = event.url
          Logger.d(this, "onPageEnd url=" + url)
        })
        .width('100%')
        .layoutWeight(1)

    }
    .padding({top: this.topHeight - 20, bottom: this.bottomHeight - 20})
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
    .onReady((ctx: NavDestinationContext) => {
      // 在NavDestination中能够拿到传来的NavPathInfo和当前所处的NavPathStack
      try {
        const url: string = ctx?.pathInfo?.param as string
        if (!url) {
          this.pageStack.pop(true)
          return
        }

        if (url.startsWith('http')) {
          this.url = url
        } else {
          this.url = $rawfile(url)
        }
        this.title = url
        this.info = this.title
      } catch (e) {
        console.log(`testTag onReady catch exception: ${JSON.stringify(e)}`)
      }
    })

  }

  @Builder
  MoreMenu() {
    Menu() {
      MenuItem({
        content: '去浏览器打开',
        symbolEndIcon: new SymbolGlyphModifier($r('sys.symbol.chevron_right'))
      })
        .enabled(typeof this.url === 'string')
        .onClick((selected) => {
          if (typeof this.url === 'string') {
            GoToWeb(this.url, this.getUIContext().getHostContext()! as common.UIAbilityContext)
          }
        })
      MenuItem({
        builder: ():void => this.UAMenu(),
        content: '切换UA',
        symbolEndIcon: new SymbolGlyphModifier($r('sys.symbol.chevron_right'))
      })
        .enabled(typeof this.url === 'string')
    }
  }
  @Builder
  UAMenu() {
    Menu() {
      MenuItem({ content: 'UA' })
        .contentFont({ weight: FontWeight.Bold })
      MenuItem({
        content: '默认',
        symbolEndIcon: this.theUA === -1 ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
      })
        .onClick(() => {
          this.theUA = -1
          // 默认UA
          try {
            this.controller.setCustomUserAgent(this.defaultUserUA)
          } catch (error) {
            Logger.e('fail', '加载默认UA', error)
          }
          // 刷新网页
          try {
            this.controller.refresh()
          } catch (error) {
            Logger.e('fail', '设置默认UA后刷新Web页面', error)
          }
        })
      MenuItem({
        content: '移动端',
        symbolEndIcon: this.theUA === 0 ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
      })
        .onClick(() => {
          this.theUA = 0
          // 移动端UA
          try {
            this.controller.setCustomUserAgent(PHONE_USER_AGENT)
          } catch (error) {
            Logger.e('fail', '加载移动端UA', error)
          }
          // 刷新网页
          try {
            this.controller.refresh()
          } catch (error) {
            Logger.e('fail', '设置移动端UA后刷新Web页面', error)
          }
        })
      MenuItem({
        content: '桌面端',
        symbolEndIcon: this.theUA === 1 ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
      })
        .onClick(() => {
          this.theUA = 1
          // 桌面端UA
          try {
            this.controller.setCustomUserAgent(PAD_USER_AGENT)
          } catch (error) {
            Logger.e('fail', '加载桌面端UA', error)
          }
          // 刷新网页
          try {
            this.controller.refresh()
          } catch (error) {
            Logger.e('fail', '设置桌面端UA后刷新Web页面', error)
          }
        })
    }
  }

  @Builder
  FunctionButton() {
    // 刷新
    SymbolGlyph($r('sys.symbol.arrow_clockwise'))
      .fontSize(24)
      .fontColor([$r('app.color.color_text_major')])
      .onClick(() => {
        try {
          this.controller.refresh()
        } catch (error) {
          Logger.e('fail', '刷新Web页面', error)
        }
      })
    // 更多
    SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
      .fontSize(28)
      .margin({ left: 12 })
      .bindMenu(this.MoreMenu())
      .fontColor([$r('app.color.color_text_major')])
  }

  onBackPress() {
    try {
      if (this.controller.accessBackward()) {
        try {
          this.controller.backward()
        } catch (error) {
          Logger.e('fail', 'Web页面返回', error)
        }
        return true
      }
    } catch (error) {
      Logger.e('fail', '检查Web是否可以返回页面', error)
    }
    return false
  }

}