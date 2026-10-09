import { ImageKnifeComponentV2, ImageKnifeOptionV2, ImageKnife, ImageInfo } from '@ohos/imageknifepro'
import Logger from '../utils/Logger';

/**
 * 网络封面图：基于 ImageKnifePro（独立网络栈 + 磁盘缓存 + 请求队列），
 * 加载失败自动重试（带退避），重试耗尽显示占位图；地址为空直接显示占位图。
 * 重试通过 reload(requestId) 原样重发：对 302 随机节点的图床（如橘子动漫封面）
 * 会重新随机分配节点，重试大概率落到健康节点上。
 * 宽高/圆角等布局属性由调用方链式设置。
 */
@ComponentV2
export struct CoverImage {

  /** 封面地址（空/undefined 显示占位图） */
  @Param imgUrl: string | undefined = undefined
  /** 图片适配模式，默认 Cover */
  @Param imageFit: ImageFit = ImageFit.Cover
  /** 占位/失败兜底图 */
  @Param placeholder: Resource = $r('app.media.pic_load_failed')
  /** 加载失败自动重试次数上限 */
  @Param maxRetry: number = 2
  /** 加载配置（loadSrc @Trace 驱动组件重新加载） */
  @Local option: ImageKnifeOptionV2 = this.buildOption()
  /** 已重试次数 */
  private retryCount: number = 0
  /** 排队中的重试定时器 */
  private retryTimer: number = -1
  /** 待重试的请求 ID */
  private pendingRequestId: string = ''

  aboutToDisappear(): void {
    this.cancelPendingRetry()
  }

  /** 列表项复用地址变化：重置重试状态并重新加载 */
  @Monitor('imgUrl')
  onImgUrlChange(): void {
    this.cancelPendingRetry()
    this.retryCount = 0
    this.option = this.buildOption()
  }

  private buildOption(): ImageKnifeOptionV2 {
    return {
      loadSrc: this.imgUrl ?? '',
      placeholderSrc: this.placeholder,
      errorSrc: this.placeholder,
      objectFit: this.imageFit,
      // 默认 60s 过长：封面加载 15s 内连不上就该换节点重试
      httpOption: { connectTimeout: 15000, readTimeout: 30000 },
      onLoadListener: {
        onLoadFailed: (err: string, imageInfo: ImageInfo) => {
          this.scheduleRetry(imageInfo.requestId)
        }
      }
    }
  }

  private cancelPendingRetry(): void {
    if (this.retryTimer !== -1) {
      clearTimeout(this.retryTimer)
      this.retryTimer = -1
    }
    this.pendingRequestId = ''
  }

  /** 失败后退避重试：第 1 次 500ms、之后 2000ms；同一失败的重复回调由定时器去重 */
  private scheduleRetry(requestId: string): void {
    if (this.retryTimer !== -1) {
      return
    }
    if (this.retryCount >= this.maxRetry) {
      Logger.e('tips', `封面加载失败（已自动重试 ${this.retryCount} 次）: ${this.imgUrl}`)
      return
    }
    const next = this.retryCount + 1
    const delay = next === 1 ? 500 : 2000
    Logger.w('tips', `封面加载失败，${delay}ms 后自动重试 ${next}/${this.maxRetry}: ${this.imgUrl}`)
    this.pendingRequestId = requestId
    this.retryTimer = setTimeout(() => {
      this.retryTimer = -1
      this.retryCount = next
      const id = this.pendingRequestId
      this.pendingRequestId = ''
      if (id !== '') {
        ImageKnife.getInstance().reload(id)
      }
    }, delay)
  }

  build() {
    if (this.imgUrl && this.imgUrl !== '') {
      ImageKnifeComponentV2({ imageKnifeOption: this.option })
        .width('100%')
        .height('100%')
    } else {
      Image(this.placeholder)
        .objectFit(this.imageFit)
        .width('100%')
        .height('100%')
    }
  }
}
