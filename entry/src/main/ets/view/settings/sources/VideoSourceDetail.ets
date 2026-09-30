import { DataSourceConfig, SelectorConfig, CategoryCardConfig } from "../../../api/DataSourceConfig"
import { EditField, EditToggleField, VideoSourceDetailViewModel } from "../../../viewmodel/VideoSourceDetailViewModel"
import TitleBar from "../../../components/TitleBar"
import { CollapsibleSection } from "../../../components/common/CollapsibleSection"
import { ToastUtil } from "../../../utils/ToastUtils"
import { AnimeState } from "../../../entryability/AnimeState"

// 源编辑页节标题：复用 CollapsibleSection 的色条标题风格（可折叠），
// 取消其内建水平/顶部边距，使色条与字段在 Tab 内边距下对齐
@ComponentV2
struct SourceEditSection {
  @Param title: string = ''
  @BuilderParam content: () => void = this.emptyContent

  @Builder emptyContent() {
  }

  build() {
    CollapsibleSection({
      title: this.title,
      titlePadding: { left: 0, right: 0, top: 0, bottom: 4 },
      content: (): void => {
        this.content()
      }
    })
  }
}

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
  private tabTitles: string[] = ['基本', '搜索', '主页', '周表', '详情', '视频']

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
        Column() {
          Row({ space: 12 }) {
            Row({ space: 5 }) {
              Toggle({ type: ToggleType.Checkbox, isOn: this.vm.editingConfig.enabled })
                .onChange((isOn: boolean) => {
                  this.vm.setEnabled(isOn)
                })
              Text('启用')
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
          .alignItems(VerticalAlign.Center)
          Row({ space: 12 }) {
            Row({ space: 5 }) {
              Toggle({ type: ToggleType.Checkbox, isOn: this.vm.editingConfig.defaultSource })
                .onChange((isOn: boolean) => {
                  this.vm.setDefaultSource(isOn)
                })
              Text('首页')
                .fontSize(16)
                .fontColor($r('app.color.color_text_major'))
            }
            .alignItems(VerticalAlign.Center)
            Row({ space: 5 }) {
              Toggle({ type: ToggleType.Checkbox, isOn: this.vm.isScheduleSource() })
                .onChange((isOn: boolean) => {
                  this.vm.setScheduleSource(isOn)
                })
              Text('周表')
                .fontSize(16)
                .fontColor($r('app.color.color_text_major'))
            }
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .backgroundColor($r('app.color.background_color_accent'))
        // Tab页签栏（胶囊按钮，可横向滚动）
        this.TabBarView()
        // Tab内容区域
        Tabs({ index: this.currentTabIndex }) {
          ForEach(this.tabTitles, (item: string, index: number) => {
            TabContent() {
              this.tabContentBuilder(item)
            }
            .align(Alignment.TopStart)
          }, (key: string) => key)
        }
        .barHeight(0)
        .vertical(false)
        .scrollable(true)
        .layoutWeight(1)
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

  // 胶囊风格页签栏：选中项主色底白字，未选中卡片底灰字，超出宽度可横向滚动
  @Builder
  TabBarView() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.tabTitles, (name: string, index: number) => {
          Text(name)
            .fontSize(15)
            .fontWeight(this.currentTabIndex == index ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.currentTabIndex == index ? Color.White : $r('app.color.color_text_normal'))
            .backgroundColor(this.currentTabIndex == index ? $r('app.color.primary_color') : $r('app.color.color_card'))
            .height(32)
            .padding({ left: 16, right: 16 })
            .borderRadius(16)
            .onClick(() => {
              this.currentTabIndex = index
            })
        }, (name: string) => `${name}_${this.currentTabIndex}`)
      }
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
  }

  @Builder
  tabContentBuilder(name: string) {
    if (name == '基本') {
      this.BasicInfoTab()
    } else if (name == '搜索') {
      this.SearchConfigTab()
    } else if (name == '主页') {
      this.HomepageConfigTab()
    } else if (name == '周表') {
      this.ScheduleConfigTab()
    } else if (name == '详情') {
      this.DetailConfigTab()
    } else {
      this.VideoConfigTab()
    }
  }

  // 字符串数组转下拉选项
  private toSelectOptions(options: string[]): SelectOption[] {
    const result: SelectOption[] = []
    for (const o of options) {
      result.push({ value: o })
    }
    return result
  }

  // 字段列表构建器（数据驱动渲染；支持勾选框、下拉选择行与条件展开行）
  @Builder
  FieldList(fields: EditField[]) {
    ForEach(fields, (item: EditField, index: number) => {
      if (item.visible === undefined || item.visible()) {
        if (item.select !== undefined) {
          Row() {
            Text(item.title)
              .fontSize(16)
              .fontColor($r('app.color.color_text_major'))
              .layoutWeight(1)
            Select(this.toSelectOptions(item.select.options))
              .selected(item.select.selected())
              .value(item.select.options[item.select.selected()])
              .font({ size: 16 })
              .onSelect((idx: number) => {
                if (item.select !== undefined) {
                  item.select.onChange(idx)
                }
              })
          }
          .width('100%')
        } else {
          this.InputFieldWithTitle(item.title, item.getValue(), item.setValue, item.placeholder,
            item.inputType ? item.inputType : 'text', false, item.toggle, '后处理')
        }
      }
    }, (item: EditField, index: number) => `${this.vm.sourceType}_${index}_${item.title}`)
  }

  // 视频信息选择器（数据驱动；可选扩展字段收进"更多字段"，配置了才展开）
  @Builder
  VideoInfoSelector(title: string, getConfig: () => SelectorConfig, setConfig: (c: SelectorConfig) => void,
    jsonMode: boolean) {
    SourceEditSection({ title: title }) {
      Column({ space: 12 }) {
        this.FieldList(this.vm.videoInfoFields(getConfig, setConfig, jsonMode))
        Row() {
          Text('更多字段')
            .fontSize(16)
            .fontColor($r('app.color.color_text_major'))
          Text('播放量 / 年份 / 月份 / 导演 / 声优 / 标签')
            .fontSize(12)
            .fontColor($r('app.color.color_text_minor'))
            .margin({ left: 8 })
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.vm.hasExtendedFields(getConfig()) })
            .onChange((isOn: boolean) => {
              this.vm.toggleExtendedFields(getConfig, setConfig, isOn)
            })
        }
        .width('100%')
        if (this.vm.hasExtendedFields(getConfig())) {
          this.FieldList(this.vm.extendedVideoInfoFields(getConfig, setConfig, jsonMode))
        }
      }
    }
  }

  // 详情扩展字段（仅更多字段开关 + 扩展组，无基础字段）
  @Builder
  DetailExtraSelector(getConfig: () => SelectorConfig, setConfig: (c: SelectorConfig) => void,
    jsonMode: boolean) {
    Column({ space: 12 }) {
      Row() {
        Text('更多字段')
          .fontSize(16)
          .fontColor($r('app.color.color_text_major'))
        Text('播放量 / 年份 / 月份 / 导演 / 声优 / 标签')
          .fontSize(12)
          .fontColor($r('app.color.color_text_minor'))
          .margin({ left: 8 })
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.vm.hasExtendedFields(getConfig()) })
          .onChange((isOn: boolean) => {
            this.vm.toggleExtendedFields(getConfig, setConfig, isOn)
          })
      }
      .width('100%')
      if (this.vm.hasExtendedFields(getConfig())) {
        this.FieldList(this.vm.extendedVideoInfoFields(getConfig, setConfig, jsonMode))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 单集选择器（数据驱动）
  @Builder
  EpisodeSelector(title: string, getConfig: () => SelectorConfig, setConfig: (c: SelectorConfig) => void,
    jsonMode: boolean) {
    SourceEditSection({ title: title }) {
      this.FieldList(this.vm.episodeItemFields(getConfig, setConfig, jsonMode))
    }
  }

  // 基本信息Tab
  @Builder
  BasicInfoTab() {
    Scroll() {
      Column({ space: 16 }) {
        this.FieldList(this.vm.basicFields())
        // JSON 模式：自定义请求头 + 登录配置
        if (this.vm.isJson()) {
          SourceEditSection({ title: '自定义请求头' }) {
            this.FieldList(this.vm.requestHeaderFields())
          }
          SourceEditSection({ title: '登录配置(API)' }) {
            Column({ space: 16 }) {
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
        SourceEditSection({ title: '搜索配置' }) {
          Column({ space: 16 }) {
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
            if (!this.vm.isJson()) {
              Row() {
                Text('高级字段')
                  .fontSize(16)
                  .fontColor($r('app.color.color_text_major'))
                Text('搜索验证码（图片 + 提交校验 + 会话重放）')
                  .fontSize(12)
                  .fontColor($r('app.color.color_text_minor'))
                  .margin({ left: 8 })
                Blank()
                Toggle({ type: ToggleType.Switch, isOn: this.vm.editingConfig.parserConfig.search.captcha !== undefined })
                  .onChange((isOn: boolean) => {
                    this.vm.setSearchCaptchaEnabled(isOn)
                  })
              }
              .width('100%')
              if (this.vm.editingConfig.parserConfig.search.captcha !== undefined) {
                this.FieldList(this.vm.captchaFields())
              }
            }
          }
        }
      }
      .tabContentStyles()
    }
  }

  @Builder
  HomepageConfigTab() {
    Scroll() {
      Column({ space: 16 }) {
        SourceEditSection({ title: '轮播图配置' }) {
          Column({ space: 16 }) {
            Row({space: 12}) {
              Row({space: 5}) {
                Toggle({ type: ToggleType.Checkbox, isOn: this.vm.editingConfig.parserConfig.homepage.banner.urlNeedBaseUrl })
                  .onChange((isOn: boolean) => {
                    this.vm.setBannerUrlNeedBaseUrl(isOn)
                  })
                Text('拼接基础URL')
                  .fontSize(16)
                  .fontColor($r('app.color.color_text_major'))
              }
              .justifyContent(FlexAlign.Start)
              .alignItems(VerticalAlign.Center)
              Row() {
                Toggle({ type: ToggleType.Checkbox, isOn: this.vm.editingConfig.parserConfig.homepage.banner.enabledHttps })
                  .onChange((isOn: boolean) => {
                    this.vm.setBannerEnabledHttps(isOn)
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
            this.FieldList(this.vm.bannerFields())
            this.VideoInfoSelector(this.vm.isJson() ? '轮播字段模板' : '轮播视频配置',
              () => this.vm.editingConfig.parserConfig.homepage.banner.itemSelectors,
              (config: SelectorConfig) => {
                this.vm.editingConfig.parserConfig.homepage.banner.itemSelectors = config
                this.vm.markAsChanged()
              }, this.vm.isJson())
          }
        }
        if (this.vm.isJson()) {
          SourceEditSection({ title: '分类卡片' }) {
            this.CategoryCardsEditor()
          }
        } else {
          SourceEditSection({ title: '分类卡片(独立页面)' }) {
            Column({ space: 16 }) {
              this.CategoryCardsEditor()
              if (this.vm.categoryCards.length > 0) {
                // 已配置卡片：同页分类配置整块隐藏，仅保留统一字段模板供卡片引用
                this.VideoInfoSelector('统一视频字段模板',
                  () => this.vm.editingConfig.parserConfig.homepage.category.videos.itemSelectors,
                  (config: SelectorConfig) => {
                    this.vm.setUnifiedItemSelectors(config)
                  }, false)
              }
            }
          }
          if (this.vm.categoryCards.length === 0) {
            SourceEditSection({ title: '分类配置(同页)' }) {
              Column({ space: 16 }) {
                Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
                  Row({space: 5}) {
                    Toggle({ type: ToggleType.Checkbox, isOn: this.vm.editingConfig.parserConfig.homepage.category.moreUrlNeedBaseUrl })
                      .onChange((isOn: boolean) => {
                        this.vm.setMoreUrlNeedBaseUrl(isOn)
                      })
                    Text('更多链接拼接URL')
                      .fontSize(15)
                      .fontColor($r('app.color.color_text_major'))
                  }
                  .alignItems(VerticalAlign.Center)
                  .margin({ right: 16 })
                  Row({space: 5}) {
                    Toggle({ type: ToggleType.Checkbox, isOn: this.vm.editingConfig.parserConfig.homepage.category.videos.urlNeedBaseUrl })
                      .onChange((isOn: boolean) => {
                        this.vm.setCategoryVideosUrlNeedBaseUrl(isOn)
                      })
                    Text('视频拼接基础URL')
                      .fontSize(15)
                      .fontColor($r('app.color.color_text_major'))
                  }
                  .alignItems(VerticalAlign.Center)
                  .margin({ right: 16 })
                  Row({space: 5}) {
                    Toggle({ type: ToggleType.Checkbox, isOn: this.vm.editingConfig.parserConfig.homepage.category.videos.enabledHttps })
                      .onChange((isOn: boolean) => {
                        this.vm.setCategoryVideosEnabledHttps(isOn)
                      })
                    Text('启用HTTPS')
                      .fontSize(15)
                      .fontColor($r('app.color.color_text_major'))
                  }
                  .alignItems(VerticalAlign.Center)
                  .margin({ right: 16 })
                }
                this.FieldList(this.vm.categoryHtmlFields())
                this.VideoInfoSelector('分类视频配置',
                  () => this.vm.editingConfig.parserConfig.homepage.category.videos.itemSelectors,
                  (config: SelectorConfig) => {
                    this.vm.setUnifiedItemSelectors(config)
                  }, false)
              }
            }
          }
        }
      }
      .tabContentStyles()
    }
  }

  // 周表配置页签（填写地址模板+列表选择器后即为可用周表源）
  @Builder
  ScheduleConfigTab() {
    Scroll() {
      Column({ space: 16 }) {
        SourceEditSection({ title: '周表配置' }) {
          Column({ space: 16 }) {
            Row({ space: 12 }) {
              Row({ space: 5 }) {
                Toggle({ type: ToggleType.Checkbox, isOn: this.vm.getScheduleUrlNeedBaseUrl() })
                  .onChange((isOn: boolean) => {
                    this.vm.setScheduleUrlNeedBaseUrl(isOn)
                  })
                Text('拼接基础URL')
                  .fontSize(15)
                  .fontColor($r('app.color.color_text_major'))
              }
              .justifyContent(FlexAlign.Start)
              .alignItems(VerticalAlign.Center)
              Row({ space: 5 }) {
                Toggle({ type: ToggleType.Checkbox, isOn: this.vm.getScheduleEnabledHttps() })
                  .onChange((isOn: boolean) => {
                    this.vm.setScheduleEnabledHttps(isOn)
                  })
                Text('启用HTTPS')
                  .fontSize(15)
                  .fontColor($r('app.color.color_text_major'))
              }
              .justifyContent(FlexAlign.Start)
              .alignItems(VerticalAlign.Center)
            }
            .justifyContent(FlexAlign.Start)
            .alignItems(VerticalAlign.Center)
            this.FieldList(this.vm.scheduleFields())
            this.VideoInfoSelector(this.vm.isJson() ? '周表字段模板' : '周表视频配置',
              () => this.vm.getScheduleItemSelectors(),
              (config: SelectorConfig) => {
                this.vm.setScheduleItemSelectors(config)
              }, this.vm.isJson())
          }
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
        .backgroundColor($r('app.color.start_window_background'))
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
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
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
        .margin({ right: 16 })
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
        .margin({ right: 16 })
        if (!this.vm.isJson()) {
          Row({ space: 5 }) {
            Toggle({ type: ToggleType.Checkbox, isOn: this.vm.isCardUnified(index) })
              .onChange((isOn: boolean) => {
                this.vm.setCardUseUnified(index, isOn)
              })
            Text('使用统一字段')
              .fontSize(15)
              .fontColor($r('app.color.color_text_major'))
          }
          .alignItems(VerticalAlign.Center)
          .margin({ right: 16 })
        }
      }
      if (this.vm.isJson() || !this.vm.isCardUnified(index)) {
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
    }
    .padding(12)
    .borderRadius(16)
    .backgroundColor($r('app.color.start_window_background'))
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  DetailConfigTab() {
    Scroll() {
      Column({ space: 16 }) {
        SourceEditSection({ title: this.vm.isJson() ? '详情字段模板' : '影片详情' }) {
          Column({ space: 16 }) {
            this.FieldList(this.vm.detailFields())
            this.DetailExtraSelector(
              () => this.vm.editingConfig.parserConfig.detail.extra ?? {},
              (config: SelectorConfig) => {
                this.vm.editingConfig.parserConfig.detail.extra = this.vm.hasExtendedFields(config) ? config : undefined
                this.vm.markAsChanged()
              }, this.vm.isJson())
          }
        }
        SourceEditSection({ title: this.vm.isJson() ? '选集配置(JSON)' : '剧集配置' }) {
          Column({ space: 16 }) {
            this.FieldList(this.vm.episodeListFields())
            this.EpisodeSelector(this.vm.isJson() ? '单集字段模板' : '单集剧集配置',
              () => this.vm.editingConfig.parserConfig.detail.episodes.itemSelectors,
              (config: SelectorConfig) => {
                this.vm.editingConfig.parserConfig.detail.episodes.itemSelectors = config
                this.vm.markAsChanged()
              }, this.vm.isJson())
          }
        }
        SourceEditSection({ title: this.vm.isJson() ? '推荐配置(JSON)' : '推荐配置' }) {
          Column({ space: 16 }) {
            Row({space: 12}) {
              Row({space: 5}) {
                Toggle({ type: ToggleType.Checkbox, isOn: this.vm.editingConfig.parserConfig.detail.recommends.urlNeedBaseUrl })
                  .onChange((isOn: boolean) => {
                    this.vm.setRecommendUrlNeedBaseUrl(isOn)
                  })
                Text('拼接基础URL')
                  .fontSize(15)
                  .fontColor($r('app.color.color_text_major'))
              }
              .alignItems(VerticalAlign.Center)
              Row({space: 5}) {
                Toggle({ type: ToggleType.Checkbox, isOn: this.vm.editingConfig.parserConfig.detail.recommends.enabledHttps })
                  .onChange((isOn: boolean) => {
                    this.vm.setRecommendEnabledHttps(isOn)
                  })
                Text('启用HTTPS')
                  .fontSize(15)
                  .fontColor($r('app.color.color_text_major'))
              }
              .alignItems(VerticalAlign.Center)
            }
            .alignItems(VerticalAlign.Center)
            this.FieldList(this.vm.recommendFields())
            this.VideoInfoSelector(this.vm.isJson() ? '推荐字段模板' : '推荐番剧配置',
              () => this.vm.editingConfig.parserConfig.detail.recommends.itemSelectors,
              (config: SelectorConfig) => {
                this.vm.editingConfig.parserConfig.detail.recommends.itemSelectors = config
                this.vm.markAsChanged()
              }, this.vm.isJson())
          }
        }
      }
      .tabContentStyles()
    }
  }

  // 视频配置Tab
  @Builder
  VideoConfigTab() {
    Scroll() {
      Column({ space: 16 }) {
        // 解析模式（第一行，决定下方显示哪些输入框）
        if (this.vm.isJson()) {
          // JSON 模式：JSON接口 / 链接透传（透传时可配合内嵌视频解析JS）
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
          // HTML 模式：解析模式（选择器 / 正则表达式）
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
              .selected(this.vm.editingConfig.parserConfig.videoUrl.pattern === 'regex' ? 1 : 0)
              .value(this.vm.editingConfig.parserConfig.videoUrl.pattern === 'regex' ? '正则表达式' : '选择器')
              .font({ size: 16 })
              .onSelect((index: number) => {
                this.vm.setVideoPattern(index === 1 ? 'regex' : '')
              })
          }
          .width('100%')
        }
        this.FieldList(this.vm.videoFields())
      }
      .tabContentStyles()
    }
  }

  // 带标题的输入框（可选：标题行右侧内联勾选框，如「后处理」）
  @Builder
  InputFieldWithTitle(title: string, value: string, onChange: (value: string) => void, placeholder: string,
    inputType: string = 'text', disabled: boolean = false,
    toggle?: EditToggleField, toggleLabel: string = '') {
    Column({ space: 8 }) {
      Row() {
        Text(title)
          .fontSize(16)
          .fontColor($r('app.color.color_text_major'))
          .textAlign(TextAlign.Start)
          .layoutWeight(1)
        if (toggle !== undefined) {
          Row({ space: 5 }) {
            Toggle({ type: ToggleType.Checkbox, isOn: toggle.isOn() })
              .onChange((isOn: boolean) => {
                if (toggle !== undefined) {
                  toggle.onChange(isOn)
                }
              })
            Text(toggleLabel)
              .fontSize(14)
              .fontColor($r('app.color.color_text_major'))
          }
          .alignItems(VerticalAlign.Center)
        }
      }
      .width('100%')
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


@Extend(Column)
function tabContentStyles() {
  .justifyContent(FlexAlign.Start)
  .alignItems(HorizontalAlign.Start)
  .padding({ left: 16, right: 16, top: 16, bottom: 16 })
}
