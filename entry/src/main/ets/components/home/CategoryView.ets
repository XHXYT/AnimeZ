import { DramaList } from "../../entity/HomepageData"
import VideoInfo from "../../entity/VideoInfo"
import { BaseDataSource } from "../common/BaseDataSource"
import { VideoList } from "../VideoList"

@Component
export struct CategroyView {

  @Link categoryList: DramaList[]
  @Consume('pageStack') pageStack: NavPathStack
  private categroyListDataSource: CategoryListDataSource = new CategoryListDataSource([])

  aboutToAppear(): void {
    this.categroyListDataSource.pushData(this.categoryList)
  }

  build() {
    Column() {
      LazyForEach(this.categroyListDataSource, (category: DramaList, index: number) => {
        Column() {
          // 标题 & 更多
          this.Bar(category.title, category.moreUrl)
          // 视频列表
          VideoList({
            videoList: category.videoList as VideoInfo[],
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
        //  TODO 跳转至分类更多

      })
    }
    .alignSelf(ItemAlign.Start)
    .width('100%')
    .padding({ left: 16, top: 16, right: 20, bottom: 0 })
  }

}

class CategoryListDataSource extends BaseDataSource<DramaList> {
  private dataArray: DramaList[] = []

  public totalCount(): number {
    return this.dataArray.length
  }

  public getData(index: number): DramaList {
    return this.dataArray[index]
  }

  public addData(index: number, data: DramaList): void {
    this.dataArray.splice(index, 0, data)
    this.notifyDataAdd(index)
  }

  public pushData(data: DramaList[]): void {
    this.dataArray = data
    this.notifyDataAdd(this.dataArray.length - 1)
  }

  // 删除全部数据
  public clear(): void {
    this.empty()
    this.refresh()
  }

  public empty(): void {
    this.dataArray = []
  }
  public refresh(): void {
    this.notifyDataReload()
  }
}