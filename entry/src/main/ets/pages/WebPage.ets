import Logger from '../utils/Logger';
import router from '@ohos.router';
import Webview from '@ohos.web.webview';
import { OPTIONS_TRANSITION_POP, OPTIONS_TRANSITION_PUSH } from '../utils/TransitionHelper';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { GoToWeb } from '../utils/GoOutWeb';

// 系统路由
@Builder
export function WebPageBuilder(name: string, param: Object) {
  WebPage()
}

const context = getContext(this) as common.UIAbilityContext
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
  @StorageProp('currentColorMode') currentMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT


  aboutToAppear() {

  }

  onBackPress() {
    if (this.controller.accessBackward()) {
      this.controller.backward()
      return true
    }
    return false
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
            GoToWeb(this.url, context)
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
          this.controller.setCustomUserAgent(this.defaultUserUA)
          // 刷新网页
          this.controller.refresh()
        })
      MenuItem({
        content: '移动端',
        symbolEndIcon: this.theUA === 0 ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
      })
        .onClick(() => {
          this.theUA = 0
          // 移动端UA
          this.controller.setCustomUserAgent(PHONE_USER_AGENT)
          // 刷新网页
          this.controller.refresh()
        })
      MenuItem({
        content: '桌面端',
        symbolEndIcon: this.theUA === 1 ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
      })
        .onClick(() => {
          this.theUA = 1
          // 桌面端UA
          this.controller.setCustomUserAgent(PAD_USER_AGENT)
          // 刷新网页
          this.controller.refresh()
        })
    }
  }


  build() {
    NavDestination() {
      Row({space: 12}) {
        Image($r('app.media.ic_arrow_left'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.color_text_major'))
          .objectFit(ImageFit.Contain)
          .onClick(() => {
            this.pageStack.pop(true)
          })
        Column() {
          Text(this.title)
            .fontColor($r('app.color.color_text_major'))
            .fontSize(16)
            .maxLines(1)
            .fontWeight(500)
            .textOverflow({overflow: TextOverflow.Ellipsis})
            .textAlign(TextAlign.Start)

          Text(this.info)
            .fontColor($r('app.color.color_text_major'))
            .fontSize(10)
            .maxLines(1)
            .textOverflow({overflow: TextOverflow.Ellipsis})
            .margin({top: 4})
            .textAlign(TextAlign.Start)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        // 刷新
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(24)
          .fontColor([$r('app.color.color_text_major')])
          .onClick(() => {
            this.controller.refresh()
          })
        // 更多
        SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
          .fontSize(28)
          .bindMenu(this.MoreMenu())
          .fontColor([$r('app.color.color_text_major')])
      }
      .height(56)
      .width('100%')
      .padding({left: 12, right: 12})
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
          this.defaultUserUA = this.controller.getUserAgent()
        })
        .onTitleReceive((event) => {
          this.title = event.title
        })
        .onProgressChange((event) => {
          this.loadingProgress = event.newProgress
        })
        .onPageBegin(event => {
          Logger.e(this, "onPageBegin url=" + event.url)
          if (!event.url.startsWith('file:')) {
            this.info = event.url
          }
        })
        .onPageEnd(event => {
          let url = event.url
          Logger.e(this, "onPageEnd url=" + url)
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
}