
import { CustomItemInfo, ItemActionType } from '../entity/CusItemInfo';
import { CustomListItem } from '../components/CustomListItem';
import { Header } from './common/Header';
import { AnimeState } from '../entryability/AnimeState';

@Preview
@ComponentV2
export struct More {
  /**
   * 更多列表数据
   */
  @Local moreItems: CustomItemInfo[] = [
    new CustomItemInfo({
      id: 'settings',
      title: '设置',
      icon: $r('app.media.gearshape'),
      type: ItemActionType.NONE,
      onChange: () => {
        AnimeState.pageStack.pushPathByName("SettingsPage", '')
      }
    }),
    new CustomItemInfo({
      id: 'disclaimer',
      title: '免责声明',
      icon: $r('app.media.ic_gitee'),
      type: ItemActionType.NONE,
      onChange: () => {
        AnimeState.pageStack.pushPathByName("WebPage", "disclaimer.html")
      }
    }),
    new CustomItemInfo({
      id: 'raw_repository',
      title: '原开源仓库',
      subtitle: 'https://github.com/Z-P-J/AnimeZ',
      icon: $r('app.media.ic_github'),
      type: ItemActionType.NONE,
      onChange: () => {
        AnimeState.pageStack.pushPathByName("WebPage", "https://github.com/Z-P-J/AnimeZ")
      }
    }),
    new CustomItemInfo({
      id: 'new_repository',
      title: '新开源仓库',
      subtitle: 'https://github.com/XHXYT/AnimeZ',
      icon: $r('app.media.ic_github'),
      type: ItemActionType.NONE,
      onChange: () => {
        AnimeState.pageStack.pushPathByName("WebPage", "https://github.com/XHXYT/AnimeZ")
      }
    })
  ];

  build() {
    Column() {
      // 标题
      Header('更多')
      // 列表
      Column() {
        ForEach(
          this.moreItems,
          (item: CustomItemInfo) => {
            CustomListItem({
              item: item,
              itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
            })
          },
          (item: CustomItemInfo) => item.id
        )
      }
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
    }
  }
}
