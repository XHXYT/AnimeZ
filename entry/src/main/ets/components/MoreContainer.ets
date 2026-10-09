
import { CustomItemInfo, ItemActionType } from '../entity/CusItemInfo';
import { SettingsGroupList } from './SettingsGroupList';
import { buildMoreGroupItems } from './SettingsContent';
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

  /** 窗口模式下隐藏"设置"（已内嵌"我的"列表），并入"更多"组条目，并以 GROUP 数据驱动组标题替代大标题 */
  @Computed
  get visibleItems(): CustomItemInfo[] {
    if (AnimeState.windowMode) {
      const groupHeader: CustomItemInfo = new CustomItemInfo({
        id: 'more_group',
        title: '更多',
        type: ItemActionType.GROUP
      })
      return [groupHeader]
        .concat(this.moreItems.filter((item: CustomItemInfo): boolean => item.id !== 'settings'))
        .concat(buildMoreGroupItems())
    }
    return this.moreItems
  }

  build() {
    Column() {
      // 标题（窗口模式下由列表内 GROUP 项渲染同款组标题，此处大标题不显示）
      if (!AnimeState.windowMode) {
        Header('更多', undefined, false, false)
      }
      // 列表
      SettingsGroupList({
        items: this.visibleItems,
        contentPadding: { left: 0, right: 0, top: 0, bottom: 0 }
      })
    }
  }
}
