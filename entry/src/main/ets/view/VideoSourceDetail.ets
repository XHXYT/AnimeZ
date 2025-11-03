import { DataSourceConfig, SelectorConfig } from "../api/DataSourceConfig"
import { dataSourceManager } from "../api/DataSourceManager"
import TitleBar from "../components/TitleBar"
import { ToastUtil } from "../utils/ToastUtils"

// 系统路由 - 视频源详情 TODO ①保存后视频源页面不会刷新 ②部分选项显示和描述错误 ③.....
@Builder
export function VideoSourceDetailBuilder(name: string, param: DataSourceConfig) {
  VideoSourceDetail({ sourceConfig: param })
}

@Component
struct VideoSourceDetail {
  @Prop sourceConfig: DataSourceConfig

  @Consume('pageStack') pageStack: NavPathStack
  // 顶部避让高度
  @StorageProp('topRectHeight') topHeight: number = 0
  // 底部避让高度
  @StorageProp('bottomRectHeight') bottomHeight: number = 0
  // 宽度断点
  @StorageLink('currentWidthBreakpoint') widthBp: WidthBreakpoint = 1
  // 高度断点
  @StorageLink('currentHeightBreakpoint') heightBp: HeightBreakpoint = 0

  // 编辑状态的配置（深拷贝避免直接修改原始数据）
  @State editingConfig: DataSourceConfig = {} as DataSourceConfig
  @State hasChanges: boolean = false
  @State currentTabIndex: number = 0
  @State isLoading: boolean = false

  // Tab页标题
  private tabTitles: string[] = ['基本', '搜索', '主页', '详情', '视频']

