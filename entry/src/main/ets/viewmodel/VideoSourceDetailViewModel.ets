import { DataSourceConfig, SelectorConfig, ProcessConfig, StringProcessConfig, CategoryCardConfig, LoginConfig, VideoConfig, ParserConfig, CategoryConfig, RecommendConfig, SearchCaptchaConfig } from "../api/DataSourceConfig"
import { UIUtils } from '@kit.ArkUI'
import { dataSourceManager } from "../api/DataSourceManager"
import { SOURCE_CHANGED_EVENT, VIDEO_SOURCE_EVENT } from "../utils/EventBus"
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
  /** 可选：返回 false 时该行不渲染（配合开关行实现"勾选后展开"） */
  visible?: () => boolean
  /** 可选：提供后渲染为勾选开关行而非输入框 */
  toggle?: EditToggleField
  /** 可选：提供后渲染为下拉选择行而非输入框 */
  select?: EditSelectField
}

/** 勾选开关行描述 */
export interface EditToggleField {
  isOn: () => boolean
  onChange: (isOn: boolean) => void
}

/** 下拉选择行描述 */
export interface EditSelectField {
  options: string[]
  selected: () => number
  onChange: (index: number) => void
}

/** 新建数据源的默认配置 */
function createDefaultConfig(): DataSourceConfig {
  return {
    key: '',
    name: '',
    group: '',
    baseUrl: '',
    version: '1.0.0',
    author: '',
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

  // 切换轮播拼接基础URL
  setBannerUrlNeedBaseUrl(isOn: boolean) {
    const banner = this.editingConfig.parserConfig.homepage.banner
    if (isOn === banner.urlNeedBaseUrl) {
      return
    }
    banner.urlNeedBaseUrl = isOn
    this.markAsChanged()
  }

  // 切换轮播启用HTTPS
  setBannerEnabledHttps(isOn: boolean) {
    const banner = this.editingConfig.parserConfig.homepage.banner
    if (isOn === banner.enabledHttps) {
      return
    }
    banner.enabledHttps = isOn
    this.markAsChanged()
  }

  // 切换分类更多链接拼接基础URL（HTML 模式）
  setMoreUrlNeedBaseUrl(isOn: boolean) {
    const category = this.editingConfig.parserConfig.homepage.category
    if (isOn === category.moreUrlNeedBaseUrl) {
      return
    }
    category.moreUrlNeedBaseUrl = isOn
    this.markAsChanged()
  }

  // 切换板块视频拼接基础URL（HTML 模式，"更多"分页页同样生效）
  setCategoryVideosUrlNeedBaseUrl(isOn: boolean) {
    const videos = this.editingConfig.parserConfig.homepage.category.videos
    if (isOn === videos.urlNeedBaseUrl) {
      return
    }
    videos.urlNeedBaseUrl = isOn
    this.markAsChanged()
  }

  // 切换板块视频启用HTTPS（HTML 模式）
  setCategoryVideosEnabledHttps(isOn: boolean) {
    const videos = this.editingConfig.parserConfig.homepage.category.videos
    if (isOn === videos.enabledHttps) {
      return
    }
    videos.enabledHttps = isOn
    this.markAsChanged()
  }

  // 切换推荐拼接基础URL
  setRecommendUrlNeedBaseUrl(isOn: boolean) {
    const recommends = this.editingConfig.parserConfig.detail.recommends
    if (isOn === recommends.urlNeedBaseUrl) {
      return
    }
    recommends.urlNeedBaseUrl = isOn
    this.markAsChanged()
  }

  // 切换推荐启用HTTPS
  setRecommendEnabledHttps(isOn: boolean) {
    const recommends = this.editingConfig.parserConfig.detail.recommends
    if (isOn === recommends.enabledHttps) {
      return
    }
    recommends.enabledHttps = isOn
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
      this.editingConfig.login = login
    } else {
      this.editingConfig.login = undefined
    }    this.markAsChanged()
  }

  // 切换搜索验证码开关（整体替换配置对象保证条件渲染刷新；开启时预填 dsn2 模板常见默认值）
  setSearchCaptchaEnabled(isOn: boolean) {
    const search = this.editingConfig.parserConfig.search
    if (isOn === (search.captcha !== undefined)) {
      return
    }
    if (isOn) {
      const captcha: SearchCaptchaConfig = {
        detectSelector: 'img.ds-verify-img',
        imageUrlSelector: 'img.ds-verify-img@src',
        imageNeedBaseUrl: true,
        verifyUrlTemplate: '/index.php/ajax/verify_check?type=search&verify={code}',
        successContains: '"code":1'
      }
      search.captcha = captcha
    } else {
      search.captcha = undefined
    }
    this.markAsChanged()
  }

  // 设置解析模式（正则/选择器/JSON/链接透传，空串表示清除pattern回到选择器模式）
  setVideoPattern(value: string) {
    this.editingConfig.parserConfig.videoUrl.pattern =
      value === '' ? undefined : value as 'regex' | 'javascript' | 'json' | 'link'
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
    this.categoryCards = this.categoryCards.concat([UIUtils.makeObserved(card)])
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
    const updated = UIUtils.makeObserved(this.copyCard(old))
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

  // 更新分类卡片字段模板（替换数组元素保证 @Trace 通知，勾选「后处理」后联动表单显隐）
  setCardItemSelectors(index: number, config: SelectorConfig) {
    const old = this.categoryCards[index]
    if (!old) {
      return
    }
    const updated = UIUtils.makeObserved(this.copyCard(old))
    updated.itemSelectors = config
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
      const prevHomeKey: string = dataSourceManager.getKey()
      if (this.originalKey === 'new') {
        // 添加新数据源
        try {
          await dataSourceManager.addDataSource(this.plainConfig())
          // 通知数据源变更
          VIDEO_SOURCE_EVENT.emit()
          ToastUtil.showToast({ message: "数据源添加成功" })
        } catch (err) {
          console.error(`${err}`)
          ToastUtil.showToast({ message: `${this.editingConfig.key} 不唯一` })
        }
      } else {
        // 更新现有数据源
        await dataSourceManager.updateDataSource(this.originalKey, this.plainConfig())
        // 通知数据源变更
        VIDEO_SOURCE_EVENT.emit()
        ToastUtil.showToast({ message: "数据源更新成功" })
      }
      // 首页源发生变化时通知首页刷新
      if (dataSourceManager.getKey() !== prevHomeKey) {
        SOURCE_CHANGED_EVENT.emit()
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
    // 自动维护更新日期（YYYY-MM-DD）
    const now = new Date()
    const month = now.getMonth() + 1
    const day = now.getDate()
    this.editingConfig.update_time =
      `${now.getFullYear()}-${month < 10 ? '0' + month : month}-${day < 10 ? '0' + day : day}`
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

  // 剥离观测代理的普通深拷贝（管理器持有与 JSON 序列化均使用干净对象）
  private plainConfig(): DataSourceConfig {
    return JSON.parse(JSON.stringify(this.editingConfig))
  }

  // 初始化新数据源
  private initNewSource() {
    // makeObserved 递归代理所有层级：编辑页嵌套写入直接触发 UI 更新（V2 深度观测）
    this.editingConfig = UIUtils.makeObserved(createDefaultConfig())
    this.sourceType = 'html'
    this.requestHeadersText = ''
    this.categoryCards = []
    this.cardKeys = []
    this.cardKeySeq = 0
  }

  // 初始化编辑数据源
  private initEditSource(sourceConfig: DataSourceConfig) {
    // 深拷贝传入的配置，避免直接修改原始数据
    const plain: DataSourceConfig = JSON.parse(JSON.stringify(sourceConfig))
    // 补齐可选缺失的配置段：导入的配置可能省略（如 tvtfun 无 recommends），
    // 而编辑页字段闭包会直接解引用这些对象，缺失会导致运行时 TypeError 闪退
    if (!plain.parserConfig) {
      plain.parserConfig = createDefaultConfig().parserConfig
    }
    this.ensureEditableSections(plain.parserConfig)
    // makeObserved 递归代理所有层级：编辑页嵌套写入直接触发 UI 更新（V2 深度观测）
    this.editingConfig = UIUtils.makeObserved(plain)
    const parser = this.editingConfig.parserConfig
    this.sourceType = parser && parser.sourceType === 'json' ? 'json' : 'html'
    this.requestHeadersText = this.headersToText(parser ? parser.requestHeaders : undefined)
    const cards = parser && parser.homepage && parser.homepage.category ? parser.homepage.category.cards : undefined
    const copied: CategoryCardConfig[] = []
    if (cards) {
      for (const card of cards) {
        copied.push(UIUtils.makeObserved(this.copyCard(card)))
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
      enabledHttps: card.enabledHttps,
      maxItems: card.maxItems
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

  // ---------- 后处理表单 ----------

  private static readonly PP_TYPE_IDS: string[] =
    ['replace', 'regex', 'substring', 'split', 'script', 'expression', 'condition', 'transformMap', 'transformTemplate', 'json']
  private static readonly PP_TYPE_LABELS: string[] =
    ['字符串替换', '正则提取', '截取片段', '分割取段', '自定义脚本', '表达式', '条件取值', '值映射', '模板拼接', 'JSON(高级)']

  /** 由现有配置推断后处理类型下标；无法识别（如 pipeline）归入 JSON(高级) */
  private postProcessTypeIndex(pp: ProcessConfig | undefined): number {
    if (pp === undefined) {
      return 0
    }
    if (pp.type === 'string') {
      const st = pp.stringProcess ? pp.stringProcess.type : ''
      const idx = VideoSourceDetailViewModel.PP_TYPE_IDS.indexOf(st)
      return idx >= 0 ? idx : 9
    }
    if (pp.type === 'transform') {
      return pp.transform && pp.transform.template !== undefined ? 8 : 7
    }
    const idx = VideoSourceDetailViewModel.PP_TYPE_IDS.indexOf(pp.type)
    return idx >= 0 ? idx : 9
  }

  /** 某类型后处理的初始配置 */
  private defaultPostProcess(typeId: string): ProcessConfig {
    switch (typeId) {
      case 'regex': {
        const sp: StringProcessConfig = { type: 'regex', pattern: '', flags: 'g', group: 0 }
        return { type: 'string', stringProcess: sp }
      }
      case 'substring': {
        const sp: StringProcessConfig = { type: 'substring', start: 0 }
        return { type: 'string', stringProcess: sp }
      }
      case 'split': {
        const sp: StringProcessConfig = { type: 'split', delimiter: '', index: 0 }
        return { type: 'string', stringProcess: sp }
      }
      case 'script':
        return { type: 'script', script: 'return String(result).trim()' }
      case 'expression':
        return { type: 'expression', expression: '' }
      case 'condition':
        return { type: 'condition', condition: 'false', trueValue: '', falseValue: '' }
      case 'transformMap': {
        const emptyMap: Record<string, string> = {}
        return { type: 'transform', transform: { map: emptyMap } }
      }
      case 'transformTemplate':
        return { type: 'transform', transform: { template: '${input}' } }
      default: {
        const sp: StringProcessConfig = { type: 'replace', search: '', replace: '', flags: 'g' }
        return { type: 'string', stringProcess: sp }
      }
    }
  }

  /** Record 映射 → 每行一条 旧值=新值 的文本 */
  private recordToLines(map: Record<string, string> | undefined): string {
    if (!map) {
      return ''
    }
    const keys = Object.keys(map)
    const lines: string[] = []
    for (const k of keys) {
      lines.push(`${k}=${String(map[k])}`)
    }
    return lines.join('\n')
  }

  /** 每行一条 旧值=新值 的文本 → Record 映射 */
  private linesToRecord(text: string): Record<string, string> {
    const map: Record<string, string> = {}
    const lines = text.split('\n')
    for (const line of lines) {
      const t = line.trim()
      if (t === '') {
        continue
      }
      const eq = t.indexOf('=')
      if (eq <= 0) {
        continue
      }
      map[t.substring(0, eq)] = t.substring(eq + 1)
    }
    return map
  }

  /**
   * 后处理表单字段组：处理方式下拉行 + 按所选类型展开的参数输入行
   * enabled 控制整组显隐；getPP/setPP 由调用方决定后处理挂在哪个字段上
   */
  private postProcessFormFields(label: string, enabled: () => boolean,
    getPP: () => ProcessConfig | undefined,
    setPP: (pp: ProcessConfig | undefined) => void): EditField[] {
    const typeIdx = (): number => this.postProcessTypeIndex(getPP())
    const isType = (idx: number): boolean => enabled() && typeIdx() === idx
    const typeRow: EditField = {
      title: `${label}处理方式`,
      placeholder: '',
      getValue: () => '',
      setValue: (v: string) => {},
      visible: enabled,
      select: {
        options: VideoSourceDetailViewModel.PP_TYPE_LABELS,
        selected: () => typeIdx(),
        onChange: (index: number) => {
          const id = VideoSourceDetailViewModel.PP_TYPE_IDS[index]
          // JSON(高级) 保持现有配置原样展示；其余类型切换为该类型的初始配置
          setPP(id === 'json' ? getPP() : this.defaultPostProcess(id))
          this.markAsChanged()
        }
      }
    }
    const spOf = (pp: ProcessConfig): StringProcessConfig =>
      pp.stringProcess ?? { type: 'replace', search: '', replace: '', flags: 'g' }
    const param = (idx: number, title: string, hint: string,
      get: (pp: ProcessConfig) => string,
      set: (pp: ProcessConfig, v: string) => ProcessConfig,
      inputType?: string): EditField => {
      const f = this.field(title, hint,
        () => {
          const pp = getPP()
          return pp !== undefined ? get(pp) : ''
        },
        (v: string) => {
          const pp = getPP()
          if (pp !== undefined) {
            setPP(set(pp, v))
            this.markAsChanged()
          }
        }, inputType)
      f.visible = () => isType(idx)
      return f
    }
    return [
      typeRow,
      // 字符串替换
      param(0, '搜索内容(正则)', '要匹配的正则表达式，如 ^第\\d+集\\s*',
        (pp) => spOf(pp).search || '',
        (pp, v) => {
          const sp = spOf(pp)
          const n: StringProcessConfig = { type: 'replace', search: v, replace: sp.replace || '', flags: sp.flags ?? 'g' }
          return { type: 'string', stringProcess: n }
        }),
      param(0, '替换为', '替换后的文本，可用 $1/$2 引用正则分组',
        (pp) => spOf(pp).replace || '',
        (pp, v) => {
          const sp = spOf(pp)
          const n: StringProcessConfig = { type: 'replace', search: sp.search || '', replace: v, flags: sp.flags ?? 'g' }
          return { type: 'string', stringProcess: n }
        }),
      param(0, '匹配标志', '正则标志：g=全部匹配，i=忽略大小写，可组合；留空=只处理第一处',
        (pp) => spOf(pp).flags || '',
        (pp, v) => {
          const sp = spOf(pp)
          const n: StringProcessConfig = { type: 'replace', search: sp.search || '', replace: sp.replace || '', flags: v }
          return { type: 'string', stringProcess: n }
        }),
      // 正则提取
      param(1, '正则表达式', '用于提取内容的正则，如 第(\\d+)集',
        (pp) => spOf(pp).pattern || '',
        (pp, v) => {
          const sp = spOf(pp)
          const n: StringProcessConfig = { type: 'regex', pattern: v, flags: sp.flags ?? 'g', group: sp.group ?? 0 }
          return { type: 'string', stringProcess: n }
        }),
      param(1, '提取分组', '分组编号：0=整体匹配，1=第一个括号的内容',
        (pp) => spOf(pp).group !== undefined ? String(spOf(pp).group) : '0',
        (pp, v) => {
          const g = parseInt(v, 10)
          const sp = spOf(pp)
          const n: StringProcessConfig = { type: 'regex', pattern: sp.pattern || '', flags: sp.flags ?? 'g', group: isNaN(g) ? 0 : g }
          return { type: 'string', stringProcess: n }
        }, 'number'),
      param(1, '匹配标志', '正则标志：g=全局，i=忽略大小写',
        (pp) => spOf(pp).flags || '',
        (pp, v) => {
          const sp = spOf(pp)
          const n: StringProcessConfig = { type: 'regex', pattern: sp.pattern || '', flags: v, group: sp.group ?? 0 }
          return { type: 'string', stringProcess: n }
        }),
      // 截取片段
      param(2, '起始位置', '数字下标从0开始；或填文本：从该文本之后开始截取',
        (pp) => spOf(pp).start !== undefined ? String(spOf(pp).start) : '',
        (pp, v) => {
          const t = v.trim()
          const sp = spOf(pp)
          const start: string | number = t === '' ? 0 : (isNaN(Number(t)) ? t : Number(t))
          const n: StringProcessConfig = { type: 'substring', start: start, end: sp.end }
          return { type: 'string', stringProcess: n }
        }),
      param(2, '结束位置', '数字下标；或填文本：截取到该文本之前；留空=截取到末尾',
        (pp) => spOf(pp).end !== undefined ? String(spOf(pp).end) : '',
        (pp, v) => {
          const t = v.trim()
          const sp = spOf(pp)
          const end: string | number | undefined = t === '' ? undefined : (isNaN(Number(t)) ? t : Number(t))
          const n: StringProcessConfig = { type: 'substring', start: sp.start ?? 0, end: end }
          return { type: 'string', stringProcess: n }
        }),
      // 分割取段
      param(3, '分隔符', '按此文本分割，如 - 或 ,',
        (pp) => spOf(pp).delimiter || '',
        (pp, v) => {
          const sp = spOf(pp)
          const n: StringProcessConfig = { type: 'split', delimiter: v, index: sp.index ?? 0 }
          return { type: 'string', stringProcess: n }
        }),
      param(3, '段索引', '分割后取第几段，从0开始',
        (pp) => spOf(pp).index !== undefined ? String(spOf(pp).index) : '0',
        (pp, v) => {
          const i = parseInt(v, 10)
          const sp = spOf(pp)
          const n: StringProcessConfig = { type: 'split', delimiter: sp.delimiter || '', index: isNaN(i) ? 0 : i }
          return { type: 'string', stringProcess: n }
        }, 'number'),
      // 自定义脚本
      param(4, '脚本代码', 'result 为输入值，需 return 返回结果；可用 Math 及 utils.string.extract/replaceAll/between 等',
        (pp) => pp.script || '',
        (pp, v) => {
          return { type: 'script', script: v }
        }),
      // 表达式
      param(5, '表达式', '如 extract(result, "v=(\\d+)")；支持 extract/replaceAll/between/parseInt 及四则运算',
        (pp) => pp.expression || '',
        (pp, v) => {
          return { type: 'expression', expression: v }
        }),
      // 条件取值
      param(6, '条件表达式', '成立时返回真值，否则返回假值，如 result.indexOf("电影") >= 0',
        (pp) => pp.condition || '',
        (pp, v) => {
          return { type: 'condition', condition: v, trueValue: pp.trueValue, falseValue: pp.falseValue }
        }),
      param(6, '真值', '条件成立时返回的内容',
        (pp) => pp.trueValue !== undefined ? String(pp.trueValue) : '',
        (pp, v) => {
          return { type: 'condition', condition: pp.condition || 'false', trueValue: v, falseValue: pp.falseValue }
        }),
      param(6, '假值', '条件不成立时返回的内容',
        (pp) => pp.falseValue !== undefined ? String(pp.falseValue) : '',
        (pp, v) => {
          return { type: 'condition', condition: pp.condition || 'false', trueValue: pp.trueValue, falseValue: v }
        }),
      // 值映射
      param(7, '映射规则', '每行一条 旧值=新值；输入等于旧值时替换为新值',
        (pp) => this.recordToLines(pp.transform ? pp.transform.map : undefined),
        (pp, v) => {
          return { type: 'transform', transform: { map: this.linesToRecord(v) } }
        }),
      // 模板拼接
      param(8, '拼接模板', '用 ${input} 代表原值进行拼接，如 第${input}集',
        (pp) => pp.transform ? (pp.transform.template || '') : '',
        (pp, v) => {
          return { type: 'transform', transform: { template: v } }
        }),
      // JSON(高级)
      param(9, '完整JSON配置', 'ProcessConfig 完整JSON，适用于管道(pipeline)等高级场景',
        (pp) => JSON.stringify(pp),
        (pp, v) => {
          const trimmed = v.trim()
          if (trimmed === '') {
            return pp
          }
          try {
            const parsed: ProcessConfig = JSON.parse(trimmed)
            return parsed
          } catch (e) {
            // 非法JSON忽略，保留原值
            return pp
          }
        })
    ]
  }

  /**
   * itemSelectors 单字段的编辑字段组：
   * 主字段（标题行右侧带「后处理」勾选框）+ 勾选后展开的后处理表单
   * 复杂配置形态下编辑主字段仅替换 selector，保留已有 postProcess
   */
  private itemSelectorFieldGroup(label: string, fieldHint: string,
    getConfig: () => SelectorConfig, setConfig: (c: SelectorConfig) => void,
    read: (c: SelectorConfig) => SelectorValue,
    write: (c: SelectorConfig, v: SelectorValue) => SelectorConfig): EditField[] {
    const ppEnabled = (): boolean => {
      const val = read(getConfig())
      return typeof val === 'object' && val !== undefined && val.postProcess !== undefined
    }
    const main = this.field(label, fieldHint,
      () => this.selectorToText(read(getConfig())),
      (v: string) => {
        setConfig(write(getConfig(), this.updateSelectorValue(v, read(getConfig()))))
      })
    main.toggle = {
      isOn: () => ppEnabled(),
      onChange: (isOn: boolean) => {
        const c = getConfig()
        const selector = this.selectorToText(read(c))
        if (isOn) {
          const pp = this.defaultPostProcess('replace')
          const complex: SelectorFieldConfig = { selector: selector, postProcess: pp }
          setConfig(write(c, complex))
        } else {
          setConfig(write(c, selector))
        }
        this.markAsChanged()
      }
    }
    const getPP = (): ProcessConfig | undefined => {
      const val = read(getConfig())
      if (typeof val === 'object' && val !== undefined) {
        return val.postProcess
      }
      return undefined
    }
    const setPP = (pp: ProcessConfig | undefined) => {
      const c = getConfig()
      const selector = this.selectorToText(read(c))
      if (pp === undefined) {
        setConfig(write(c, selector))
        return
      }
      const complex: SelectorFieldConfig = { selector: selector, postProcess: pp }
      setConfig(write(c, complex))
    }
    return [main, ...this.postProcessFormFields(label, ppEnabled, getPP, setPP)]
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
          this.editingConfig.name = v
          this.markAsChanged()
        }),
      this.field('版本', '数据源版本号, 只能写数字哦，格式：x.x.x',
        () => this.editingConfig.version,
        (v: string) => { this.editingConfig.version = v; this.markAsChanged() }),
      this.field('作者', '源作者，导出时会随源携带',
        () => this.editingConfig.author || '',
        (v: string) => { this.editingConfig.author = v; this.markAsChanged() }),
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
        (v: string) => { if (this.editingConfig.login) { this.editingConfig.login.authValueTemplate = v; this.markAsChanged() } }),
      this.field('额外请求体JSON(可选)', '登录请求体的额外固定字段，如 {"device":"web"}，留空清除',
        () => this.editingConfig.login && this.editingConfig.login.extraBody ? JSON.stringify(this.editingConfig.login.extraBody) : '',
        (v: string) => {
          if (!this.editingConfig.login) {
            return
          }
          const trimmed = v.trim()
          if (!trimmed) {
            this.editingConfig.login.extraBody = undefined
            this.markAsChanged()
            return
          }
          try {
            const parsed: Record<string, string> = JSON.parse(trimmed)
            if (parsed) {
              this.editingConfig.login.extraBody = parsed
              this.markAsChanged()
            }
          } catch (e) {
            // 非法JSON忽略，保留原值
          }
        })
    ]
  }

  // 搜索配置字段
  searchFields(): EditField[] {
    const json = this.isJson()
    const fields: EditField[] = [
      this.field('搜索链接模板',
        json ? '如 /api/videos/search?q={keyword}&page={page}' : '搜索URL模板，如：/search?q={keyword}&page={page}',
        () => this.editingConfig.parserConfig.search.videos.urlTemplate,
        (v: string) => { this.editingConfig.parserConfig.search.videos.urlTemplate = v; this.markAsChanged() }),
      this.field(json ? '列表JSON路径' : '列表选择器',
        json ? '搜索结果列表在响应中的JSON路径，如 data.list' : '搜索结果列表的CSS选择器',
        () => this.editingConfig.parserConfig.search.videos.listSelector,
        (v: string) => { this.editingConfig.parserConfig.search.videos.listSelector = v; this.markAsChanged() })
    ]
    if (!json) {
      fields.push(this.field('列表容器选择器(可选)', '整页文档中先定位列表容器，再在其中用列表选择器找条目',
        () => this.editingConfig.parserConfig.search.videos.containerSelector || '',
        (v: string) => { this.editingConfig.parserConfig.search.videos.containerSelector = v; this.markAsChanged() }))
    }
    return fields
  }

  // 搜索验证码字段（HTML 模式，高级字段开关展开后渲染）
  captchaFields(): EditField[] {
    const captcha = () => this.editingConfig.parserConfig.search.captcha
    const imageNeedBaseUrl = this.field('图片拼接基础URL', '',
      () => '',
      (v: string) => {})
    imageNeedBaseUrl.toggle = {
      isOn: () => { const c = captcha(); return c ? c.imageNeedBaseUrl !== false : false },
      onChange: (isOn: boolean) => {
        const c = captcha()
        if (c) {
          c.imageNeedBaseUrl = isOn
          this.markAsChanged()
        }
      }
    }
    return [
      this.field('验证页判定选择器', '搜索响应命中该选择器即视为验证码页，如 img.ds-verify-img',
        () => { const c = captcha(); return c ? (c.detectSelector || '') : '' },
        (v: string) => { const c = captcha(); if (c) { c.detectSelector = v; this.markAsChanged() } }),
      this.field('验证码图片选择器', 'selector@attr 形式，如 img.ds-verify-img@src；留空且判定元素是 img 时自动取其 src',
        () => { const c = captcha(); return c ? (c.imageUrlSelector || '') : '' },
        (v: string) => { const c = captcha(); if (c) { c.imageUrlSelector = v; this.markAsChanged() } }),
      imageNeedBaseUrl,
      this.field('防缓存参数名(可选)', '获取图片时附加 ?参数名=随机数 防缓存，如 r，留空不附加',
        () => { const c = captcha(); return c && c.imageCacheBustParam ? c.imageCacheBustParam : '' },
        (v: string) => {
          const c = captcha()
          if (c) {
            const trimmed = v.trim()
            c.imageCacheBustParam = trimmed === '' ? undefined : trimmed
            this.markAsChanged()
          }
        }),
      this.field('校验提交地址模板', '相对基础URL或绝对地址，{code} 为用户输入，如 /index.php/ajax/verify_check?type=search&verify={code}',
        () => { const c = captcha(); return c ? (c.verifyUrlTemplate || '') : '' },
        (v: string) => { const c = captcha(); if (c) { c.verifyUrlTemplate = v; this.markAsChanged() } }),
      this.field('成功标识子串(可选)', '提交响应包含该子串视为校验成功，如 "code":1，留空仅按重放结果判断',
        () => { const c = captcha(); return c && c.successContains ? c.successContains : '' },
        (v: string) => {
          const c = captcha()
          if (c) {
            const trimmed = v.trim()
            c.successContains = trimmed === '' ? undefined : trimmed
            this.markAsChanged()
          }
        })
    ]
  }

  // 轮播图字段
  bannerFields(): EditField[] {
    const json = this.isJson()
    const fields: EditField[] = [
      this.field(json ? '接口地址模板' : '基础URL拼接模板',
        json ? '轮播数据接口地址，支持 {today} 占位符(1=周一..7=周日)' : '轮播图的基础链接拼接模板',
        () => this.editingConfig.parserConfig.homepage.banner.urlTemplate,
        (v: string) => { this.editingConfig.parserConfig.homepage.banner.urlTemplate = v; this.markAsChanged() }),
      this.field(json ? '列表JSON路径' : '列表选择器',
        json ? '轮播列表在响应中的JSON路径，如 data.list' : 'Banner列表的CSS选择器',
        () => this.editingConfig.parserConfig.homepage.banner.listSelector,
        (v: string) => { this.editingConfig.parserConfig.homepage.banner.listSelector = v; this.markAsChanged() })
    ]
    if (!json) {
      fields.push(this.field('列表容器选择器(可选)', '整页文档中先定位轮播容器，再在其中用列表选择器找条目',
        () => this.editingConfig.parserConfig.homepage.banner.containerSelector || '',
        (v: string) => { this.editingConfig.parserConfig.homepage.banner.containerSelector = v; this.markAsChanged() }))
    }
    return fields
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
        (v: string) => { this.editingConfig.parserConfig.homepage.category.videoLists = v; this.markAsChanged() }),
      this.field('板块视频列表选择器', '板块内单个视频条目的CSS选择器',
        () => this.editingConfig.parserConfig.homepage.category.videos.listSelector,
        (v: string) => { this.editingConfig.parserConfig.homepage.category.videos.listSelector = v; this.markAsChanged() }),
      this.field('板块视频容器选择器(可选)', '"更多"页等整页文档中先定位列表容器，再用板块视频列表选择器找条目',
        () => this.editingConfig.parserConfig.homepage.category.videos.containerSelector || '',
        (v: string) => { this.editingConfig.parserConfig.homepage.category.videos.containerSelector = v; this.markAsChanged() })
    ]
  }

  // 详情字段（模式自适应：HTML=CSS选择器 / JSON=字段模板）
  detailFields(): EditField[] {
    const json = this.isJson()
    const detail = () => this.editingConfig.parserConfig.detail
    const coverField = this.field(json ? '封面模板' : '封面选择器',
      json ? '如 {cover_url}，相对路径将拼接基础URL' : '视频详情页封面的CSS选择器',
      () => detail().coverSelector,
      (v: string) => { detail().coverSelector = v; this.markAsChanged() })
    if (json) {
      coverField.toggle = {
        isOn: () => detail().coverPostProcess !== undefined,
        onChange: (isOn: boolean) => {
          if (isOn) {
            detail().coverPostProcess = this.defaultPostProcess('replace')
          } else {
            detail().coverPostProcess = undefined
          }
          this.markAsChanged()
        }
      }
    }
    const fields: EditField[] = [
      this.field(json ? '标题模板' : '标题选择器',
        json ? '如 {title}' : '视频详情页标题的CSS选择器',
        () => detail().titleSelector,
        (v: string) => { detail().titleSelector = v; this.markAsChanged() }),
      this.field(json ? '描述模板' : '描述选择器',
        json ? '如 {description}' : '视频详情页描述的CSS选择器',
        () => detail().descSelector,
        (v: string) => { detail().descSelector = v; this.markAsChanged() }),
      coverField,
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
      fields.push(this.field('详情数据JSON路径(可选)', '详情数据在响应中的JSON路径，默认 data；接口直接返回数组时填 0，留空恢复默认',
        () => detail().dataPath || '',
        (v: string) => {
          const trimmed = v.trim()
          detail().dataPath = trimmed === '' ? undefined : trimmed
          this.markAsChanged()
        }))
      fields.push(...this.postProcessFormFields('封面',
        () => detail().coverPostProcess !== undefined,
        () => detail().coverPostProcess,
        (pp: ProcessConfig | undefined) => { detail().coverPostProcess = pp }))
    }
    return fields
  }

  // 剧集列表字段（模式自适应：HTML=选择器组 / JSON=选集接口配置）
  episodeListFields(): EditField[] {
    const json = this.isJson()
    const episodes = () => this.editingConfig.parserConfig.detail.episodes
    if (json) {
      return [
        this.field('路线数组路径', '详情响应中的路线数组路径，如 play_from；留空则为单路线模式（详情数据自身为唯一路线，选集内嵌于详情响应）',
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
      const fields: EditField[] = []
      if (videoUrl().pattern !== 'link') {
        fields.push(this.field('播放地址JSON路径', '播放地址在响应中的JSON路径，默认 data.url',
          () => videoUrl().valuePath || '',
          (v: string) => { videoUrl().valuePath = v; this.markAsChanged() }))
        fields.push(this.field('后处理', '视频链接后处理脚本',
          () => videoUrl().postProcess || '',
          (v: string) => { videoUrl().postProcess = v; this.markAsChanged() }))
      } else {
        // 链接透传：选集链接即播放页地址，仅在此时内嵌JS才有意义（后处理不参与）
        fields.push(this.field('内嵌视频解析JS(可选)', '选集链接作为播放页在WebView中打开后执行此JS，最终需返回真实播放地址；返回ERR_开头字符串表示失败原因',
          () => videoUrl().iframeSelector || '',
          (v: string) => { videoUrl().iframeSelector = v; this.markAsChanged() }))
      }
      return fields
    }
    const isRegex = videoUrl().pattern === 'regex'
    return [
      this.field(isRegex ? '播放链接正则' : '播放链接选择器',
        isRegex ? '正则表达式，捕获组1为播放地址，如 "url":"([^"]+)"' : '视频播放链接的CSS选择器，如 video@src',
        () => videoUrl().urlSelector || '',
        (v: string) => { videoUrl().urlSelector = v; this.markAsChanged() }),
      this.field('后处理', '视频链接后处理脚本',
        () => videoUrl().postProcess || '',
        (v: string) => { videoUrl().postProcess = v; this.markAsChanged() }),
      this.field('内嵌视频选择器(执行JS，最终需返回播放链接)', '提取到的是播放器页地址时，可在该页内执行此JS获取真实播放链接',
        () => videoUrl().iframeSelector || '',
        (v: string) => { videoUrl().iframeSelector = v; this.markAsChanged() })
    ]
  }

  // 视频信息选择器字段：写值时保留全部字段键（避免编辑任一字段时丢失其余字段，含扩展字段）
  private writeVideoInfoField(c: SelectorConfig, key: string, v: SelectorValue): SelectorConfig {
    const copy: SelectorConfig = {
      title: c.title,
      url: c.url,
      imgUrl: c.imgUrl,
      episode: c.episode,
      playCount: c.playCount,
      year: c.year,
      month: c.month,
      director: c.director,
      actors: c.actors,
      tags: c.tags
    }
    switch (key) {
      case 'title': copy.title = v; break
      case 'url': copy.url = v; break
      case 'imgUrl': copy.imgUrl = v; break
      case 'episode': copy.episode = v; break
      case 'playCount': copy.playCount = v; break
      case 'year': copy.year = v; break
      case 'month': copy.month = v; break
      case 'director': copy.director = v; break
      case 'actors': copy.actors = v; break
      case 'tags': copy.tags = v; break
      default: break
    }
    return copy
  }

  // 是否配置了任一扩展字段（控制"更多字段"展开态）
  hasExtendedFields(c: SelectorConfig): boolean {
    return c.playCount !== undefined || c.year !== undefined || c.month !== undefined
      || c.director !== undefined || c.actors !== undefined || c.tags !== undefined
  }

  // 开关"更多字段"：开启=补齐 6 个扩展字段键（展开编辑），关闭=全部清除
  toggleExtendedFields(getConfig: () => SelectorConfig, setConfig: (c: SelectorConfig) => void,
    enabled: boolean): void {
    const c = getConfig()
    const next: SelectorConfig = this.writeVideoInfoField(c, 'playCount', undefined)
    next.year = undefined
    next.month = undefined
    next.director = undefined
    next.actors = undefined
    next.tags = undefined
    if (enabled) {
      next.playCount = c.playCount ?? ''
      next.year = c.year ?? ''
      next.month = c.month ?? ''
      next.director = c.director ?? ''
      next.actors = c.actors ?? ''
      next.tags = c.tags ?? ''
    }
    setConfig(next)
    this.markAsChanged()
  }

  // 视频信息选择器基础字段（模式自适应提示）
  videoInfoFields(getConfig: () => SelectorConfig, setConfig: (c: SelectorConfig) => void,
    jsonMode: boolean): EditField[] {
    const titleHint = jsonMode ? '字段模板，如 {title}' : '番剧名称的CSS选择器'
    const imgUrlHint = jsonMode ? '字段模板，如 {cover_url}' : '封面图片链接的CSS选择器'
    const urlHint = jsonMode ? '字段模板，如 {baseUrl}/api/videos/{id}' : '番剧详情链接的CSS选择器'
    const episodeHint = jsonMode ? '字段模板，如 {remarks}' : '剧集数量的CSS选择器'
    return [
      ...this.itemSelectorFieldGroup('番剧名', titleHint, getConfig, setConfig,
        (c: SelectorConfig): SelectorValue => c.title,
        (c: SelectorConfig, v: SelectorValue): SelectorConfig => this.writeVideoInfoField(c, 'title', v)),
      ...this.itemSelectorFieldGroup('封面链接', imgUrlHint, getConfig, setConfig,
        (c: SelectorConfig): SelectorValue => c.imgUrl,
        (c: SelectorConfig, v: SelectorValue): SelectorConfig => this.writeVideoInfoField(c, 'imgUrl', v)),
      ...this.itemSelectorFieldGroup('番剧链接', urlHint, getConfig, setConfig,
        (c: SelectorConfig): SelectorValue => c.url,
        (c: SelectorConfig, v: SelectorValue): SelectorConfig => this.writeVideoInfoField(c, 'url', v)),
      ...this.itemSelectorFieldGroup('剧集数', episodeHint, getConfig, setConfig,
        (c: SelectorConfig): SelectorValue => c.episode,
        (c: SelectorConfig, v: SelectorValue): SelectorConfig => this.writeVideoInfoField(c, 'episode', v))
    ]
  }

  // 视频信息选择器扩展字段（"更多字段"组，模式自适应提示）
  extendedVideoInfoFields(getConfig: () => SelectorConfig, setConfig: (c: SelectorConfig) => void,
    jsonMode: boolean): EditField[] {
    const playCountHint = jsonMode ? '字段模板，如 {hits}' : '播放量的CSS选择器'
    const yearHint = jsonMode ? '字段模板，如 {year}' : '播出年份的CSS选择器'
    const monthHint = jsonMode ? '字段模板，如 {month}' : '播出月份的CSS选择器'
    const directorHint = jsonMode ? '字段模板，如 {director}' : '导演的CSS选择器'
    const actorsHint = jsonMode ? '字段模板，如 {actors}' : '演员的CSS选择器'
    const tagsHint = jsonMode ? '字段模板，如 {tags}' : '标签的CSS选择器'
    return [
      ...this.itemSelectorFieldGroup('播放量', playCountHint, getConfig, setConfig,
        (c: SelectorConfig): SelectorValue => c.playCount,
        (c: SelectorConfig, v: SelectorValue): SelectorConfig => this.writeVideoInfoField(c, 'playCount', v)),
      ...this.itemSelectorFieldGroup('播出年份', yearHint, getConfig, setConfig,
        (c: SelectorConfig): SelectorValue => c.year,
        (c: SelectorConfig, v: SelectorValue): SelectorConfig => this.writeVideoInfoField(c, 'year', v)),
      ...this.itemSelectorFieldGroup('播出月份', monthHint, getConfig, setConfig,
        (c: SelectorConfig): SelectorValue => c.month,
        (c: SelectorConfig, v: SelectorValue): SelectorConfig => this.writeVideoInfoField(c, 'month', v)),
      ...this.itemSelectorFieldGroup('导演', directorHint, getConfig, setConfig,
        (c: SelectorConfig): SelectorValue => c.director,
        (c: SelectorConfig, v: SelectorValue): SelectorConfig => this.writeVideoInfoField(c, 'director', v)),
      ...this.itemSelectorFieldGroup('演员', actorsHint, getConfig, setConfig,
        (c: SelectorConfig): SelectorValue => c.actors,
        (c: SelectorConfig, v: SelectorValue): SelectorConfig => this.writeVideoInfoField(c, 'actors', v)),
      ...this.itemSelectorFieldGroup('标签', tagsHint, getConfig, setConfig,
        (c: SelectorConfig): SelectorValue => c.tags,
        (c: SelectorConfig, v: SelectorValue): SelectorConfig => this.writeVideoInfoField(c, 'tags', v))
    ]
  }

  // 单集选择器字段（模式自适应提示）
  episodeItemFields(getConfig: () => SelectorConfig, setConfig: (c: SelectorConfig) => void,
    jsonMode: boolean): EditField[] {
    const titleHint = jsonMode ? '字段模板，如 {title}' : '剧集标题的CSS选择器'
    const urlHint = jsonMode ? '字段模板，如 {baseUrl}/api/v2/sections/{id}/play-url' : '剧集链接的CSS选择器'
    const readTitle = (c: SelectorConfig): SelectorValue => c.title
    const readUrl = (c: SelectorConfig): SelectorValue => c.url
    const writeTitle = (c: SelectorConfig, v: SelectorValue): SelectorConfig => {
      return { title: v, url: c.url || '' }
    }
    const writeUrl = (c: SelectorConfig, v: SelectorValue): SelectorConfig => {
      return { title: c.title || '', url: v }
    }
    return [
      ...this.itemSelectorFieldGroup('标题', titleHint, getConfig, setConfig, readTitle, writeTitle),
      ...this.itemSelectorFieldGroup('链接', urlHint, getConfig, setConfig, readUrl, writeUrl)
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
    fields.push(this.field('显示条数上限(可选)', '主页卡片最多解析/显示的条数，如 12；留空=不限制，完整列表走"更多"',
      () => { const c = cardAt(); return c && c.maxItems !== undefined ? String(c.maxItems) : '' },
      (v: string) => {
        const c = cardAt()
        if (c) {
          const n = parseInt(v, 10)
          c.maxItems = v.trim() !== '' && !isNaN(n) && n > 0 ? n : undefined
          this.markAsChanged()
        }
      }, 'number'))
    return fields
  }
}
