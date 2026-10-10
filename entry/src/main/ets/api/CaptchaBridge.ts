import { image } from '@kit.ImageKit';

/** 验证码挑战：携带验证码图片与刷新回调，交给 UI 层展示 */
export interface CaptchaChallenge {
  sourceName: string;                          // 数据源名称（用于弹窗提示）
  pixelMap: image.PixelMap;                    // 验证码图片
  refresh: () => Promise<image.PixelMap>;      // 「换一张」：重新获取验证码图片
}

/** UI 层处理器：展示验证码弹窗，resolve 用户输入的验证码，reject 表示用户取消 */
export type CaptchaHandler = (challenge: CaptchaChallenge) => Promise<string>;

/**
 * 验证码 UI 桥
 * 数据源层（GenericDataSource）通过 prompt 触发验证码输入；
 * 搜索页在 aboutToAppear 注册处理器、aboutToDisappear 注销
 */
export class CaptchaBridge {
  private static handler: CaptchaHandler | null = null;
  /** 串行队列尾部：并发多源同时需要验证码时排队逐个弹窗，避免弹窗互相覆盖导致回调丢失 */
  private static queueTail: Promise<void> = Promise.resolve();

  static register(handler: CaptchaHandler): void {
    CaptchaBridge.handler = handler;
  }

  static unregister(): void {
    CaptchaBridge.handler = null;
  }

  static hasHandler(): boolean {
    return CaptchaBridge.handler !== null;
  }

  /**
   * 请求用户输入验证码（串行：同一时刻只展示一个验证码弹窗，后续挑战排队等待前一个完成）
   * 未注册处理器（当前页面不支持）或用户取消时抛错
   */
  static async prompt(challenge: CaptchaChallenge): Promise<string> {
    if (!CaptchaBridge.handler) {
      throw new Error('当前页面不支持验证码输入');
    }
    const run: Promise<string> = CaptchaBridge.queueTail.then(async (): Promise<string> => {
      if (!CaptchaBridge.handler) {
        throw new Error('当前页面不支持验证码输入');
      }
      return await CaptchaBridge.handler(challenge);
    });
    CaptchaBridge.queueTail = run.then((): void => {}, (): void => {});
    return await run;
  }
}
