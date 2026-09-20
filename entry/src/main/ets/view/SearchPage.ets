
import Logger from '../utils/Logger';
import { ViewState } from '../components/StateView';
import { VideoList } from '../components/VideoList';
import StateView from '../components/StateView';
import { ToastUtil } from '../utils/ToastUtils';
import SearchHistoryInfo from '../entity/SearchHistoryInfo';
import { AnimeState } from '../entryability/AnimeState';
import { searchViewModel } from '../viewmodel/SearchViewModel';
import { CategoryViewModel } from '../viewmodel/CategoryViewModel';

const tag: string = 'SearchPage'

// 系统路由
@Builder
export function SearchPageBuilder(name: string, param: Object) {
  SearchPage()
}

@ComponentV2
struct SearchPage {

  @Local keyword: string = ''
  private searchRecommends: string[] = ['冰菓', '进击的巨人', '电锯人', '鲁路修', '命运石之门', '回复术士', '天降之物']
  @Local categoryViewModel: CategoryViewModel = new CategoryViewModel()

  async aboutToAppear() {
    this.categoryViewModel.state = ViewState.CUSTOM
    // 查询搜索历史
    await searchViewModel.loadHistory()
  }

  build() {
    NavDestination() {
      this.SearchBar()
      StateView(
        {
          state: this.categoryViewModel.state,
          errorMessage: this.categoryViewModel.errorMessage,
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
    .padding({top: AnimeState.topRectHeight - 15, bottom: AnimeState.bottomRectHeight - 20})
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
  }

  @Builder content() {
    VideoList({ videoList: this.categoryViewModel.videoList }).height('100%').padding(16)
  }

  @Builder SearchBar() {
    Row() {
      SymbolGlyph($r('sys.symbol.arrow_left'))
        .fontSize(24)
        .fontColor([$r('app.color.color_text_major')])
        .onClick(() => {
          AnimeState.pageStack.pop(true)
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
        if (searchViewModel.searchHistoryList.length > 0) {
          this.Bar("搜索历史")
          Flex({ alignItems: ItemAlign.Start, justifyContent: FlexAlign.Start, wrap: FlexWrap.Wrap }) {
            ForEach(searchViewModel.searchHistoryList, (item: SearchHistoryInfo) => {
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
    // 记录搜索历史（VM 内插入后自动刷新历史列表）
    searchViewModel.addHistory(this.keyword)
    // 执行搜索（状态迁移 LOADING→CONTENT/EMPTY 由 VM 管理）
    await this.categoryViewModel.search(this.keyword)
  }

  private clearHistory() {
    ToastUtil.showAlertDialog(
      {
        title: '清空搜索历史',
        message: '确认清空所有搜索历史记录？',
        primaryButton: {
          value: '取消',
          action: () => {
          }
        },
        secondaryButton: {
          value: '确定',
          fontColor: Color.Red,
          action: async () => {
            await searchViewModel.clearHistory()
          }
        }
      }
    )
  }

}