  build() {
    NavDestination() {
      Column() {
        // 标题栏
        TitleBar({
          title: this.editingConfig.name || '新建数据源',
          button: () => {
            this.saveButton()
          }
        })
        // 工具栏
        Row({ space: 5 }) {
          Toggle({ type: ToggleType.Checkbox, isOn: this.editingConfig.enabled })
            .onChange((isOn: boolean) => {
              this.editingConfig.enabled = isOn
              this.markAsChanged()
            })
          Text('启用状态')
            .fontSize(16)
            .fontColor($r('app.color.color_text_major'))
          Blank()
        }
        .width('100%')
        .padding({ left: 16, right: 16})
        .backgroundColor($r('app.color.background_color_accent'))
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
        if (this.isLoading) {
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
    .padding({ top: this.topHeight - 15, bottom: this.bottomHeight - 15 })
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
    .onBackPressed(() => {
      if (this.hasChanges) {
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
              this.pageStack.pop()
            }
          }
        })
        return true
      }
      return false
    })
  }

  aboutToAppear() {
    // 判断是新建还是编辑
    if (this.sourceConfig.key === 'new') {
      // 新建数据源
      this.initNewSource()
    } else {
      // 编辑现有数据源
      this.initEditSource()
    }
  }

  // 初始化新数据源
  private initNewSource() {
    this.editingConfig = {
      key: '',
      name: '',
      group: '',
      baseUrl: '',
      version: 1,
      description: '',
      enabled: true,
      priority: 100,
      defaultSource: false,
      parserConfig: {
        search: {
          videos: {
            urlTemplate: '',
            listSelector: '',
            urlNeedBaseUrl: true,
            enabledHttps: true,
            itemSelectors: {}
          }
        },
        homepage: {
          banner: {
            urlTemplate: '',
            listSelector: '',
            urlNeedBaseUrl: true,
            enabledHttps: true,
            itemSelectors: {}
          },
          category: {
            title: '',
            titles: '',
            moreUrl: '',
            moreUrlNeedBaseUrl: true,
            videoLists: '',
            videos: {
              urlTemplate: '',
              listSelector: '',
              urlNeedBaseUrl: true,
              enabledHttps: true,
              itemSelectors: {}
            }
          }
        },
        detail: {
          titleSelector: '',
          descSelector: '',
          coverSelector: '',
          episodes: {
            itemSelector: '',
            itemSelectors: {}
          },
          recommends: {
            listSelector: '',
            itemSelectors: {},
            urlNeedBaseUrl: true,
            enabledHttps: true
          }
        },
        videoUrl: {}
      }
    }
  }

  // 初始化编辑数据源
  private initEditSource() {
    // 深拷贝传入的配置，避免直接修改原始数据
    this.editingConfig = JSON.parse(JSON.stringify(this.sourceConfig))
  }

  // 保存配置
  private async saveConfig() {
    if (!this.editingConfig.key || !this.editingConfig.name) {
      ToastUtil.showToast({ message: "请填写必要信息" })
      return
    }
    try {
      this.isLoading = true
      if (this.sourceConfig.key === 'new') {
        // 添加新数据源
        try {
          await dataSourceManager.addDataSource(this.editingConfig)
          ToastUtil.showToast({ message: "数据源添加成功" })
        } catch (err) {
          console.error(`${err}`)
          ToastUtil.showToast({message: `${this.sourceConfig.key} 不唯一`})
        }
      } else {
        // 更新现有数据源
        await dataSourceManager.updateDataSource(this.sourceConfig.key, this.editingConfig)
        ToastUtil.showToast({ message: "数据源更新成功" })
      }
      this.hasChanges = false
      // this.pageStack.pop()
    } catch (error) {
      ToastUtil.showToast({ message: "保存失败: " + error.message })
    } finally {
      this.isLoading = false
    }
  }

  // 标记为已更改
  private markAsChanged() {
    this.hasChanges = true
  }

  @Builder
  saveButton() {
    Button('保存')
      .fontColor(this.hasChanges ? $r('app.color.primary_color_accent') : $r('app.color.color_text_minor'))
      .backgroundColor(Color.Transparent)
      .enabled(!this.isLoading)
      .onClick(() => {
        if (this.hasChanges && !this.isLoading) {
          this.saveConfig()
        }
      })
  }

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

  // 基本信息Tab
  @Builder
  BasicInfoTab() {
    Scroll() {
      Column({ space: 16 }) {
        // Key
        this.InputFieldWithTitle('Key(请确保唯一性)', this.editingConfig.key, (value: string) => {
          this.editingConfig.key = value
          this.markAsChanged()
        }, '数据源唯一标识')
        // 基础URL
        this.InputFieldWithTitle('基础URL', this.editingConfig.baseUrl, (value: string) => {
          this.editingConfig.baseUrl = value
          this.markAsChanged()
        }, '数据源基础地址，如：https://example.com')
        // 名称
        this.InputFieldWithTitle('名称', this.editingConfig.name, (value: string) => {
          this.editingConfig.name = value
          this.markAsChanged()
        }, '数据源显示名称')
        // 描述
        this.InputFieldWithTitle('描述', this.editingConfig.description, (value: string) => {
          this.editingConfig.description = value
          this.markAsChanged()
        }, '介绍一下视频源')
        // 分组
        this.InputFieldWithTitle('分组', this.editingConfig.group, (value: string) => {
          this.editingConfig.group = value
          this.markAsChanged()
        }, '数据源所属分组')
        // 优先级
        this.InputFieldWithTitle('优先级', this.editingConfig.priority.toString(), (value: string) => {
          const num = parseInt(value)
          if (!isNaN(num)) {
            this.editingConfig.priority = num
            this.markAsChanged()
          }
        }, '数值越小优先级越高', 'number')
        // 默认源
        Row() {
          Text('默认数据源')
            .fontSize(16)
            .fontColor($r('app.color.color_text_major'))
            .width('30%')
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.editingConfig.defaultSource })
            .onChange((isOn: boolean) => {
              this.editingConfig.defaultSource = isOn
              this.markAsChanged()
            })
        }
        .width('100%')
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
            Toggle({ type: ToggleType.Checkbox, isOn: this.editingConfig.parserConfig.search.videos.urlNeedBaseUrl })
              .onChange((isOn: boolean) => {
                this.editingConfig.parserConfig.search.videos.urlNeedBaseUrl = isOn
                this.markAsChanged()
              })
            Text('拼接基础URL')
              .fontSize(16)
              .fontColor($r('app.color.color_text_major'))
              .width('30%')
          }
          .justifyContent(FlexAlign.Start)
          .alignItems(VerticalAlign.Center)
          // 启用HTTPS
          Row() {
            Toggle({ type: ToggleType.Checkbox, isOn: this.editingConfig.parserConfig.search.videos.enabledHttps })
              .onChange((isOn: boolean) => {
                this.editingConfig.parserConfig.search.videos.enabledHttps = isOn
                this.markAsChanged()
              })
            Text('启用HTTPS')
              .fontSize(16)
              .fontColor($r('app.color.color_text_major'))
              .width('30%')
          }
          .justifyContent(FlexAlign.Start)
          .alignItems(VerticalAlign.Center)
        }
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Center)
        // URL模板
        this.InputFieldWithTitle('搜索链接模板', this.editingConfig.parserConfig.search.videos.urlTemplate, (value: string) => {
          this.editingConfig.parserConfig.search.videos.urlTemplate = value
          this.markAsChanged()
        }, '搜索URL模板，如：/search?q={keyword}&page={page}')
        // 列表选择器
        this.InputFieldWithTitle('列表选择器', this.editingConfig.parserConfig.search.videos.listSelector, (value: string) => {
          this.editingConfig.parserConfig.search.videos.listSelector = value
          this.markAsChanged()
        }, '搜索结果列表的CSS选择器')
        // 搜索结果配置 - 视频信息
        this.VideoInfoSelector('搜索结果配置', this.editingConfig.parserConfig.search.videos.itemSelectors as SelectorConfig, (config: SelectorConfig) => {
          this.editingConfig.parserConfig.search.videos.itemSelectors = config
          this.markAsChanged()
        })
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
        // Banner URL拼接模板
        this.InputFieldWithTitle('基础URL拼接模板', this.editingConfig.parserConfig.homepage.banner.urlTemplate, (value: string) => {
          this.editingConfig.parserConfig.homepage.banner.urlTemplate = value
          this.markAsChanged()
        }, '轮播图的基础链接拼接模板')
        // Banner列表选择器
        this.InputFieldWithTitle('列表选择器', this.editingConfig.parserConfig.homepage.banner.listSelector, (value: string) => {
          this.editingConfig.parserConfig.homepage.banner.listSelector = value
          this.markAsChanged()
        }, 'Banner列表的CSS选择器')
        // Banner配置 - 视频信息
        this.VideoInfoSelector('轮播项目配置', this.editingConfig.parserConfig.homepage.banner.itemSelectors as SelectorConfig, (config: SelectorConfig) => {
          this.editingConfig.parserConfig.homepage.banner.itemSelectors = config
          this.markAsChanged()
        })
        Text('分类配置')
          .titleStyles(1)
        // 分类标题选择器
        this.InputFieldWithTitle('标题选择器', this.editingConfig.parserConfig.homepage.category.title, (value: string) => {
          this.editingConfig.parserConfig.homepage.category.title = value
          this.markAsChanged()
        }, '分类标题的CSS选择器')
        // 分类标题列表选择器
        this.InputFieldWithTitle('标题列表选择器', this.editingConfig.parserConfig.homepage.category.titles, (value: string) => {
          this.editingConfig.parserConfig.homepage.category.titles = value
          this.markAsChanged()
        }, '分类标题列表的CSS选择器')
        // 更多链接选择器
        this.InputFieldWithTitle('更多链接选择器', this.editingConfig.parserConfig.homepage.category.moreUrl, (value: string) => {
          this.editingConfig.parserConfig.homepage.category.moreUrl = value
          this.markAsChanged()
        }, '分类更多链接的CSS选择器')
        // 视频列表容器选择器
        this.InputFieldWithTitle('视频列表容器', this.editingConfig.parserConfig.homepage.category.videoLists, (value: string) => {
          this.editingConfig.parserConfig.homepage.category.videoLists = value
          this.markAsChanged()
        }, '分类视频列表容器的CSS选择器')
        // 分类视频配置 - 视频信息
        this.VideoInfoSelector('分类视频项目配置', this.editingConfig.parserConfig.homepage.category.videos.itemSelectors as SelectorConfig, (config: SelectorConfig) => {
          this.editingConfig.parserConfig.homepage.category.videos.itemSelectors = config
          this.markAsChanged()
        })
      }
      .tabContentStyles()
    }
  }

  @Builder
  DetailConfigTab() {
    Scroll() {
      Column({ space: 16 }) {
        Text('影片详情')
          .titleStyles(1)
        // 标题选择器
        this.InputFieldWithTitle('标题选择器', this.editingConfig.parserConfig.detail.titleSelector, (value: string) => {
          this.editingConfig.parserConfig.detail.titleSelector = value
          this.markAsChanged()
        }, '视频详情页标题的CSS选择器')
        // 描述选择器
        this.InputFieldWithTitle('描述选择器', this.editingConfig.parserConfig.detail.descSelector, (value: string) => {
          this.editingConfig.parserConfig.detail.descSelector = value
          this.markAsChanged()
        }, '视频详情页描述的CSS选择器')
        // 封面选择器
        this.InputFieldWithTitle('封面选择器', this.editingConfig.parserConfig.detail.coverSelector, (value: string) => {
          this.editingConfig.parserConfig.detail.coverSelector = value
          this.markAsChanged()
        }, '视频详情页封面的CSS选择器')
        Text('剧集配置')
          .titleStyles(1)
        // 多路线标题选择器
        this.InputFieldWithTitle('多路线标题选择器(可选)', this.editingConfig.parserConfig.detail.episodes.routeTitlesSelector || '', (value: string) => {
          this.editingConfig.parserConfig.detail.episodes.routeTitlesSelector = value
          this.markAsChanged()
        }, '多路线标题的CSS选择器')
        // 多路线剧集选择器
        this.InputFieldWithTitle('多路线剧集选择器(可选)', this.editingConfig.parserConfig.detail.episodes.routeContainersSelector || '', (value: string) => {
          this.editingConfig.parserConfig.detail.episodes.routeContainersSelector = value
          this.markAsChanged()
        }, '多路线剧集的CSS选择器')
        // 单路线剧集选择器
        this.InputFieldWithTitle('单路线剧集选择器(仅单路线时必选)', this.editingConfig.parserConfig.detail.episodes.containerSelector || '', (value: string) => {
          this.editingConfig.parserConfig.detail.episodes.containerSelector = value
          this.markAsChanged()
        }, '单路线剧集的CSS选择器')
        // 剧集列表选择器
        this.InputFieldWithTitle('剧集列表选择器', this.editingConfig.parserConfig.detail.episodes.itemSelector, (value: string) => {
          this.editingConfig.parserConfig.detail.episodes.itemSelector = value
          this.markAsChanged()
        }, '剧集列表的CSS选择器')
        // 剧集配置 - 剧集信息
        this.EpisodeSelector('单集剧集配置', this.editingConfig.parserConfig.detail.episodes.itemSelectors as SelectorConfig, (config: SelectorConfig) => {
          this.editingConfig.parserConfig.detail.episodes.itemSelectors = config
          this.markAsChanged()
        })
        Text('推荐配置')
          .titleStyles(1)
        // 推荐列表选择器
        this.InputFieldWithTitle('推荐列表选择器', this.editingConfig.parserConfig.detail.recommends.listSelector, (value: string) => {
          this.editingConfig.parserConfig.detail.recommends.listSelector = value
          this.markAsChanged()
        }, '推荐视频列表的CSS选择器')
        // 推荐配置 - 视频信息
        this.VideoInfoSelector('推荐番剧配置', this.editingConfig.parserConfig.detail.recommends.itemSelectors as SelectorConfig, (config: SelectorConfig) => {
          this.editingConfig.parserConfig.detail.recommends.itemSelectors = config
          this.markAsChanged()
        })
      }
      .tabContentStyles()
    }
  }

  // 视频信息选择器
  @Builder
  VideoInfoSelector(title: string, config: SelectorConfig, onChange: (config: SelectorConfig) => void) {
    Column({ space: 12 }) {
      Text(title)
        .titleStyles(0)
      // 番剧名选择器
      this.InputFieldWithTitle('番剧名', config.title || '', (value: string) => {
        const newConfig: SelectorConfig = {
          title: value,
          url: config.url || '',
          imgUrl: config.imgUrl || '',
          episode: config.episode || ''
        }
        onChange(newConfig)
      }, '番剧名称的CSS选择器')
      // 封面链接选择器
      this.InputFieldWithTitle('封面链接', config.imgUrl || '', (value: string) => {
        const newConfig: SelectorConfig = {
          title: config.title || '',
          url: config.url || '',
          imgUrl: value,
          episode: config.episode || ''
        }
        onChange(newConfig)
      }, '封面图片链接的CSS选择器')
      // 番剧链接选择器
      this.InputFieldWithTitle('番剧链接', config.url || '', (value: string) => {
        const newConfig: SelectorConfig = {
          title: config.title || '',
          url: value,
          imgUrl: config.imgUrl || '',
          episode: config.episode || ''
        }
        onChange(newConfig)
      }, '番剧详情链接的CSS选择器')

      // 剧集数选择器
      this.InputFieldWithTitle('剧集数', config.episode || '', (value: string) => {
        const newConfig: SelectorConfig = {
          title: config.title || '',
          url: config.url || '',
          imgUrl: config.imgUrl || '',
          episode: value
        }
        onChange(newConfig)
      }, '剧集数量的CSS选择器')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 剧集选择器 用于剧集列表
  @Builder
  EpisodeSelector(title: string, config: SelectorConfig, onChange: (config: SelectorConfig) => void) {
    Column({ space: 12 }) {
      Text(title)
        .titleStyles(0)
      // 标题选择器
      this.InputFieldWithTitle('标题', config.title || '', (value: string) => {
        const newConfig: SelectorConfig = {
          title: value,
          url: config.url || ''
        }
        onChange(newConfig)
      }, '剧集标题的CSS选择器')
      // 链接选择器
      this.InputFieldWithTitle('链接', config.url || '', (value: string) => {
        const newConfig: SelectorConfig = {
          title: config.title || '',
          url: value
        }
        onChange(newConfig)
      }, '剧集链接的CSS选择器')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 视频配置Tab
  @Builder
  VideoConfigTab() {
    Scroll() {
      Column({ space: 16 }) {
        // 播放链接选择器
        this.InputFieldWithTitle('播放链接选择器', this.editingConfig.parserConfig.videoUrl.urlSelector || '', (value: string) => {
          this.editingConfig.parserConfig.videoUrl.urlSelector = value
          this.markAsChanged()
        }, '视频播放链接的CSS选择器')
        // 解析模式
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
            .value(this.editingConfig.parserConfig.videoUrl.pattern || '选择器')
            .font({ size: 16 })
            .onSelect((index: number, value: string) => {
              this.editingConfig.parserConfig.videoUrl.pattern = value as 'regex' | 'javascript'
              this.markAsChanged()
            })
        }
        .enabled(false)
        .width('100%')
        // 后处理
        this.InputFieldWithTitle('后处理', this.editingConfig.parserConfig.videoUrl.postProcess || '', (value: string) => {
          this.editingConfig.parserConfig.videoUrl.postProcess = value
          this.markAsChanged()
        }, '视频链接后处理脚本')
        // 内嵌视频选择器
        this.InputFieldWithTitle('内嵌视频选择器(执行JS，最终需返回播放链接)', this.editingConfig.parserConfig.videoUrl.iframeSelector || '', (value: string) => {
          this.editingConfig.parserConfig.videoUrl.iframeSelector = value
          this.markAsChanged()
        }, '内嵌视频播放器的JS操作')
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
        .onChange((value: string) => {
          onChange(value)
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
