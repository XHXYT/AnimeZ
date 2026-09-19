import { ToastUtil } from '../../utils/ToastUtils';

interface ShareItem {
  name: string,
  icons: Resource,
  onClick: () => void
}

/**
 * 自定义分享弹窗
 */
@ComponentV2
export struct ShareDialog {

  /**
   * 关闭弹窗回调
   */
  @Event onClose: () => void = () => {}

  /**
   * 分享选项
   */
  private readonly shareItems: ShareItem[] = [
    { name: 'QQ', icons: $r('app.media.ic_share_qq'),
      onClick: () => {
        ToastUtil.showToast({ message: 'TODO 分享到QQ'})
      }
    },
    { name: 'QQ空间', icons: $r('app.media.ic_share_qqzone'),
      onClick: () => {
        ToastUtil.showToast({ message: 'TODO 分享到QQ空间'})
      }
    },
    { name: '新浪', icons: $r('app.media.ic_share_sina'),
      onClick: () => {
        ToastUtil.showToast({ message: 'TODO 分享到新浪微博'})
      }
    },
    { name: '微信', icons: $r('app.media.ic_share_wechat'),
      onClick: () => {
        ToastUtil.showToast({ message: 'TODO 分享到微信'})
      }
    },
    { name: '朋友圈', icons: $r('app.media.ic_share_friends'),
      onClick: () => {
        ToastUtil.showToast({ message: 'TODO 分享到朋友圈'})
      }
    },
    { name: '链接分享', icons: $r('app.media.ic_share_link'),
      onClick: () => {
        ToastUtil.showToast({ message: 'TODO 分享链接'})
      }
    }
  ]

  build() {
    Column({space: 16}) {
      Row() {
        Text('分享')
          .fontSize(18)
          .fontColor($r('app.color.color_text_major'))
          .fontWeight(FontWeight.Bold)
          .alignSelf(ItemAlign.Start)
        Blank()
        Image($r('app.media.ic_close'))
          .width(24).height(24)
          .onClick(this.onClose)
      }
      .width('100%')

      Flex({
        alignItems: ItemAlign.Start,
        justifyContent: FlexAlign.SpaceAround,
        wrap: FlexWrap.Wrap,
        alignContent: FlexAlign.SpaceBetween
      }) {
        ForEach(this.shareItems, (item: ShareItem) => {
          if (item) {
            Stack() {
              Image(item.icons)
                .width(36)
                .height(36)
            }
            .backgroundColor($r('app.color.background_color_accent'))
            .padding(16)
            .borderRadius(16)
            .margin({ top: 8, bottom: 8 })
            .onClick(item.onClick)
          } else {
            Stack()
              .width(68)
              .height(68)
              .margin({ top: 8, bottom: 8 })
          }
        })
      }


    }
    .backgroundColor($r('app.color.background_color'))
    .padding(24)
    .borderRadius({
      topLeft: 24, topRight: 24
    })
    .width('100%')
  }
}
