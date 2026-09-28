import { CustomItemInfo, ItemGroupData, makeItemGroups } from '../entity/CusItemInfo'
import { CustomListItem } from './CustomListItem'

/**
 * 列表卡片样式：
 * PER_GROUP 每组一张圆角卡片（默认，设置页风格）；
 * CONNECTED 扁平列表连体卡（首/尾条目保留外侧圆角，视觉上连成一张卡，应用信息页风格）；
 * NONE 无卡片背景（透明，半模态面板等自带背景的场景）。
 */
export enum SettingsListCardMode {
  PER_GROUP = 0,
  CONNECTED = 1,
  NONE = 2
}

/**
 * 通用分组设置列表容器：
 * 传入扁平 CustomItemInfo[]（GROUP 类型自动开组），内部基于 List 实现滚动，
 * 并内置分组、分组头、卡片样式、内容边距与条目渲染，页面只需声明数据。
 * version 递增时强制重建列表以刷新选中态（对应页面的 listVersion 机制）。
 */
@ComponentV2
export struct SettingsGroupList {

  /** 扁平设置项数据（含 GROUP 分组项；无 GROUP 时整体为一组且不渲染分组头） */
  @Require @Param items: CustomItemInfo[]
  /** 版本号：递增时作为分组 key 前缀强制重建，刷新选中态 */
  @Param version: number = 0
  /** 卡片样式，默认每组一卡 */
  @Param cardMode: SettingsListCardMode = SettingsListCardMode.PER_GROUP
  /** 列表内容边距（内置默认值，页面级容器已有边距或半模态面板场景可传 0 覆盖） */
  @Param contentPadding: Padding = { left: 16, right: 16, top: 4, bottom: 16 }
  /** 分组间距 */
  @Param groupGap: number = 16
  /** 条目内边距 */
  @Param itemPadding: Padding = { left: 16, right: 16, top: 12, bottom: 12 }
  /** 列表底部内容预留偏移（如为悬浮提示留出空间） */
  @Param contentEndOffset: number = 0
  /** 是否允许列表自身滚动：嵌套在页面级 Scroll 内时传 false，避免抢占手势 */
  @Param scrollable: boolean = true

  /** 分组结果（依赖 items 数组引用变化自动重算） */
  @Computed
  get groups(): ItemGroupData[] {
    return makeItemGroups(this.items)
  }

  build() {
    List() {
      ForEach(
        this.groups,
        (group: ItemGroupData, index: number) => {
          if (this.cardMode == SettingsListCardMode.CONNECTED) {
            // 连体卡：组透明，每个条目独立背景，首/尾条目保留外侧圆角
            ListItemGroup() {
              ForEach(
                group.items,
                (item: CustomItemInfo, itemIndex: number) => {
                  ListItem() {
                    Column() {
                      CustomListItem({ item: item, itemPadding: this.itemPadding })
                    }
                    .backgroundColor($r('app.color.background_color'))
                    .borderRadius({
                      topLeft: itemIndex === 0 ? 16 : 0,
                      topRight: itemIndex === 0 ? 16 : 0,
                      bottomLeft: itemIndex === group.items.length - 1 ? 16 : 0,
                      bottomRight: itemIndex === group.items.length - 1 ? 16 : 0
                    })
                  }
                },
                (item: CustomItemInfo) => item.id
              )
            }
            .margin({ bottom: index < this.groups.length - 1 ? this.groupGap : 0 })
          } else {
            // 每组一卡 / 无卡片：分组头与条目均在组内
            ListItemGroup() {
              if (group.group && group.group.title) {
                ListItem() {
                  this.GroupHeader(group.group.title)
                }
              }
              ForEach(
                group.items,
                (item: CustomItemInfo) => {
                  ListItem() {
                    CustomListItem({ item: item, itemPadding: this.itemPadding })
                  }
                },
                (item: CustomItemInfo) => item.id
              )
            }
            .backgroundColor(this.cardMode == SettingsListCardMode.NONE
              ? Color.Transparent : $r('app.color.background_color'))
            .borderRadius(16)
            .margin({ bottom: index < this.groups.length - 1 ? this.groupGap : 0 })
          }
        },
        // 唯一键生成（带版本前缀：version 变化时强制重建所有分组以刷新选中态）
        (group: ItemGroupData) => `${this.version}_${group.group?.id ?? String(group.items.length)}`
      )
    }
    .width('100%')
    .padding(this.contentPadding)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .enableScrollInteraction(this.scrollable)
    .contentEndOffset(this.contentEndOffset)
  }

  /**
   * 分组标题（色条视觉）
   */
  @Builder
  GroupHeader(title: ResourceStr) {
    Row() {
      Row()
        .backgroundColor($r('app.color.primary_color'))
        .height(14)
        .width(6)
        .margin({ right: 2 })
        .borderRadius(4)
      Text(title)
        .fontColor($r('app.color.color_text_major'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
    }
    .padding({ left: 16, top: 16, right: 16, bottom: 8 })
    .width('100%')
  }

}
