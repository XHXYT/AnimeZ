// WebParseOverlay.ets
// 全局 WebView 解析悬浮层（挂载于 Index 根部，位于 Navigation 与所有页面之上）：
// - 自动模式：1x1 隐藏 WebView，无感解析，不吞点击；
// - 手动模式：底部半模态卡片（遮罩 + 拖拽条 + 状态头 + 网页），等待用户点击站点
//   播放按钮后捕获播放地址；点击遮罩取消本次解析。
// 由 AnimeState.showWebView 条件渲染控制挂载/卸载，空闲时不渲染任何节点、零开销；
// 每次 src 变化都经 false→true 卸载重挂获取全新会话（新凭证）。
// 解析流程驱动方为 utils/WebVideoResolver.ets。
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { AnimeState } from '../entryability/AnimeState';
import { M3U8Sniffer } from '../utils/m3u8/M3U8Sniffer';
import Logger from '../utils/Logger';

/**
 * 全局 WebView 解析悬浮层
 */
@ComponentV2
export struct WebParseOverlay {

  private webviewController: webview.WebviewController = new webview.WebviewController();

  build() {
    if (AnimeState.showWebView) {
      if (AnimeState.webviewManual) {
        this.ManualSheet()
      } else {
        // 自动模式：隐藏 1x1 WebView（尺寸/穿透在 CoreWeb 内按模式切换）
        this.CoreWeb()
      }
    }
  }

  /** 手动模式：底部半模态卡片（遮罩点击取消，与状态头取消按钮一致） */
  @Builder ManualSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 半模态遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .transition(TransitionEffect.OPACITY.animation({ duration: 250 }))
        .onClick(() => {
          AnimeState.webJsVideoLink = 'ERR_MANUAL_CANCEL';
        })

      // 半模态卡片：拖拽条 + 状态头 + 网页
      Column() {
        // 顶部拖拽条装饰
        Column() {
          Row()
            .width(36)
            .height(5)
            .borderRadius(3)
            .backgroundColor('#FFE0E0E0')
            .margin({ top: 8, bottom: 6 })
        }
        .width('100%')
        .backgroundColor(Color.White)
        .alignItems(HorizontalAlign.Center)

        this.ManualHeader()

        this.CoreWeb()
      }
      .width('100%')
      .height('72%')
      .borderRadius({ topLeft: 20, topRight: 20 })
      .clip(true)
      .backgroundColor(Color.White)
      .padding({ bottom: AnimeState.bottomRectHeight })
      .onClick(() => {
        // 消费卡片区域点击，避免透传到下方遮罩误触发取消
      })
      .transition(TransitionEffect.translate({ y: 400 })
        .animation({ duration: 250, curve: Curve.Friction }))
    }
    .width('100%')
    .height('100%')
  }

  /** 手动模式状态头部：当前状态 + 需要用户辅助的操作类型 + 取消 */
  @Builder ManualHeader() {
    Column() {
      Row() {
        Column() {
          Text('需要手动辅助解析')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF1F1F1F')
          Text(AnimeState.webviewManualReason)
            .fontSize(11)
            .fontColor('#FF888888')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        LoadingProgress()
          .width(20)
          .height(20)
          .color('#FF007DFF')
          .margin({ right: 10 })

        Button('取消')
          .fontSize(14)
          .height(32)
          .padding({ left: 14, right: 14 })
          .backgroundColor('rgba(0,0,0,0.05)')
          .fontColor('#FF1F1F1F')
          .onClick(() => {
            AnimeState.webJsVideoLink = 'ERR_MANUAL_CANCEL';
          })
      }
      .width('100%')
      .padding({ left: 16, top: 8, right: 12, bottom: 6 })

      Text('▶ 请在网页中点击播放按钮，应用将自动捕获播放地址并继续')
        .fontSize(12)
        .fontColor('#FF007DFF')
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
    }
    .width('100%')
    .backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Start)
  }

  /** WebView 主体（自动/手动模式共用；自动 1x1 隐藏不吞点击，手动填满卡片剩余空间） */
  @Builder CoreWeb() {
    Web({ src: AnimeState.webviewUrl, controller: this.webviewController })
      .backgroundColor(AnimeState.webviewManual ? Color.White : Color.Transparent)
      .onControllerAttached(() => {
        // controller 绑定后注册网络层嗅探（纯旁路，不拦截任何请求）
        M3U8Sniffer.attach(this.webviewController)
      })
      .javaScriptAccess(true)
      .javaScriptProxy({
        object: {
          onLink: (link: string): void => {
            console.info(`animeBridge.onLink: ${link}`);
            AnimeState.webJsVideoLink = link;
          }
        },
        name: 'animeBridge',
        methodList: ['onLink'],
        controller: this.webviewController
      })
      .width(AnimeState.webviewManual ? '100%' : 1)
      .height(AnimeState.webviewManual ? '86%' : 1)
      .layoutWeight(AnimeState.webviewManual ? 1 : 0)
      .hitTestBehavior(AnimeState.webviewManual ? HitTestMode.Default : HitTestMode.None)
      .onPageBegin((event) => {
        console.log(`链接 ${event.url} 成功加载`)
      })
      .onPageEnd(e => {
        try {
          if (e) {
            Logger.e('tips', `URL ${e.url} 开始加载JavaScript`)
            // 手动模式下尽快安装钩子（避免错过用户点击触发的站点自身解析）；自动模式延迟等待页面就绪
            const injectDelay = AnimeState.webviewManual ? 800 : 3000;
            setTimeout(() => {
              // TODO 待修复 webviewController 未绑定上或者绑定了多个 Web 组件
              // 注意：页面销毁后 Web 组件解绑，runJavaScript 会同步抛 17100001，
              // .catch 捕获不到同步异常，必须在回调内部 try-catch
              try {
                this.webviewController.runJavaScript(AnimeState.runJs)
                  .then((result) => {
                    if (!AnimeState.webviewManual) {
                      console.info(`URL ${e.url} 执行 result: ${result}`)
                      // 兼容两种返回：runJavaScript 结果可能为原始字符串或 JSON 编码字符串
                      let link: string = result
                      try {
                        const parsed: string = JSON.parse(result)
                        if (parsed !== '') {
                          link = parsed
                        }
                      } catch (err) {
                        // result 非合法 JSON 时按原始字符串处理
                      }
                      if (link === 'PENDING') {
                        // 源 JS 已安装异步钩子（如嗅探 m3u8 请求），结果稍后经 animeBridge.onLink 回传，继续轮询等待
                        console.info(`URL ${e.url} JS返回PENDING，等待异步桥回传播放地址`)
                      } else {
                        AnimeState.webJsVideoLink = link
                        AnimeState.showWebView = false
                        console.info(`URL ${e.url} 显示状态: ${AnimeState.showWebView} 解析后链接：${AnimeState.webJsVideoLink}`)
                      }
                    } else {
                      // 手动模式：结果经 animeBridge 桥回传，此处仅确认钩子安装
                      console.info(`URL ${e.url} 手动模式钩子已安装: ${result}`)
                    }
                  })
                  .catch((error: BusinessError) => {
                    Logger.e('fail', '加载JavaScript', error)
                  })
              } catch (error) {
                Logger.e('fail', '页面已销毁，跳过JS注入', error)
              }
            }, injectDelay)
          }
        } catch (error) {
          Logger.e('fail', 'webviewController 加载JavaScript', error)
        }
      })
  }
}
