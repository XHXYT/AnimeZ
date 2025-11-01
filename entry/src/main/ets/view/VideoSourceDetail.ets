
// 系统路由 - 视频源详情
@Builder
export function VideoSourceDetailBuilder(name: string, param: string) {
  VideoSourceDetail()
}

@Component
struct VideoSourceDetail {

  @Consume('pageStack') pageStack: NavPathStack
  // 顶部避让高度
  @StorageProp('topRectHeight') topHeight: number = 0
  // 底部避让高度
  @StorageProp('bottomRectHeight') bottomHeight: number = 0
  // 宽度断点
  @StorageLink('currentWidthBreakpoint') widthBp: WidthBreakpoint = 1
  // 高度断点
  @StorageLink('currentHeightBreakpoint') heightBp: HeightBreakpoint = 0

  build() {

  }

}