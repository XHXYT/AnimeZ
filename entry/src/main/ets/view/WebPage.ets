import Logger from '../utils/Logger';
import Webview from '@ohos.web.webview';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { GoToWeb } from '../utils/GoOutWeb';
import TitleBar from '../components/TitleBar';
import { AnimeState } from '../entryability/AnimeState';

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

@ComponentV2
struct WebPage {
  @Local title: string = ''
  @Local info: string = ''
  @Local theUA: number = -1
  @Local defaultUserUA: string = ''
  @Local loadingProgress: number = 0
  private readonly controller: Webview.WebviewController = new Webview.WebviewController()
  private url: string | Resource = ''

  build() {
    NavDestination() {
      TitleBar({
        title: this.title,
        subtitle: this.info,
        buttons: [
          { // 刷新
            symbol: 'arrow_clockwise',
            iconSize: 24,
            action: () => {
              try {
                this.controller.refresh()
              } catch (error) {
                Logger.e('fail', '刷新Web页面', error)
              }
            }
          },
          { // 更多
            symbol: 'dot_grid_2x2',
            iconSize: 24,
            needCheckmark: true,
            menuSelected: this.theUA === -1 ? 'ua_default' : this.theUA === 0 ? 'ua_phone' : 'ua_pad',
            menuItems: [
              {
                name: '去浏览器打开',
                value: 'go_web',
                symbolStart: 'safari',
                action: () => {
                  if (typeof this.url === 'string') {
                    GoToWeb(this.url, this.getUIContext().getHostContext()! as common.UIAbilityContext)
                  }
                }
              },
              {
                name: '默认UA',
                value: 'ua_default',
                action: () => {
                  this.setUA(-1, this.defaultUserUA)
                }
              },
              {
                name: '移动端UA',
                value: 'ua_phone',
                action: () => {
                  this.setUA(0, PHONE_USER_AGENT)
                }
              },
              {
                name: '桌面端UA',
                value: 'ua_pad',
                action: () => {
                  this.setUA(1, PAD_USER_AGENT)
                }
              }
            ]
          }
        ]
      })

      if (this.loadingProgress < 100) {
        Progress({ value: this.loadingProgress, total: 100, type: ProgressType.Linear })
          .color($r('app.color.primary_color'))
          .width('100%').height(4)
      }
      Web({ src: this.url, controller: this.controller })
        .javaScriptAccess(true)
        .darkMode(AnimeState.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? WebDarkMode.On : WebDarkMode.Off)
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
    .padding({top: AnimeState.topRectHeight, bottom: AnimeState.bottomRectHeight - 20})
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
          AnimeState.pageStack.pop(true)
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
    .onBackPressed(() => {
      // Web 历史可返回时优先返回上一级网页，否则交还导航栈
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
    })

  }

  private setUA(ua: number, userAgent: string): void {
    this.theUA = ua
    try {
      this.controller.setCustomUserAgent(userAgent)
    } catch (error) {
      Logger.e('fail', '设置自定义UA', error)
    }
    // 刷新网页
    try {
      this.controller.refresh()
    } catch (error) {
      Logger.e('fail', '设置UA后刷新Web页面', error)
    }
  }

}
