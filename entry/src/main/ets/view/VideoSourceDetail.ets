import { DataSourceConfig, SelectorConfig, CategoryCardConfig } from "../api/DataSourceConfig"
import { EditField, VideoSourceDetailViewModel } from "../viewmodel/VideoSourceDetailViewModel"
import TitleBar from "../components/TitleBar"
import { ToastUtil } from "../utils/ToastUtils"
import { AnimeState } from "../entryability/AnimeState"

// 系统路由 - 视频源详情
@Builder
export function VideoSourceDetailBuilder(name: string, param: DataSourceConfig) {
  VideoSourceDetail({ sourceConfig: param })
}

@ComponentV2
struct VideoSourceDetail {
  @Require @Param sourceConfig: DataSourceConfig

  // ViewModel：持有编辑状态与字段描述
  @Local vm: VideoSourceDetailViewModel = new VideoSourceDetailViewModel()
  @Local currentTabIndex: number = 0

  // Tab页标题
  private tabTitles: string[] = ['基本', '搜索', '主页', '详情', '视频']

  build() {
    NavDestination() {
      Column() {
        // 标题栏
        TitleBar({
          title: this.vm.editingConfig.name || '新建数据源',
          buttons: [
            {
              text: '保存',
              width: 48,
              fontColor: this.vm.hasChanges ? $r('app.color.primary_color_accent') : $r('app.color.color_text_minor'),
              enabled: !this.vm.isLoading,
              action: () => {
                if (this.vm.hasChanges && !this.vm.isLoading) {
                  this.vm.saveConfig()
                }
              }
            }
          ]
        })
        // 工具栏
        Row({ space: 12 }) {
          Row({ space: 5 }) {
            Toggle({ type: ToggleType.Checkbox, isOn: this.vm.editingConfig.enabled })
              .onChange((isOn: boolean) => {
                this.vm.setEnabled(isOn)
              })
            Text('启用状态')
              .fontSize(16)
              .fontColor($r('app.color.color_text_major'))
          }
          .alignItems(VerticalAlign.Center)
          Blank()
          Text('源模式')
            .fontSize(16)
            .fontColor($r('app.color.color_text_major'))
          Select([
            { value: 'HTML' },
            { value: 'JSON' }
          ])
            .selected(this.vm.sourceType === 'json' ? 1 : 0)
            .value(this.vm.sourceType === 'json' ? 'JSON' : 'HTML')
            .font({ size: 14 })
            .onSelect((index: number) => {
              this.vm.setSourceType(index === 1 ? 'json' : 'html')
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .backgroundColor($r('app.color.background_color_accent'))
        .alignItems(VerticalAlign.Center)
        // Tab内容区域
        Tabs({ index: this.currentTabIndex }) {
          ForEach(this.tabTitles, (item: string, index: number) => {
            TabContent() {
              this.tabContentBuilder(item)
            }
            .align(Alignment.TopStart)
            .tabBar(this.tabBarBuilder(item, index))
          }, (key: string) => key)
        }
        .barHeight(52)
        .barWidth(200)
        .vertical(false)
        .scrollable(true)
        .layoutWeight(1)
        .barMode(BarMode.Fixed)
        .animationDuration(300)
        .onChange((index: number) => {
          this.currentTabIndex = index
        })
        // 加载指示器
        if (this.vm.isLoading) {
          LoadingProgress()
            .width(50)
            .height(50)
            .position({ x: '50%', y: '50%' })
            .translate({ x: -25, y: -25 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_color_accent'))
    }
    .padding({ top: AnimeState.topRectHeight - 15, bottom: AnimeState.bottomRectHeight - 15 })
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
    .onBackPressed(() => {
      if (this.vm.hasChanges) {
        // 显示确认对话框
        ToastUtil.showAlertDialog({
          title: '确认退出',
          message: '您有未保存的更改，确认要退出吗？',
          primaryButton: {
            value: '取消',
            action: () => {}
          },
          secondaryButton: {
            value: '确认',
            fontColor: Color.Red,
            action: () => {
              AnimeState.pageStack.pop()
            }
          }
        })
        return true
      }
      return false
    })
  }

  aboutToAppear() {
    // 初始化 ViewModel（新建或编辑）
    this.vm.init(this.sourceConfig)
  }

  // ---------- 构建器 ----------

  @Builder
  tabBarBuilder(name: string, index: number) {
    Column({space: 2}) {
      Text(name)
        .fontSize(this.currentTabIndex == index ? 17 : 16)
        .fontWeight(this.currentTabIndex == index ? FontWeight.Regular : FontWeight.Normal)
      Row()
        .backgroundColor(this.currentTabIndex == index ? $r('app.color.primary_color') : Color.Transparent)
        .borderRadius(2)
        .width('60%')
        .height(4)
    }
    .width(35)
  }

  @Builder
  tabContentBuilder(name: string) {
    if (name == '基本') {
      this.BasicInfoTab()
    } else if (name == '搜索') {
      this.SearchConfigTab()
    } else if (name == '主页') {
      this.HomepageConfigTab()
    } else if (name == '详情') {
      this.DetailConfigTab()
    } else {
      this.VideoConfigTab()
    }
  }

  // 字段列表构建器（数据驱动渲染）
  @Builder
  FieldList(fields: EditField[]) {
    ForEach(fields, (item: EditField, index: number) => {
      this.InputFieldWithTitle(item.title, item.getValue(), item.setValue, item.placeholder,
        item.inputType ? item.inputType : 'text')
    }, (item: EditField, index: number) => `${this.vm.sourceType}_${index}_${item.title}`)
  }

  // 视频信息选择器（数据驱动）
  @Builder
  VideoInfoSelector(title: string, getConfig: () => SelectorConfig, setConfig: (c: SelectorConfig) => void,
    jsonMode: boolean) {
    Column({ space: 12 }) {
      Text(title)
        .titleStyles(0)
      this.FieldList(this.vm.videoInfoFields(getConfig, setConfig, jsonMode))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 单集选择器（数据驱动）
  @Builder
  EpisodeSelector(title: string, getConfig: () => SelectorConfig, setConfig: (c: SelectorConfig) => void,
    jsonMode: boolean) {
    Column({ space: 12 }) {
      Text(title)
        .titleStyles(0)
      this.FieldList(this.vm.episodeItemFields(getConfig, setConfig, jsonMode))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 基本信息Tab
  @Builder
  BasicInfoTab() {
    Scroll() {
      Column({ space: 16 }) {
        this.FieldList(this.vm.basicFields())
        // 默认源
        Row() {
          Text('默认数据源')
            .fontSize(16)
            .fontColor($r('app.color.color_text_major'))
            .width('30%')
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.vm.editingConfig.defaultSource })
            .onChange((isOn: boolean) => {
              this.vm.setDefaultSource(isOn)
            })
        }
        .width('100%')
        // JSON 模式：自定义请求头 + 登录配置
        if (this.vm.isJson()) {
          Text('自定义请求头')
            .titleStyles(1)
          this.FieldList(this.vm.requestHeaderFields())
          Text('登录配置(API)')
            .titleStyles(1)
          Row() {
            Text('启用账号登录')
              .fontSize(16)
              .fontColor($r('app.color.color_text_major'))
              .width('30%')
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.vm.editingConfig.login !== undefined })
              .onChange((isOn: boolean) => {
                this.vm.setLoginEnabled(isOn)
              })
          }
          .width('100%')
          if (this.vm.editingConfig.login !== undefined) {
            this.FieldList(this.vm.loginFields())
          }
        }
      }
      .tabContentStyles()
    }
  }

  // 搜索配置Tab
  @Builder
  SearchConfigTab() {
    Scroll() {
      Column({ space: 16 }) {
        Text('搜索配置')
          .titleStyles(1)
        Row({space: 12}) {
          // 是否需要基础URL
          Row({space: 5}) {
            Toggle({ type: ToggleType.Checkbox, isOn: this.vm.editingConfig.parserConfig.search.videos.urlNeedBaseUrl })
              .onChange((isOn: boolean) => {
                this.vm.setSearchUrlNeedBaseUrl(isOn)
              })
            Text('拼接基础URL')
              .fontSize(16)
              .fontColor($r('app.color.color_text_major'))
          }
          .justifyContent(FlexAlign.Start)
          .alignItems(VerticalAlign.Center)
          // 启用HTTPS
          Row() {
            Toggle({ type: ToggleType.Checkbox, isOn: this.vm.editingConfig.parserConfig.search.videos.enabledHttps })
              .onChange((isOn: boolean) => {
                this.vm.setSearchEnabledHttps(isOn)
              })
            Text('启用HTTPS')
              .fontSize(16)
              .fontColor($r('app.color.color_text_major'))
          }
          .justifyContent(FlexAlign.Start)
          .alignItems(VerticalAlign.Center)
        }
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Center)
        this.FieldList(this.vm.searchFields())
        this.VideoInfoSelector('搜索结果配置',
          () => this.vm.editingConfig.parserConfig.search.videos.itemSelectors,
          (config: SelectorConfig) => {
            this.vm.editingConfig.parserConfig.search.videos.itemSelectors = config
            this.vm.markAsChanged()
          }, this.vm.isJson())
      }
      .tabContentStyles()
    }
  }

  @Builder
  HomepageConfigTab() {
    Scroll() {
      Column({ space: 16 }) {
        Text('轮播图配置')
          .titleStyles(1)
        this.FieldList(this.vm.bannerFields())
        if (this.vm.isJson()) {
          this.VideoInfoSelector('轮播字段模板',
            () => this.vm.editingConfig.parserConfig.homepage.banner.itemSelectors,
            (config: SelectorConfig) => {
              this.vm.editingConfig.parserConfig.homepage.banner.itemSelectors = config
              this.vm.markAsChanged()
            }, true)
          Text('分类卡片')
            .titleStyles(1)
          this.CategoryCardsEditor()
        } else {
          this.VideoInfoSelector('轮播视频配置',
            () => this.vm.editingConfig.parserConfig.homepage.banner.itemSelectors,
            (config: SelectorConfig) => {
              this.vm.editingConfig.parserConfig.homepage.banner.itemSelectors = config
              this.vm.markAsChanged()
            }, false)
          Text('分类卡片(独立页面)')
            .titleStyles(1)
          this.CategoryCardsEditor()
          Text('分类配置(同页,未配置卡片时生效)')
            .titleStyles(1)
          this.FieldList(this.vm.categoryHtmlFields())
          this.VideoInfoSelector('分类视频配置',
            () => this.vm.editingConfig.parserConfig.homepage.category.videos.itemSelectors,
            (config: SelectorConfig) => {
              this.vm.editingConfig.parserConfig.homepage.category.videos.itemSelectors = config
              this.vm.markAsChanged()
            }, false)
        }
      }
      .tabContentStyles()
    }
  }

  // JSON 模式分类卡片编辑器
  @Builder
  CategoryCardsEditor() {
    Column({ space: 12 }) {
      ForEach(this.vm.categoryCards, (card: CategoryCardConfig, index: number) => {
        this.CategoryCardItem(card, index)
      }, (card: CategoryCardConfig, index: number) => this.vm.cardKeys[index] || index.toString())
      Button('添加卡片')
        .width('100%')
        .fontSize(15)
        .backgroundColor($r('app.color.background_color'))
        .fontColor($r('app.color.color_text_major'))
        .onClick(() => {
          this.vm.addCategoryCard()
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 单个分类卡片
  @Builder
  CategoryCardItem(card: CategoryCardConfig, index: number) {
    Column({ space: 10 }) {
      Row() {
        Text(`卡片${index + 1}`)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.color_text_major'))
        Blank()
        Text('删除')
          .fontSize(15)
          .fontColor(Color.Red)
          .onClick(() => {
            this.vm.deleteCategoryCard(index)
          })
      }
      .width('100%')
      this.FieldList(this.vm.cardFields(index))
      Row({ space: 12 }) {
        Row({ space: 5 }) {
          Toggle({ type: ToggleType.Checkbox, isOn: card.urlNeedBaseUrl ?? false })
            .onChange((isOn: boolean) => {
              this.vm.setCategoryCardToggle(index, isOn, undefined)
            })
          Text('拼接基础URL')
            .fontSize(15)
            .fontColor($r('app.color.color_text_major'))
        }
        .alignItems(VerticalAlign.Center)
        Row({ space: 5 }) {
          Toggle({ type: ToggleType.Checkbox, isOn: card.enabledHttps ?? true })
            .onChange((isOn: boolean) => {
              this.vm.setCategoryCardToggle(index, undefined, isOn)
            })
          Text('启用HTTPS')
            .fontSize(15)
            .fontColor($r('app.color.color_text_major'))
        }
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(VerticalAlign.Center)
      this.VideoInfoSelector('字段模板',
        () => {
          const c = this.vm.categoryCards[index]
          return c ? c.itemSelectors : {}
        },
        (config: SelectorConfig) => {
          const c = this.vm.categoryCards[index]
          if (c) {
            c.itemSelectors = config
            this.vm.markAsChanged()
          }
        }, this.vm.isJson())
    }
    .padding(12)
    .borderRadius(16)
    .backgroundColor($r('app.color.background_color'))
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  DetailConfigTab() {
    Scroll() {
      Column({ space: 16 }) {
        Text(this.vm.isJson() ? '详情字段模板' : '影片详情')
          .titleStyles(1)
        this.FieldList(this.vm.detailFields())
        Text(this.vm.isJson() ? '选集配置(JSON)' : '剧集配置')
          .titleStyles(1)
        this.FieldList(this.vm.episodeListFields())
        this.EpisodeSelector(this.vm.isJson() ? '单集字段模板' : '单集剧集配置',
          () => this.vm.editingConfig.parserConfig.detail.episodes.itemSelectors,
          (config: SelectorConfig) => {
            this.vm.editingConfig.parserConfig.detail.episodes.itemSelectors = config
            this.vm.markAsChanged()
          }, this.vm.isJson())
        Text(this.vm.isJson() ? '推荐配置(JSON)' : '推荐配置')
          .titleStyles(1)
        this.FieldList(this.vm.recommendFields())
        this.VideoInfoSelector(this.vm.isJson() ? '推荐字段模板' : '推荐番剧配置',
          () => this.vm.editingConfig.parserConfig.detail.recommends.itemSelectors,
          (config: SelectorConfig) => {
            this.vm.editingConfig.parserConfig.detail.recommends.itemSelectors = config
            this.vm.markAsChanged()
          }, this.vm.isJson())
      }
      .tabContentStyles()
    }
  }

  // 视频配置Tab
  @Builder
  VideoConfigTab() {
    Scroll() {
      Column({ space: 16 }) {
        this.FieldList(this.vm.videoFields())
        // JSON 模式：JSON接口 / 链接透传（配合内嵌视频解析JS）
        if (this.vm.isJson()) {
          Row() {
            Text('解析模式')
              .fontSize(16)
              .fontColor($r('app.color.color_text_major'))
              .width('30%')
            Blank()
            Select([
              { value: 'JSON接口' },
              { value: '链接透传' }
            ])
              .selected(this.vm.editingConfig.parserConfig.videoUrl.pattern === 'link' ? 1 : 0)
              .value(this.vm.editingConfig.parserConfig.videoUrl.pattern === 'link' ? '链接透传' : 'JSON接口')
              .font({ size: 16 })
              .onSelect((index: number, value: string) => {
                this.vm.setVideoPattern(index === 1 ? 'link' : 'json')
              })
          }
          .width('100%')
        } else {
          // HTML 模式：解析模式（暂不可用）
          Row() {
            Text('解析模式')
              .fontSize(16)
              .fontColor($r('app.color.color_text_major'))
              .width('30%')
            Blank()
            Select([
              { value: '选择器' },
              { value: '正则表达式' }
            ])
              .enabled(false)
              .selected(0)
              .value(this.vm.editingConfig.parserConfig.videoUrl.pattern || '选择器')
              .font({ size: 16 })
              .onSelect((index: number, value: string) => {
                this.vm.setVideoPattern(value)
              })
          }
          .enabled(false)
          .width('100%')
        }
      }
      .tabContentStyles()
    }
  }

  // 带标题的输入框
  @Builder
  InputFieldWithTitle(title: string, value: string, onChange: (value: string) => void, placeholder: string, inputType: string = 'text', disabled: boolean = false) {
    Column({ space: 8 }) {
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.color_text_major'))
        .width('100%')
        .textAlign(TextAlign.Start)
      TextArea({
        placeholder: placeholder,
        text: value
      })
        .padding(12)
        .fontSize(14)
        .width('100%')
        .borderRadius(16)
        .enabled(!disabled)
        .backgroundColor($r('app.color.background_color'))
        .onChange((newValue: string) => {
          // 与当前绑定值相同说明是初始化/渲染触发的冗余回调，非用户编辑，不标记更改
          if (newValue !== value) {
            onChange(newValue)
          }
        })
        .type(inputType === 'number' ? TextAreaType.NUMBER : TextAreaType.NORMAL)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

}


@Extend(Text)
function titleStyles(weight: 0 | 1) {
  .fontWeight(weight == 0 ? FontWeight.Medium : FontWeight.Bold)
  .textAlign(TextAlign.Start)
  .width('100%')
  .fontSize(18)
}

@Extend(Column)
function tabContentStyles() {
  .justifyContent(FlexAlign.Start)
  .alignItems(HorizontalAlign.Start)
  .padding({ left: 16, right: 16, top: 16, bottom: 16 })
}
