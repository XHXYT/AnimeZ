import { dataSourceManager } from "../../api/DataSourceManager"
import { CategoryListDataSource } from "../../entity/CategoryData"
import { DramaList } from "../../entity/HomepageData"
import { VideoCategoryNavigateInfo } from "../../entity/VideoNavigateInfo"
import { VideoList } from "../VideoList"

// 主页视频目录
@Component
export struct CategoryView {

  @Link categoryList: DramaList[]
  @Consume('pageStack') pageStack: NavPathStack
  private categoryListDataSource: CategoryListDataSource = new CategoryListDataSource([])

  aboutToAppear(): void {
    this.categoryListDataSource.pushData(this.categoryList)
  }

  build() {
    Column() {
      LazyForEach(this.categoryListDataSource, (category: DramaList, index: number) => {
        Column() {
          // 标题 & 更多
          this.Bar(category.title, category.moreUrl)
          // 视频列表
          VideoList({
            videoList: category.videoList,
            scrollable: false
          }).padding(16)
        }
      }, (item: DramaList, index: number) => index + JSON.stringify(item))
    }

  }

  // 标题 & 更多
  @Builder Bar(title: string, moreUrl: string) {
    Row({space: 2}) {
      Row()
        .height(14)
        .width(6)
        .borderRadius(4)
        .backgroundColor($r('app.color.primary_color'))
      Text(title)
        .fontColor($r('app.color.color_text_major'))
        .fontSize(16)
        .fontWeight(500)
      Blank()
      Row() {
        Text('更多')
          .fontColor($r('app.color.color_text_major'))
          .fontSize(14)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(26)
          .fontColor(['#817977'])
          .alignSelf(ItemAlign.End)
      }.onClick(() => {
        const params: VideoCategoryNavigateInfo = {
          sourceKey: dataSourceManager.getKey(),
          title: title,
          url: moreUrl
        }
        this.pageStack.pushPathByName('CategoryPage', params)
      })
    }
    .alignSelf(ItemAlign.Start)
    .width('100%')
    .padding({ left: 16, top: 16, right: 20, bottom: 0 })
  }

}

