
import TitleBar from '../components/TitleBar'
import { AnimeState } from '../entryability/AnimeState';
import { CustomListItem } from '../components/CustomListItem';
import { CustomItemInfo, ItemActionType } from '../entity/CusItemInfo';
import { ToastUtil } from '../utils/ToastUtils';

/** 关于作者页分组（头部信息 + 通用行） */
interface AuthorSection {
  key: string
  title: string
  introduce: string
  image: ResourceStr
  items: CustomItemInfo[]
}

// 系统路由 - 关于作者
@Builder
export function AboutMePageBuilder(name: string, param: string) {
  AboutMePage()
}

@ComponentV2
struct AboutMePage {

  private aboutMe: AuthorSection[] = [
    {
      key: 'zpj',
      title: '原作者',
      introduce: '开源鸿蒙应用开发爱好者，为开源鸿蒙应用生态作出微薄的贡献',
      image: $rawfile('zpj.png'),
      items: [
        new CustomItemInfo({
          id: 'raw_author_github',
          title: 'Github主页',
          subtitle: 'https://github.com/Z-P-J',
          icon: $r('app.media.ic_github'),
          type: ItemActionType.NONE,
          onChange: () => {
            AnimeState.pageStack.pushPathByName("WebPage", "https://github.com/Z-P-J")
          }
        }),
        new CustomItemInfo({
          id: 'raw_author_gitee',
          title: 'Gitee主页',
          subtitle: 'https://gitee.com/z-p-j',
          icon: $r('app.media.ic_gitee'),
          type: ItemActionType.NONE,
          onChange: () => {
            AnimeState.pageStack.pushPathByName("WebPage", "https://gitee.com/z-p-j")
          }
        }),
        new CustomItemInfo({
          id: 'support_raw_author',
          title: '赞助作者',
          subtitle: '赞助作者一杯咖啡',
          icon: $r('app.media.ic_java'),
          type: ItemActionType.NONE,
          onChange: () => {
            ToastUtil.showToast({ message: '该功能暂未实现，感谢您的支持！' }, 'AboutMePage')
          }
        }),
      ]
    },
    {
      key: 'ya',
      title: '维护者',
      introduce: '鸿蒙应用开发爱好者，一只代码小白',
      image: $rawfile('ya.png'),
      items: [
        new CustomItemInfo({
          id: 'new_author_github',
          title: 'Github主页',
          subtitle: 'https://github.com/XHXYT',
          icon: $r('app.media.ic_github'),
          type: ItemActionType.NONE,
          onChange: () => {
            AnimeState.pageStack.pushPathByName("WebPage", "https://github.com/XHXYT")
          }
        }),
        new CustomItemInfo({
          id: 'new_author_gitee',
          title: 'Gitee主页',
          subtitle: 'https://gitee.com/DXHXYT',
          icon: $r('app.media.ic_gitee'),
          type: ItemActionType.NONE,
          onChange: () => {
            AnimeState.pageStack.pushPathByName("WebPage", "https://gitee.com/DXHXYT")
          }
        }),
        new CustomItemInfo({
          id: 'support_new_author',
          title: '赞助作者',
          subtitle: '赞助作者一杯咖啡',
          icon: $r('app.media.ic_java'),
          type: ItemActionType.NONE,
          onChange: () => {
            ToastUtil.showToast({ message: '该功能暂未实现，感谢您的支持！' }, 'AboutMePage')
          }
        }),
      ]
    },
    {
      key: 'summer',
      title: '维护者',
      introduce: '鸿蒙应用开发爱好者',
      image: $rawfile('summer_kaze.jfif'),
      items: [
        new CustomItemInfo({
          id: 'summer_author_github',
          title: 'Github主页',
          subtitle: 'https://github.com/SummerKaze',
          icon: $r('app.media.ic_github'),
          type: ItemActionType.NONE,
          onChange: () => {
            AnimeState.pageStack.pushPathByName("WebPage", "https://github.com/SummerKaze")
          }
        }),
        new CustomItemInfo({
          id: 'summer_author_gitee',
          title: 'Gitee主页',
          subtitle: 'https://gitee.com/SummerKaze',
          icon: $r('app.media.ic_gitee'),
          type: ItemActionType.NONE,
          onChange: () => {
            AnimeState.pageStack.pushPathByName("WebPage", "https://gitee.com/SummerKaze")
          }
        }),
        new CustomItemInfo({
          id: 'support_summer_author',
          title: '赞助作者',
          subtitle: '赞助作者一杯咖啡',
          icon: $r('app.media.ic_java'),
          type: ItemActionType.NONE,
          onChange: () => {
            ToastUtil.showToast({ message: '该功能暂未实现，感谢您的支持！' }, 'AboutMePage')
          }
        }),
      ]
    }
  ]

  build() {
    NavDestination() {
      TitleBar({title: '关于作者'})

      Scroll() {
        Column({space: 5}) {
          // 关于作者详情
          ForEach(
            this.aboutMe,
            (group: AuthorSection, index) => {
              Image(group.image)
                .height(64)
                .width(64)
                .margin({top: 56})
                .borderRadius(100)
                .shadow({ radius: 12, color: AnimeState.darkModeImage ? '#333333' : '#aaaaaa', offsetX: 6, offsetY: 6 })
              Text(group.title)
                .fontSize(18)
                .fontColor($r('app.color.color_text_major'))
                .fontWeight(500)
                .padding({ top: 12 })
              Text(group.introduce)
                .fontSize(14)
                .fontColor($r('app.color.color_text_major'))
                .margin({ top: 8, bottom: 56 })
                .textAlign(TextAlign.Center)
                .constraintSize({
                  maxWidth: '80%'
                })
              Column() {
                if (group.title) {
                  Row() {
                    Row()
                      .backgroundColor($r('app.color.primary_color'))
                      .height(14)
                      .width(6)
                      .margin({ right: 2 })
                      .borderRadius(4)
                    Text(group.title)
                      .fontColor($r('app.color.color_text_major'))
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                    Blank()
                  }
                  .padding({ left: 16, top: 16, right: 16, bottom: 8 })
                  .width('100%')
                }

                ForEach(
                  group.items,
                  (item: CustomItemInfo) => {
                    CustomListItem({
                      item: item,
                      itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
                    })
                  }, (item: CustomItemInfo) => item.id)
              }
              .backgroundColor($r('app.color.background_color'))
              .borderRadius(16)

              if (index < this.aboutMe.length - 1) {
                Blank().height(16)
              }
            },
            // 唯一键生成
            (group: AuthorSection) => group.key
          )
        }
        .padding(16)
        .width('100%')
        .constraintSize({
          minHeight: '100%'
        })
      }
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
    }
    .padding({top: AnimeState.topRectHeight - 20, bottom: AnimeState.bottomRectHeight - 20})
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
  }
}
