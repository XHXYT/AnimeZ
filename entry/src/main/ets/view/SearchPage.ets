
import Logger from '../utils/Logger';
import { ViewState } from '../components/StateView';
import { VideoList } from '../components/VideoList';
import VideoInfo from '../entity/VideoInfo';
import StateView from '../components/StateView';
import { dataSourceManager } from '../api/DataSourceManager';
import { ToastUtil } from '../utils/ToastUtils';
import SearchHistoryInfo from '../entity/SearchHistoryInfo';
import { SearchHistoryTable } from '../db/impl/SearchHistoryDao';

const tag: string = 'SearchPage'

// 系统路由
@Builder
export function SearchPageBuilder(name: string, param: Object) {
  SearchPage()
}

@Component
struct SearchPage {

  @State videoList: VideoInfo[] = []
  @Consume('pageStack') pageStack: NavPathStack
  @State searchHistoryList: SearchHistoryInfo[] = []
  // 顶部避让高度
  @StorageProp('topRectHeight') topHeight: number = 0
  @StorageLink('currentColorMode') currentMode: number = 1
  // 底部避让高度
  @StorageProp('bottomRectHeight') bottomHeight: number = 0
  @State searchRecommends: string[] = ['冰菓', '进击的巨人', '电锯人', '鲁路修', '命运石之门', '回复术士', '天降之物']
  @State state: number = 0
  @State errorMessage: string = ''
  @State keyword: string = ''

  private searchHistoryInfoDB = new SearchHistoryTable(this.getUIContext().getHostContext()!)

  async aboutToAppear() {
    this.state = ViewState.CUSTOM
    // 查询搜索历史
    const search_list = await this.searchHistoryInfoDB.queryAll()
    if (search_list) {
      this.searchHistoryList = search_list
    }
  }

  build() {
    NavDestination() {
      this.SearchBar()
      StateView(
        {
          state: this.state,
          errorMessage: $errorMessage,
          content: () => {
            this.content()
          },
          custom: () => {
            this.SearchHistory()
          },
          onRetry: () => {
            this.doSearch(this.keyword)
            return true;
          }
        }
      )
        .width('100%')
        .layoutWeight(1)

    }
    .padding({top: this.topHeight - 15, bottom: this.bottomHeight - 20})
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
  }

  @Builder content() {
    VideoList({ videoList: this.videoList }).height('100%').padding(16)
  }

  @Builder SearchBar() {
    Row() {
      SymbolGlyph($r('sys.symbol.arrow_left'))
        .fontSize(24)
        .fontColor([$r('app.color.color_text_major')])
        .onClick(() => {
          this.pageStack.pop(true)
        })
      TextInput({ placeholder: '输入关键字...', text: this.keyword })
        .placeholderFont({ size: 14, weight: 300 })
        .placeholderColor('#817977')
        .fontColor($r('app.color.color_text_major'))
        .onChange((value) => {
          this.keyword = value
        })
        .onSubmit(() => {
          this.doSearch(this.keyword)
        })
        .height(36)
        .margin({ left: 12, right: 12 })
        .backgroundColor($r('app.color.background_color'))
        .layoutWeight(1)
      Text('搜索')
        .fontSize(16)
        .fontColor($r('app.color.primary_color'))
        .onClick(() => {
          this.doSearch(this.keyword)
        })
    }
    .height(56)
    .width('100%')
    .padding({left: 16, right: 16})
  }

  @Builder Bar(title: string, showButton: boolean = true) {
    Row() {
      Row()
        .height(14)
        .width(6)
        .margin({ right: 2 })
        .borderRadius(4)
        .backgroundColor($r('app.color.primary_color'))
      Text(title)
        .fontColor($r('app.color.color_text_major'))
        .fontSize(16)
        .fontWeight(500)

      Blank()

      if (showButton) {
        Image($r('app.media.ic_delete'))
          .width(20)
          .height(20)
          .alignSelf(ItemAlign.End)
          .onClick(() => {
            this.clearHistory()
          })
      }
    }
    .alignSelf(ItemAlign.Start)
    .width('100%')
    .padding({ left: 16, top: 16, right: 16, bottom: 8 })
  }

  @Builder SearchHistory() {
    Scroll() {
      Column() {
        if (this.searchHistoryList.length > 0) {
          this.Bar("搜索历史")
          Flex({ alignItems: ItemAlign.Start, justifyContent: FlexAlign.Start, wrap: FlexWrap.Wrap }) {
            ForEach(this.searchHistoryList, (item: SearchHistoryInfo) => {
              Text(item.keyword)
                .textAlign(TextAlign.Center)
                .backgroundColor($r('app.color.background_color'))
                .fontColor($r('app.color.color_text_major'))
                .fontWeight(300)
                .fontSize(14)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({ top: 8, bottom: 8, left: 12, right: 12 })
                .borderRadius(4)
                .margin(6)
                .constraintSize({
                  minWidth: '15%',
                  maxWidth: '50%'
                })
                .onClick(() => {
                  this.doSearch(item.keyword)
                })

            })
          }
          .margin(6)
        }

        this.Bar("搜索推荐", false)
        Flex({ alignItems: ItemAlign.Start, justifyContent: FlexAlign.Start, wrap: FlexWrap.Wrap }) {
          ForEach(this.searchRecommends, (item: string) => {
            Text(item)
              .width('45%')
              .textAlign(TextAlign.Start)
              .fontColor($r('app.color.color_text_major'))
              .fontWeight(300)
              .fontSize(14)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ top: 2, bottom: 2 })
              .margin(6)
              .onClick(() => {
                this.doSearch(item)
              })
          })
        }
        .margin(6)
      }
      .constraintSize({
        minHeight: '100%'
      })
    }
    .edgeEffect(EdgeEffect.Spring)
    .height('100%')
  }

  private async doSearch(keyword: string) {
    Logger.e('tips', 'doSearch keyword=' + keyword)
    this.keyword = keyword
    if (this.keyword.length == 0) {
      ToastUtil.showToast({ message: '请输入关键词' }, `${tag}.doSearch`)
      return
    }
    this.state = ViewState.LOADING
    let result: SearchHistoryInfo = {
      id: null,
      keyword: keyword,
      accessTime: new Date().getTime()
    }
    this.searchHistoryInfoDB.insert(result)
      .then((insertId) => {
        console.log('SearchTest #doSearch 插入成功id为：', insertId)
      })
      .catch((error: Error) => {
        console.error("SearchTest #doSearch 插入操作失败: ", error)
      })

    dataSourceManager.search(keyword, 1)
      .then((videoList) => {
        this.videoList = videoList
        if (this.videoList.length == 0) {
          this.state = ViewState.EMPTY
        } else {
          this.state = ViewState.CONTENT
        }
      })
      .catch((e: Error) => {
        this.errorMessage = JSON.stringify(e)
        this.state = ViewState.ERROR
      })
  }

  private clearHistory() {
    ToastUtil.showAlertDialog(
      {
        title: '清空搜索历史',
        message: '确认清空搜索历史记录？',
        primaryButton: {
          value: '取消',
          action: () => {
          }
        },
        secondaryButton: {
          value: '确定',
          fontColor: Color.Red,
          action: async () => {
            await this.searchHistoryInfoDB.clearAll()
            this.searchHistoryList = []
          }
        }
      }
    )
  }

}