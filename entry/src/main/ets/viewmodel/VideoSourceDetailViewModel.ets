import { DataSourceConfig, SelectorConfig, ProcessConfig, CategoryCardConfig, LoginConfig, VideoConfig, ParserConfig, CategoryConfig, RecommendConfig } from "../api/DataSourceConfig"
import { dataSourceManager } from "../api/DataSourceManager"
import { VIDEO_SOURCE_EVENT } from "../utils/EventBus"
import { ToastUtil } from "../utils/ToastUtils"

/** 选择器字段的复杂配置形态（与 DataSourceConfig.SelectorConfig 的对象分支结构一致） */
export interface SelectorFieldConfig {
  selector: string
  postProcess?: ProcessConfig
}

/** 选择器字段取值：简单字符串 或 带 postProcess 的复杂配置 */
export type SelectorValue = string | SelectorFieldConfig | undefined

/** 数据驱动的编辑字段描述：取值/写值均为闭包，调用时实时读取状态 */
export interface EditField {
  title: string
  placeholder: string
  getValue: () => string
  setValue: (value: string) => void
  inputType?: string
}

/** 新建数据源的默认配置 */
function createDefaultConfig(): DataSourceConfig {
  return {
    key: '',
    name: '',
    group: '',
    baseUrl: '',
    version: '1.0.0',
    description: '',
    enabled: true,
    priority: 100,
    defaultSource: false,
    parserConfig: {
      sourceType: 'html',
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
          },
          cards: []
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

/**
 * 数据源编辑页 ViewModel
 * 持有编辑状态（深拷贝配置 + 独立编辑态）与全部字段描述，View 只负责渲染
 */
@ObservedV2
export class VideoSourceDetailViewModel {
  // 编辑状态的配置（深拷贝避免直接修改原始数据）
  @Trace public editingConfig: DataSourceConfig = createDefaultConfig()
  // 是否有未保存修改
  @Trace public hasChanges: boolean = false
  // 保存中
  @Trace public isLoading: boolean = false
  // 源模式：html / json（独立状态驱动顶部选择器与各Tab内容切换）
  @Trace public sourceType: string = 'html'
  // 自定义请求头文本（每行一个，格式：名称: 值），保存时解析回 requestHeaders
  @Trace public requestHeadersText: string = ''
  // JSON 模式首页分类卡片（独立状态驱动增删，保存时写回配置）
  @Trace public categoryCards: CategoryCardConfig[] = []
  // 卡片 ForEach 稳定 key（与 categoryCards 下标对应）
  public cardKeys: string[] = []
  private cardKeySeq: number = 0
  // 原始配置 key（'new' 表示新建）
  public originalKey: string = ''

  /** 初始化：key='new' 新建，否则编辑现有配置 */
  init(sourceConfig: DataSourceConfig) {
    this.originalKey = sourceConfig.key
    if (sourceConfig.key === 'new') {
      this.initNewSource()
    } else {
      this.initEditSource(sourceConfig)
    }
  }

  // 是否 JSON 模式
  isJson(): boolean {
    return this.sourceType === 'json'
  }

  // ---------- 状态更新 ----------

  // 切换启用状态
  setEnabled(isOn: boolean) {
    if (isOn === this.editingConfig.enabled) {
      return
    }
    this.editingConfig.enabled = isOn
    this.markAsChanged()
  }

  // 切换源模式（html / json）
  setSourceType(newType: string) {
    if (newType === this.sourceType) {
      return
    }
    this.sourceType = newType
    this.editingConfig.parserConfig.sourceType = newType as 'html' | 'json'
    this.markAsChanged()
  }

  // 切换默认数据源
  setDefaultSource(isOn: boolean) {
    if (isOn === this.editingConfig.defaultSource) {
      return
    }
    this.editingConfig.defaultSource = isOn
    this.markAsChanged()
  }

  // 切换搜索拼接基础URL
  setSearchUrlNeedBaseUrl(isOn: boolean) {
    const videos = this.editingConfig.parserConfig.search.videos
    if (isOn === videos.urlNeedBaseUrl) {
      return
    }
    videos.urlNeedBaseUrl = isOn
    this.markAsChanged()
  }

  // 切换搜索启用HTTPS
  setSearchEnabledHttps(isOn: boolean) {
    const videos = this.editingConfig.parserConfig.search.videos
    if (isOn === videos.enabledHttps) {
      return
    }
    videos.enabledHttps = isOn
    this.markAsChanged()
  }

  // 切换登录配置开关（整体替换配置对象保证条件渲染刷新）
  setLoginEnabled(isOn: boolean) {
    if (isOn === (this.editingConfig.login !== undefined)) {
      return
    }
    if (isOn) {
      const login: LoginConfig = {
        type: 'api',
        loginUrl: '',
        usernameField: 'username',
        passwordField: 'password',
        tokenPath: 'data.token',
        authHeaderName: 'Authorization',
        authValueTemplate: '{token}'
      }
      this.replaceConfig((config: DataSourceConfig) => {
        config.login = login
      })
    } else {
      this.replaceConfig((config: DataSourceConfig) => {
        config.login = undefined
      })
    }
    this.markAsChanged()
  }

  // 设置解析模式（正则/选择器/JSON/链接透传）
  setVideoPattern(value: string) {
    this.editingConfig.parserConfig.videoUrl.pattern = value as 'regex' | 'javascript' | 'json' | 'link'
    this.markAsChanged()
  }

  // 添加分类卡片（默认值按源模式区分）
  addCategoryCard() {
    const card: CategoryCardConfig = {
      title: '',
      url: '',
      moreUrl: '',
      listPath: this.isJson() ? 'data.list' : undefined,
      listSelector: this.isJson() ? undefined : '',
      itemSelectors: {},
      urlNeedBaseUrl: !this.isJson(),
      enabledHttps: true
    }
    this.cardKeys.push(`card_${++this.cardKeySeq}`)
    this.categoryCards = this.categoryCards.concat([card])
    this.markAsChanged()
  }

  // 删除分类卡片
  deleteCategoryCard(index: number) {
    if (index < 0 || index >= this.categoryCards.length) {
      return
    }
    this.cardKeys.splice(index, 1)
    const arr = this.categoryCards.slice()
    arr.splice(index, 1)
    this.categoryCards = arr
    this.markAsChanged()
  }

  // 切换分类卡片开关（替换数组元素保证UI刷新）
  setCategoryCardToggle(index: number, urlNeedBaseUrl?: boolean, enabledHttps?: boolean) {
    const old = this.categoryCards[index]
    if (!old) {
      return
    }
    const updated = this.copyCard(old)
    if (urlNeedBaseUrl !== undefined) {
      updated.urlNeedBaseUrl = urlNeedBaseUrl
    }
    if (enabledHttps !== undefined) {
      updated.enabledHttps = enabledHttps
    }
    const arr = this.categoryCards.slice()
    arr[index] = updated
    this.categoryCards = arr
    this.markAsChanged()
  }

  // ---------- 保存 ----------

  // 保存配置
  async saveConfig() {
    if (!this.editingConfig.key || !this.editingConfig.name) {
      ToastUtil.showToast({ message: "请填写必要信息" })
      return
    }
    try {
      this.isLoading = true
      this.syncTransientToConfig()
      if (this.originalKey === 'new') {
        // 添加新数据源
        try {
          await dataSourceManager.addDataSource(this.editingConfig)
          // 通知数据源变更
          VIDEO_SOURCE_EVENT.emit()
          ToastUtil.showToast({ message: "数据源添加成功" })
        } catch (err) {
          console.error(`${err}`)
          ToastUtil.showToast({ message: `${this.editingConfig.key} 不唯一` })
        }
      } else {
        // 更新现有数据源
        await dataSourceManager.updateDataSource(this.originalKey, this.editingConfig)
        // 通知数据源变更
        VIDEO_SOURCE_EVENT.emit()
        ToastUtil.showToast({ message: "数据源更新成功" })
      }
      this.hasChanges = false
      // AnimeState.pageStack.pop()
    } catch (error) {
      ToastUtil.showToast({ message: "保存失败: " + error.message })
    } finally {
      this.isLoading = false
    }
  }

  // 保存前把独立编辑状态写回配置
  private syncTransientToConfig() {
    this.editingConfig.parserConfig.sourceType = this.sourceType === 'json' ? 'json' : 'html'
    this.editingConfig.parserConfig.requestHeaders = this.parseHeadersText(this.requestHeadersText)
    if (this.editingConfig.parserConfig.homepage && this.editingConfig.parserConfig.homepage.category) {
      this.editingConfig.parserConfig.homepage.category.cards =
        this.categoryCards.length > 0 ? this.categoryCards : undefined
    }
  }

  // ---------- 私有工具 ----------

  // 标记为已更改
  markAsChanged() {
    this.hasChanges = true
  }

  // 整体替换编辑配置（深拷贝后修改再赋值，触发 @Trace 通知条件渲染）
  private replaceConfig(mutate: (config: DataSourceConfig) => void) {
    const next: DataSourceConfig = JSON.parse(JSON.stringify(this.editingConfig))
    mutate(next)
    this.editingConfig = next
  }

  // 初始化新数据源
  private initNewSource() {
    this.editingConfig = createDefaultConfig()
    this.sourceType = 'html'
    this.requestHeadersText = ''
    this.categoryCards = []
    this.cardKeys = []
    this.cardKeySeq = 0
  }

  // 初始化编辑数据源
  private initEditSource(sourceConfig: DataSourceConfig) {
    // 深拷贝传入的配置，避免直接修改原始数据
    this.editingConfig = JSON.parse(JSON.stringify(sourceConfig))
    // 补齐可选缺失的配置段：导入的配置可能省略（如 tvtfun 无 recommends），
    // 而编辑页字段闭包会直接解引用这些对象，缺失会导致运行时 TypeError 闪退
    if (!this.editingConfig.parserConfig) {
      this.editingConfig.parserConfig = createDefaultConfig().parserConfig
    }
    this.ensureEditableSections(this.editingConfig.parserConfig)
    const parser = this.editingConfig.parserConfig
    this.sourceType = parser && parser.sourceType === 'json' ? 'json' : 'html'
    this.requestHeadersText = this.headersToText(parser ? parser.requestHeaders : undefined)
    const cards = parser && parser.homepage && parser.homepage.category ? parser.homepage.category.cards : undefined
    const copied: CategoryCardConfig[] = []
    if (cards) {
      for (const card of cards) {
        copied.push(this.copyCard(card))
      }
    }
    this.categoryCards = copied
    this.cardKeys = copied.map((item: CategoryCardConfig, index: number) => `card_${index}`)
    this.cardKeySeq = copied.length
  }

  // 补齐编辑界面会解引用的可选配置段（仅补缺，不覆盖已有值）
  private ensureEditableSections(parser: ParserConfig) {
    if (!parser.search) {
      parser.search = { videos: this.defaultVideoConfig() }
    } else if (!parser.search.videos) {
      parser.search.videos = this.defaultVideoConfig()
    }
    const defaultCategory = (): CategoryConfig => {
      return {
        title: '', titles: '', moreUrl: '', moreUrlNeedBaseUrl: true, videoLists: '',
        videos: this.defaultVideoConfig(), cards: []
      }
    }
    if (!parser.homepage) {
      parser.homepage = { banner: this.defaultVideoConfig(), category: defaultCategory() }
    } else {
      if (!parser.homepage.banner) {
        parser.homepage.banner = this.defaultVideoConfig()
      }
      if (!parser.homepage.category) {
        parser.homepage.category = defaultCategory()
      } else if (!parser.homepage.category.videos) {
        parser.homepage.category.videos = this.defaultVideoConfig()
      }
    }
    const defaultRecommends = (): RecommendConfig => {
      return { listSelector: '', itemSelectors: {}, urlNeedBaseUrl: true, enabledHttps: true }
    }
    if (!parser.detail) {
      parser.detail = {
        titleSelector: '', descSelector: '', coverSelector: '',
        episodes: { itemSelector: '', itemSelectors: {} },
        recommends: defaultRecommends()
      }
    } else {
      if (!parser.detail.episodes) {
        parser.detail.episodes = { itemSelector: '', itemSelectors: {} }
      }
      if (!parser.detail.recommends) {
        parser.detail.recommends = defaultRecommends()
      }
    }
    if (!parser.videoUrl) {
      parser.videoUrl = {}
    }
  }

  // 默认视频列表配置段（补齐缺失段用）
  private defaultVideoConfig(): VideoConfig {
    return { urlTemplate: '', listSelector: '', urlNeedBaseUrl: true, enabledHttps: true, itemSelectors: {} }
  }

  // 复制分类卡片（浅拷贝字段，itemSelectors 保持引用）
  private copyCard(card: CategoryCardConfig): CategoryCardConfig {
    return {
      title: card.title,
      url: card.url,
      moreUrl: card.moreUrl,
      listPath: card.listPath,
      listSelector: card.listSelector,
      itemSelectors: card.itemSelectors,
      urlNeedBaseUrl: card.urlNeedBaseUrl,
      enabledHttps: card.enabledHttps
    }
  }

  // requestHeaders -> "名称: 值" 文本
  private headersToText(headers?: Record<string, string>): string {
    if (!headers) {
      return ''
    }
    const lines: string[] = []
    const entries = Object.entries(headers)
    for (const entry of entries) {
      lines.push(`${entry[0]}: ${entry[1]}`)
    }
    return lines.join('\n')
  }

  // "名称: 值" 文本 -> requestHeaders
  private parseHeadersText(text: string): Record<string, string> | undefined {
    const result: Record<string, string> = {}
    const lines = text.split('\n')
    for (const line of lines) {
      const trimmed = line.trim()
      if (!trimmed) {
        continue
      }
      const idx = trimmed.indexOf(':')
      if (idx <= 0) {
        continue
      }
      result[trimmed.substring(0, idx).trim()] = trimmed.substring(idx + 1).trim()
    }
    return Object.keys(result).length > 0 ? result : undefined
  }

  /** 提取选择器字段的文本用于输入框回显 */
  private selectorToText(value: SelectorValue): string {
    if (typeof value === 'string') {
      return value
    }
    if (value !== undefined) {
      return value.selector || ''
    }
    return ''
  }

  /** 更新选择器字段：原值为复杂配置时仅替换 selector，保留 postProcess */
  private updateSelectorValue(value: string, old: SelectorValue): string | SelectorFieldConfig {
    if (typeof old === 'object') {
      const result: SelectorFieldConfig = { selector: value }
      if (old.postProcess !== undefined) {
        result.postProcess = old.postProcess
      }
      return result
    }
    return value
  }

  // 构造编辑字段描述
  private field(title: string, placeholder: string, getValue: () => string,
    setValue: (value: string) => void, inputType?: string): EditField {
    const result: EditField = {
      title: title,
      placeholder: placeholder,
      getValue: getValue,
      setValue: setValue,
      inputType: inputType
    }
    return result
  }

  // ---------- 字段列表（数据驱动） ----------

  // 基本信息字段
  basicFields(): EditField[] {
    return [
      this.field('Key(请确保唯一性)', '数据源唯一标识',
        () => this.editingConfig.key,
        (v: string) => { this.editingConfig.key = v; this.markAsChanged() }),
      this.field('基础URL', '数据源基础地址，如：https://example.com',
        () => this.editingConfig.baseUrl,
        (v: string) => { this.editingConfig.baseUrl = v; this.markAsChanged() }),
      this.field('名称', '数据源显示名称',
        () => this.editingConfig.name,
        (v: string) => {
          // 名称联动标题栏，整体替换保证 @Trace 通知
          this.replaceConfig((config: DataSourceConfig) => {
            config.name = v
          })
          this.markAsChanged()
        }),
      this.field('版本', '数据源版本号, 只能写数字哦，格式：x.x.x',
        () => this.editingConfig.version,
        (v: string) => { this.editingConfig.version = v; this.markAsChanged() }),
      this.field('描述', '介绍一下视频源',
        () => this.editingConfig.description,
        (v: string) => { this.editingConfig.description = v; this.markAsChanged() }),
      this.field('分组', '数据源所属分组',
        () => this.editingConfig.group,
        (v: string) => { this.editingConfig.group = v; this.markAsChanged() }),
      this.field('优先级', '数值越小优先级越高',
        () => this.editingConfig.priority.toString(),
        (v: string) => {
          const num = parseInt(v)
          if (!isNaN(num)) {
            this.editingConfig.priority = num
            this.markAsChanged()
          }
        }, 'number')
    ]
  }

  // 自定义请求头字段（JSON 模式）
  requestHeaderFields(): EditField[] {
    return [
      this.field('请求头列表', '每行一个，格式：名称: 值',
        () => this.requestHeadersText,
        (v: string) => { this.requestHeadersText = v; this.markAsChanged() })
    ]
  }

  // 登录配置字段（JSON 模式）
  loginFields(): EditField[] {
    return [
      this.field('登录接口地址', '如 /api/auth/login，相对路径将拼接基础URL',
        () => this.editingConfig.login ? (this.editingConfig.login.loginUrl || '') : '',
        (v: string) => { if (this.editingConfig.login) { this.editingConfig.login.loginUrl = v; this.markAsChanged() } }),
      this.field('用户名字段', '请求体中用户名字段名，默认 username',
        () => this.editingConfig.login ? (this.editingConfig.login.usernameField || '') : '',
        (v: string) => { if (this.editingConfig.login) { this.editingConfig.login.usernameField = v; this.markAsChanged() } }),
      this.field('密码字段', '请求体中密码字段名，默认 password',
        () => this.editingConfig.login ? (this.editingConfig.login.passwordField || '') : '',
        (v: string) => { if (this.editingConfig.login) { this.editingConfig.login.passwordField = v; this.markAsChanged() } }),
      this.field('凭证JSON路径', '登录响应中凭证的JSON路径，默认 data.token',
        () => this.editingConfig.login ? (this.editingConfig.login.tokenPath || '') : '',
        (v: string) => { if (this.editingConfig.login) { this.editingConfig.login.tokenPath = v; this.markAsChanged() } }),
      this.field('凭证请求头名', '携带凭证的请求头名，默认 Authorization',
        () => this.editingConfig.login ? (this.editingConfig.login.authHeaderName || '') : '',
        (v: string) => { if (this.editingConfig.login) { this.editingConfig.login.authHeaderName = v; this.markAsChanged() } }),
      this.field('凭证请求头模板', '请求头值模板，默认 {token}',
        () => this.editingConfig.login ? (this.editingConfig.login.authValueTemplate || '') : '',
        (v: string) => { if (this.editingConfig.login) { this.editingConfig.login.authValueTemplate = v; this.markAsChanged() } })
    ]
  }

  // 搜索配置字段
  searchFields(): EditField[] {
    const json = this.isJson()
    return [
      this.field('搜索链接模板',
        json ? '如 /api/videos/search?q={keyword}&page={page}' : '搜索URL模板，如：/search?q={keyword}&page={page}',
        () => this.editingConfig.parserConfig.search.videos.urlTemplate,
        (v: string) => { this.editingConfig.parserConfig.search.videos.urlTemplate = v; this.markAsChanged() }),
      this.field(json ? '列表JSON路径' : '列表选择器',
        json ? '搜索结果列表在响应中的JSON路径，如 data.list' : '搜索结果列表的CSS选择器',
        () => this.editingConfig.parserConfig.search.videos.listSelector,
        (v: string) => { this.editingConfig.parserConfig.search.videos.listSelector = v; this.markAsChanged() })
    ]
  }

  // 轮播图字段
  bannerFields(): EditField[] {
    const json = this.isJson()
    return [
      this.field(json ? '接口地址模板' : '基础URL拼接模板',
        json ? '轮播数据接口地址，支持 {today} 占位符(1=周一..7=周日)' : '轮播图的基础链接拼接模板',
        () => this.editingConfig.parserConfig.homepage.banner.urlTemplate,
        (v: string) => { this.editingConfig.parserConfig.homepage.banner.urlTemplate = v; this.markAsChanged() }),
      this.field(json ? '列表JSON路径' : '列表选择器',
        json ? '轮播列表在响应中的JSON路径，如 data.list' : 'Banner列表的CSS选择器',
        () => this.editingConfig.parserConfig.homepage.banner.listSelector,
        (v: string) => { this.editingConfig.parserConfig.homepage.banner.listSelector = v; this.markAsChanged() })
    ]
  }

  // 分类配置字段（HTML 模式）
  categoryHtmlFields(): EditField[] {
    return [
      this.field('标题选择器', '分类标题的CSS选择器',
        () => this.editingConfig.parserConfig.homepage.category.title,
        (v: string) => { this.editingConfig.parserConfig.homepage.category.title = v; this.markAsChanged() }),
      this.field('标题列表选择器', '分类标题列表的CSS选择器',
        () => this.editingConfig.parserConfig.homepage.category.titles,
        (v: string) => { this.editingConfig.parserConfig.homepage.category.titles = v; this.markAsChanged() }),
      this.field('更多链接选择器', '分类更多链接的CSS选择器',
        () => this.editingConfig.parserConfig.homepage.category.moreUrl,
        (v: string) => { this.editingConfig.parserConfig.homepage.category.moreUrl = v; this.markAsChanged() }),
      this.field('视频列表容器', '分类视频列表容器的CSS选择器',
        () => this.editingConfig.parserConfig.homepage.category.videoLists,
        (v: string) => { this.editingConfig.parserConfig.homepage.category.videoLists = v; this.markAsChanged() })
    ]
  }

  // 详情字段（模式自适应：HTML=CSS选择器 / JSON=字段模板）
  detailFields(): EditField[] {
    const json = this.isJson()
    const detail = () => this.editingConfig.parserConfig.detail
    const fields: EditField[] = [
      this.field(json ? '标题模板' : '标题选择器',
        json ? '如 {title}' : '视频详情页标题的CSS选择器',
        () => detail().titleSelector,
        (v: string) => { detail().titleSelector = v; this.markAsChanged() }),
      this.field(json ? '描述模板' : '描述选择器',
        json ? '如 {description}' : '视频详情页描述的CSS选择器',
        () => detail().descSelector,
        (v: string) => { detail().descSelector = v; this.markAsChanged() }),
      this.field(json ? '封面模板' : '封面选择器',
        json ? '如 {cover_url}，相对路径将拼接基础URL' : '视频详情页封面的CSS选择器',
        () => detail().coverSelector,
        (v: string) => { detail().coverSelector = v; this.markAsChanged() }),
      this.field(json ? '分类模板(可选)' : '分类选择器(可选)',
        json ? '如 {categories}' : '视频分类的CSS选择器',
        () => detail().categorySelector || '',
        (v: string) => { detail().categorySelector = v; this.markAsChanged() }),
      this.field(json ? '导演模板(可选)' : '导演选择器(可选)',
        json ? '如 {director}' : '导演信息的CSS选择器',
        () => detail().directorSelector || '',
        (v: string) => { detail().directorSelector = v; this.markAsChanged() }),
      this.field(json ? '更新时间模板(可选)' : '更新时间选择器(可选)',
        json ? '如 {publish_date}' : '更新时间的CSS选择器',
        () => detail().updateTimeSelector || '',
        (v: string) => { detail().updateTimeSelector = v; this.markAsChanged() }),
      this.field(json ? '主演模板(可选)' : '主演选择器(可选)',
        json ? '如 {actor}' : '主演信息的CSS选择器',
        () => detail().protagonistSelector || '',
        (v: string) => { detail().protagonistSelector = v; this.markAsChanged() })
    ]
    if (json) {
      fields.push(this.field('封面后处理JSON(可选)', '封面地址后处理配置的JSON文本，如 {"type":"string","stringProcess":{"type":"replace","search":"^https://old/(.+)$","replace":"https://new/$1","flags":""}}，留空清除',
        () => detail().coverPostProcess ? JSON.stringify(detail().coverPostProcess) : '',
        (v: string) => {
          const trimmed = v.trim()
          if (!trimmed) {
            detail().coverPostProcess = undefined
            this.markAsChanged()
            return
          }
          try {
            const parsed: ProcessConfig = JSON.parse(trimmed)
            detail().coverPostProcess = parsed
            this.markAsChanged()
          } catch (e) {
            // 非法JSON忽略，保留原值
          }
        }))
    }
    return fields
  }

  // 剧集列表字段（模式自适应：HTML=选择器组 / JSON=选集接口配置）
  episodeListFields(): EditField[] {
    const json = this.isJson()
    const episodes = () => this.editingConfig.parserConfig.detail.episodes
    if (json) {
      return [
        this.field('路线数组路径', '详情响应中的路线数组路径，如 play_from',
          () => episodes().jsonRoutesPath || '',
          (v: string) => { episodes().jsonRoutesPath = v; this.markAsChanged() }),
        this.field('路线标题模板', '如 {title}，可用详情字段与路线项字段',
          () => episodes().jsonRouteTitleTemplate || '',
          (v: string) => { episodes().jsonRouteTitleTemplate = v; this.markAsChanged() }),
        this.field('选集接口地址模板', '如 {baseUrl}/api/videos/{id}/sections?player_code={code}&page=1&page_size=100',
          () => episodes().jsonSectionsUrlTemplate || '',
          (v: string) => { episodes().jsonSectionsUrlTemplate = v; this.markAsChanged() }),
        this.field('选集列表JSON路径', '选集列表在响应中的JSON路径，默认 data.list',
          () => episodes().jsonListPath || '',
          (v: string) => { episodes().jsonListPath = v; this.markAsChanged() })
      ]
    }
    return [
      this.field('多路线标题选择器(可选)', '多路线标题的CSS选择器',
        () => episodes().routeTitlesSelector || '',
        (v: string) => { episodes().routeTitlesSelector = v; this.markAsChanged() }),
      this.field('多路线剧集选择器(可选)', '多路线剧集的CSS选择器',
        () => episodes().routeContainersSelector || '',
        (v: string) => { episodes().routeContainersSelector = v; this.markAsChanged() }),
      this.field('单路线剧集选择器(仅单路线时必选)', '单路线剧集的CSS选择器',
        () => episodes().containerSelector || '',
        (v: string) => { episodes().containerSelector = v; this.markAsChanged() }),
      this.field('剧集列表选择器', '剧集列表的CSS选择器',
        () => episodes().itemSelector,
        (v: string) => { episodes().itemSelector = v; this.markAsChanged() })
    ]
  }

  // 推荐配置字段（模式自适应）
  recommendFields(): EditField[] {
    const json = this.isJson()
    const recommends = () => this.editingConfig.parserConfig.detail.recommends
    if (json) {
      return [
        this.field('推荐接口地址模板', '如 {baseUrl}/api/videos/{id}/recommendations',
          () => recommends().jsonUrlTemplate || '',
          (v: string) => { recommends().jsonUrlTemplate = v; this.markAsChanged() }),
        this.field('推荐列表JSON路径', '推荐列表在响应中的JSON路径，如 data.list',
          () => recommends().listSelector,
          (v: string) => { recommends().listSelector = v; this.markAsChanged() })
      ]
    }
    return [
      this.field('推荐列表选择器', '推荐视频列表的CSS选择器',
        () => recommends().listSelector,
        (v: string) => { recommends().listSelector = v; this.markAsChanged() })
    ]
  }

  // 视频播放字段（模式自适应）
  videoFields(): EditField[] {
    const json = this.isJson()
    const videoUrl = () => this.editingConfig.parserConfig.videoUrl
    if (json) {
      return [
        this.field('播放地址JSON路径', '播放地址在响应中的JSON路径，默认 data.url',
          () => videoUrl().valuePath || '',
          (v: string) => { videoUrl().valuePath = v; this.markAsChanged() }),
        this.field('后处理', '视频链接后处理脚本',
          () => videoUrl().postProcess || '',
          (v: string) => { videoUrl().postProcess = v; this.markAsChanged() }),
        this.field('内嵌视频解析JS(可选，解析模式=链接透传时生效)', '在播放页内执行的JS，最终需返回真实播放地址；返回ERR_开头字符串表示失败原因',
          () => videoUrl().iframeSelector || '',
          (v: string) => { videoUrl().iframeSelector = v; this.markAsChanged() })
      ]
    }
    return [
      this.field('播放链接选择器', '视频播放链接的CSS选择器',
        () => videoUrl().urlSelector || '',
        (v: string) => { videoUrl().urlSelector = v; this.markAsChanged() }),
      this.field('后处理', '视频链接后处理脚本',
        () => videoUrl().postProcess || '',
        (v: string) => { videoUrl().postProcess = v; this.markAsChanged() }),
      this.field('内嵌视频选择器(执行JS，最终需返回播放链接)', '内嵌视频播放器的JS操作',
        () => videoUrl().iframeSelector || '',
        (v: string) => { videoUrl().iframeSelector = v; this.markAsChanged() })
    ]
  }

  // 视频信息选择器字段（模式自适应提示）
  videoInfoFields(getConfig: () => SelectorConfig, setConfig: (c: SelectorConfig) => void,
    jsonMode: boolean): EditField[] {
    const titleHint = jsonMode ? '字段模板，如 {title}' : '番剧名称的CSS选择器'
    const imgUrlHint = jsonMode ? '字段模板，如 {cover_url}' : '封面图片链接的CSS选择器'
    const urlHint = jsonMode ? '字段模板，如 {baseUrl}/api/videos/{id}' : '番剧详情链接的CSS选择器'
    const episodeHint = jsonMode ? '字段模板，如 {remarks}' : '剧集数量的CSS选择器'
    return [
      this.field('番剧名', titleHint,
        () => this.selectorToText(getConfig().title),
        (v: string) => {
          const c = getConfig()
          const next: SelectorConfig = {
            title: this.updateSelectorValue(v, c.title),
            url: c.url || '',
            imgUrl: c.imgUrl || '',
            episode: c.episode || ''
          }
          setConfig(next)
        }),
      this.field('封面链接', imgUrlHint,
        () => this.selectorToText(getConfig().imgUrl),
        (v: string) => {
          const c = getConfig()
          const next: SelectorConfig = {
            title: c.title || '',
            url: c.url || '',
            imgUrl: this.updateSelectorValue(v, c.imgUrl),
            episode: c.episode || ''
          }
          setConfig(next)
        }),
      this.field('番剧链接', urlHint,
        () => this.selectorToText(getConfig().url),
        (v: string) => {
          const c = getConfig()
          const next: SelectorConfig = {
            title: c.title || '',
            url: this.updateSelectorValue(v, c.url),
            imgUrl: c.imgUrl || '',
            episode: c.episode || ''
          }
          setConfig(next)
        }),
      this.field('剧集数', episodeHint,
        () => this.selectorToText(getConfig().episode),
        (v: string) => {
          const c = getConfig()
          const next: SelectorConfig = {
            title: c.title || '',
            url: c.url || '',
            imgUrl: c.imgUrl || '',
            episode: this.updateSelectorValue(v, c.episode)
          }
          setConfig(next)
        }),
      this.field('封面后处理JSON(可选)', '封面地址后处理配置的JSON文本，如 {"type":"string","stringProcess":{"type":"replace","search":"^https://old/(.+)$","replace":"https://new/$1","flags":""}}，留空清除',
        () => {
          const img = getConfig().imgUrl
          if (typeof img === 'object' && img !== undefined && img.postProcess !== undefined) {
            return JSON.stringify(img.postProcess)
          }
          return ''
        },
        (v: string) => {
          const c = getConfig()
          const selector = this.selectorToText(c.imgUrl)
          const trimmed = v.trim()
          if (!trimmed) {
            const next: SelectorConfig = {
              title: c.title || '',
              url: c.url || '',
              imgUrl: selector,
              episode: c.episode || ''
            }
            setConfig(next)
            this.markAsChanged()
            return
          }
          try {
            const parsed: ProcessConfig = JSON.parse(trimmed)
            const next: SelectorConfig = {
              title: c.title || '',
              url: c.url || '',
              imgUrl: { selector: selector, postProcess: parsed },
              episode: c.episode || ''
            }
            setConfig(next)
            this.markAsChanged()
          } catch (e) {
            // 非法JSON忽略，保留原值
          }
        })
    ]
  }

  // 单集选择器字段（模式自适应提示）
  episodeItemFields(getConfig: () => SelectorConfig, setConfig: (c: SelectorConfig) => void,
    jsonMode: boolean): EditField[] {
    const titleHint = jsonMode ? '字段模板，如 {title}' : '剧集标题的CSS选择器'
    const urlHint = jsonMode ? '字段模板，如 {baseUrl}/api/v2/sections/{id}/play-url' : '剧集链接的CSS选择器'
    return [
      this.field('标题', titleHint,
        () => this.selectorToText(getConfig().title),
        (v: string) => {
          const c = getConfig()
          const next: SelectorConfig = {
            title: this.updateSelectorValue(v, c.title),
            url: c.url || ''
          }
          setConfig(next)
        }),
      this.field('链接', urlHint,
        () => this.selectorToText(getConfig().url),
        (v: string) => {
          const c = getConfig()
          const next: SelectorConfig = {
            title: c.title || '',
            url: this.updateSelectorValue(v, c.url)
          }
          setConfig(next)
        })
    ]
  }

  // 分类卡片字段（按下标实时定位，卡片替换后仍有效；模式自适应）
  cardFields(index: number): EditField[] {
    const cardAt = (): CategoryCardConfig | undefined => this.categoryCards[index]
    const fields: EditField[] = [
      this.field('标题', '卡片显示标题，如 周榜',
        () => { const c = cardAt(); return c ? c.title : '' },
        (v: string) => { const c = cardAt(); if (c) { c.title = v; this.markAsChanged() } }),
      this.field(this.isJson() ? '接口地址' : '页面地址',
        this.isJson() ? '数据接口地址，相对路径将拼接基础URL' : '数据页面地址，相对路径将拼接基础URL，如 /ft/recent.html',
        () => { const c = cardAt(); return c ? c.url : '' },
        (v: string) => { const c = cardAt(); if (c) { c.url = v; this.markAsChanged() } }),
      this.field('更多页地址(可选)', '"更多"页地址，支持 {page} 占位符（JSON）或页面地址（HTML）',
        () => { const c = cardAt(); return c ? (c.moreUrl || '') : '' },
        (v: string) => { const c = cardAt(); if (c) { c.moreUrl = v; this.markAsChanged() } })
    ]
    if (this.isJson()) {
      fields.push(this.field('列表JSON路径', '列表在响应中的JSON路径，如 data.list',
        () => { const c = cardAt(); return c ? (c.listPath || '') : '' },
        (v: string) => { const c = cardAt(); if (c) { c.listPath = v; this.markAsChanged() } }))
    } else {
      fields.push(this.field('列表选择器', '列表的CSS选择器，如 .anime-card',
        () => { const c = cardAt(); return c ? (c.listSelector || '') : '' },
        (v: string) => { const c = cardAt(); if (c) { c.listSelector = v; this.markAsChanged() } }))
    }
    return fields
  }
}
