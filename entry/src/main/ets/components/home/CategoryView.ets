import { dataSourceManager } from "../../api/DataSourceManager"
import { CategoryListDataSource } from "../../entity/CategoryData"
import { DramaList } from "../../entity/HomepageData"
import { VideoCategoryNavigateInfo } from "../../entity/VideoNavigateInfo"
import { Header } from "../common/Header"
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
    Header(title, () => {
      const params: VideoCategoryNavigateInfo = {
        sourceKey: dataSourceManager.getKey(),
        title: title,
        url: moreUrl
      }
      this.pageStack.pushPathByName('CategoryPage', params)
    }, true)
  }

}

