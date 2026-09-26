
import Logger from '../utils/Logger';
import { ViewState } from '../components/StateView';
import { VideoList } from '../components/VideoList';
import { SearchResultList } from '../components/SearchResultList';
import StateView from '../components/StateView';
import { ToastUtil } from '../utils/ToastUtils';
import SearchHistoryInfo from '../entity/SearchHistoryInfo';
import VideoInfo from '../entity/VideoInfo';
import { AnimeState } from '../entryability/AnimeState';
import { searchViewModel } from '../viewmodel/SearchViewModel';
import { CategoryViewModel } from '../viewmodel/CategoryViewModel';
import TitleBar from '../components/TitleBar';
import { CustomContentDialog, CapsuleSegmentButtonV2, SegmentButtonV2Items } from '@kit.ArkUI';
import { ButtonOptions } from '@ohos.arkui.advanced.Dialog';
import { CaptchaBridge, CaptchaChallenge } from '../api/CaptchaBridge';
import { appSettings } from '../entryability/Settings';
import { image } from '@kit.ImageKit';
import { MenuItem } from '../components/common/Button';
import { DataSourceConfig } from '../api/DataSourceConfig';

const tag: string = 'SearchPage'

// 系统路由
@Builder
export function SearchPageBuilder(name: string, param: Object) {
  SearchPage()
}

@ComponentV2
struct SearchPage {

  @Local keyword: string = ''
  private searchRecommends: string[] = ['冰菓', '进击的巨人', '电锯人', '鲁路修', '命运石之门', '史莱姆', '天降之物']
  @Local categoryViewModel: CategoryViewModel = new CategoryViewModel()
  // 搜索结果展示样式（card=卡片 list=列表，由设置+结果自动判定解析而来）
  @Local resultStyle: string = 'card'

  // 搜索历史删除模式（长按记录进入）
  @Local historyEditMode: boolean = false
  // 搜索范围选择弹窗
  @Local showScopeSheet: boolean = false
  @Local scopeTab: string = 'group'
  @Local scopeGroupOptions: string[] = []
  @Local scopeSourceOptions: DataSourceConfig[] = []
  @Local selectedScopeGroups: string[] = []
  @Local selectedScopeSources: string[] = []
  // 范围弹窗顶部分段按钮（多分组/多源）
  private scopeSegmentItems: SegmentButtonV2Items = new SegmentButtonV2Items([{ text: '多分组' }, { text: '多源' }])
  @Local scopeSelectedIndex: number = 0

  // 公共输入弹窗（验证码/屏蔽词共用，按 dialogMode 切换内容构建）
  @Local commonDialog: CustomDialogController | undefined
  @Local dialogMode: string = ''
  @Local dialogTitle: string = ''
  @Local dialogSubtitle: string = ''
  @Local blockWordsInput: string = ''
  // 验证码弹窗
  @Local captchaImage: image.PixelMap | undefined
  @Local captchaCode: string = ''
  private captchaChallengeResolve: ((code: string) => void) | null = null
  private captchaChallengeReject: ((error: Error) => void) | null = null
  private captchaRefresh: (() => Promise<image.PixelMap>) | null = null

  async aboutToAppear() {
    this.categoryViewModel.state = ViewState.CUSTOM
    // 查询搜索历史
    await searchViewModel.loadHistory()

    const dialogButtons: ButtonOptions[] = [
      {
        value: '取消',
        buttonStyle: ButtonStyleMode.TEXTUAL,
        fontColor: $r('app.color.primary_color'),
        action: () => {
          this.cancelDialog()
        }
      },
      {
        value: '确定',
        buttonStyle: ButtonStyleMode.EMPHASIZED,
        action: () => {
          this.confirmDialog()
        }
      }
    ]
    this.commonDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: this.dialogTitle,
        secondaryTitle: this.dialogSubtitle,
        contentBuilder: (): void => {
          if (this.dialogMode === 'captcha') {
            this.captchaContent()
          } else if (this.dialogMode === 'block_words') {
            this.blockWordsContent()
          }
        },
        buttons: dialogButtons,
        contentAreaPadding: { top: 15, bottom: 15, left: 24, right: 24 },
        themeColorMode: appSettings.color_mode,
      }),
      autoCancel: false,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
    })

    CaptchaBridge.register((challenge: CaptchaChallenge): Promise<string> => {
      return this.handleCaptchaChallenge(challenge)
    })
  }

  aboutToDisappear(): void {
    CaptchaBridge.unregister()
  }

  /**
   * 公共弹窗取消：按当前模式分发
   */
  private cancelDialog(): void {
    if (this.dialogMode === 'captcha') {
      this.cancelCaptcha()
    } else {
      this.commonDialog?.close()
    }
  }

  /**
   * 公共弹窗确定：按当前模式分发
   */
  private confirmDialog(): void {
    if (this.dialogMode === 'captcha') {
      this.confirmCaptcha()
    } else if (this.dialogMode === 'block_words') {
      this.confirmBlockWords()
    }
  }

  /**
   * 数据源层发起验证码挑战：暂存回调和图片并打开弹窗，
   * 用户点「确定」时 resolve 验证码、点「取消」时 reject
   */
  private handleCaptchaChallenge(challenge: CaptchaChallenge): Promise<string> {
    return new Promise<string>((resolve: (code: string) => void, reject: (error: Error) => void) => {
      this.captchaChallengeResolve = resolve
      this.captchaChallengeReject = reject
      this.captchaRefresh = challenge.refresh
      this.dialogMode = 'captcha'
      this.dialogTitle = '安全验证'
      this.dialogSubtitle = '当前数据源搜索需要验证，请输入图片中的字符'
      this.captchaImage = challenge.pixelMap
      this.captchaCode = ''
      this.commonDialog?.open()
    })
  }

  private confirmCaptcha(): void {
    const code = this.captchaCode.trim()
    if (code.length === 0) {
      ToastUtil.showToast({ message: '请输入验证码' }, `${tag}.confirmCaptcha`)
      return
    }
    this.commonDialog?.close()
    const resolve = this.captchaChallengeResolve
    this.captchaChallengeResolve = null
    this.captchaChallengeReject = null
    this.captchaRefresh = null
    if (resolve) {
      resolve(code)
    }
  }

  private cancelCaptcha(): void {
    this.commonDialog?.close()
    const reject = this.captchaChallengeReject
    this.captchaChallengeResolve = null
    this.captchaChallengeReject = null
    this.captchaRefresh = null
    if (reject) {
      reject(new Error('已取消验证码输入'))
    }
  }

  private async refreshCaptcha(): Promise<void> {
    if (!this.captchaRefresh) {
      return
    }
    try {
      this.captchaImage = await this.captchaRefresh()
    } catch (e) {
      Logger.e('fail', `${tag} 刷新验证码失败`, e)
      ToastUtil.showToast({ message: '刷新验证码失败' }, `${tag}.refreshCaptcha`)
    }
  }

  @Builder captchaContent() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        if (this.captchaImage) {
          Image(this.captchaImage)
            .width(130)
            .height(44)
            .objectFit(ImageFit.Contain)
            .borderRadius(4)
            .backgroundColor($r('app.color.background_color'))
        }
        Text('换一张')
          .fontColor($r('app.color.primary_color'))
          .fontSize(14)
          .onClick(() => {
            this.refreshCaptcha()
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      TextInput({ text: this.captchaCode, placeholder: '输入验证码' })
        .type(InputType.Normal)
        .width('100%')
        .height(48)
        .borderRadius(8)
        .fontSize(16)
        .onChange((v: string) => {
          this.captchaCode = v
        })
    }
    .width('100%')
  }

  build() {
    NavDestination() {
      TitleBar({
        searchPlaceholder: '输入关键字...',
        searchText: this.keyword,
        onSearchChange: (value: string) => {
          this.keyword = value
          // 手动清空搜索框：退回搜索记录页
          if (value.trim() === '' && this.categoryViewModel.state !== ViewState.CUSTOM &&
            this.categoryViewModel.state !== ViewState.LOADING) {
            this.categoryViewModel.backToHistory()
          }
        },
        onSearchSubmit: (value: string) => {
          this.doSearch(value)
        },
        buttons: [
          {
            text: '搜索',
            width: 48,
            fontColor: $r('app.color.primary_color'),
            action: () => {
              this.doSearch(this.keyword)
            }
          },
          {
            image: $r('app.media.ic_setting'),
            iconSize: 22,
            width: 48,
            fontColor: $r('app.color.color_text_major'),
            menuTitle: '搜索菜单',
            menuItems: this.getSearchMenuItems()
          }
        ]
      })
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
    .padding({top: AnimeState.topRectHeight, bottom: AnimeState.bottomRectHeight - 20})
    .backgroundColor($r('app.color.background_color_accent'))
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
    .onBackPressed((): boolean => {
      // 搜索历史删除模式：返回先退出编辑状态
      if (this.historyEditMode) {
        this.historyEditMode = false
        return true
      }
      // 搜索结果已展示（内容/空态/错误态）：返回先退回搜索记录
      if (this.categoryViewModel.state !== ViewState.CUSTOM &&
        this.categoryViewModel.state !== ViewState.LOADING) {
        this.categoryViewModel.backToHistory()
        return true
      }
      return false
    })
    .bindSheet(this.showScopeSheet!!, this.ScopeSheet(), {
      detents: [600],
      showClose: true,
      dragBar: false,
      backgroundColor: $r('app.color.color_card'),
      keyboardAvoidMode: SheetKeyboardAvoidMode.RESIZE_ONLY,
      scrollSizeMode: ScrollSizeMode.CONTINUOUS,
      preferType: SheetType.CENTER,
      onDisappear: () => {
        this.showScopeSheet = false
      }
    })
  }

  @Builder content() {
    if (this.resultStyle === 'list') {
      SearchResultList({ videoList: this.categoryViewModel.videoList })
        .height('100%')
    } else {
      VideoList({ videoList: this.categoryViewModel.videoList, showSourceBadge: true })
        .height('100%')
    }
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
        if (this.historyEditMode) {
          Text('完成')
            .fontSize(14)
            .fontColor($r('app.color.primary_color'))
            .onClick(() => {
              this.historyEditMode = false
            })
        } else {
          Image($r('app.media.ic_delete'))
            .width(20)
            .height(20)
            .alignSelf(ItemAlign.End)
            .onClick(() => {
              this.clearHistory()
            })
        }
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
          if (this.historyEditMode) {
            Text('删除模式：点击标签删除对应记录')
              .fontSize(12)
              .fontColor($r('app.color.color_text_minor'))
              .margin({ top: 0, bottom: 4 })
          }
          Flex({ alignItems: ItemAlign.Start, justifyContent: FlexAlign.Start, wrap: FlexWrap.Wrap }) {
            ForEach(searchViewModel.searchHistoryList, (item: SearchHistoryInfo) => {
              Stack() {
                Text(item.keyword)
                  .backgroundColor($r('sys.color.button_background_color_transparent'))
                  .padding({ top: 4, bottom: 4, left: 8, right: 8 })
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center)
                  .borderRadius(6)
                  .borderRadius(4)
                  .fontWeight(300)
                  .fontSize(14)
                  .maxLines(1)
                  .margin(3)
                  .constraintSize({
                    minWidth: '15%',
                    maxWidth: '50%'
                  })
                if (this.historyEditMode) {
                  SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
                    .fontSize(12)
                    .fontColor([$r('sys.color.font_tertiary')])
                }
              }
              .align(Alignment.TopEnd)
              .constraintSize({
                minWidth: '15%',
                maxWidth: '50%'
              })
              .margin(6)
              .onClick(() => {
                if (this.historyEditMode) {
                  this.deleteHistoryItem(item.keyword)
                } else {
                  this.doSearch(item.keyword)
                }
              })
              .gesture(LongPressGesture()
                .onAction(() => {
                  this.historyEditMode = true
                }))
            }, (item: SearchHistoryInfo): string => item.keyword)
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
    if (this.keyword.trim().length == 0) {
      ToastUtil.showToast({ message: '请输入关键词' }, `${tag}.doSearch`)
      return
    }
    this.historyEditMode = false
    // 记录搜索历史（VM 内去重后自动刷新历史列表）
    searchViewModel.addHistory(this.keyword)
    // 执行搜索（应用精准/模糊匹配、屏蔽词过滤与搜索范围限定）
    await this.categoryViewModel.search(
      this.keyword,
      appSettings.search_precise,
      searchViewModel.getBlockWords(),
      searchViewModel.getSearchSourceKeys()
    )
    // 搜索完成后按设置与结果解析展示样式
    this.resolveResultStyle()
  }

  /**
   * 是否携带扩展信息（播放量/年份/月份/导演/演员/标签 任一非空）
   */
  private hasExtendedInfo(item: VideoInfo): boolean {
    return (item.playCount ?? '').trim() !== '' || (item.year ?? '').trim() !== '' ||
      (item.month ?? '').trim() !== '' || (item.director ?? '').trim() !== '' ||
      (item.actors ?? '').trim() !== '' || (item.tags ?? '').trim() !== ''
  }

  /**
   * 解析结果展示样式：设置固定 card/list 直接生效；
   * auto 时按源分组投票——某源过半结果带扩展信息则该源投列表票，多源取多数，平票归卡片
   */
  private resolveResultStyle(): void {
    const setting: string = appSettings.search_result_style
    if (setting === 'card' || setting === 'list') {
      this.resultStyle = setting
      return
    }
    const results: VideoInfo[] = this.categoryViewModel.videoList
    if (results.length === 0) {
      this.resultStyle = 'card'
      return
    }
    const totals: Map<string, number> = new Map<string, number>()
    const extended: Map<string, number> = new Map<string, number>()
    for (const item of results) {
      totals.set(item.sourceKey, (totals.get(item.sourceKey) ?? 0) + 1)
      if (this.hasExtendedInfo(item)) {
        extended.set(item.sourceKey, (extended.get(item.sourceKey) ?? 0) + 1)
      }
    }
    let listVotes: number = 0
    let cardVotes: number = 0
    totals.forEach((total: number, key: string) => {
      const ext: number = extended.get(key) ?? 0
      if (ext * 2 > total) {
        listVotes++
      } else {
        cardVotes++
      }
    })
    this.resultStyle = listVotes > cardVotes ? 'list' : 'card'
  }

  /**
   * 切换结果展示样式并持久化
   */
  private setResultStyle(style: string): void {
    appSettings.search_result_style = style
    this.resolveResultStyle()
    ToastUtil.showToast({ message: '已切换为' + this.resultStyleLabel() + '样式' }, `${tag}.setResultStyle`)
  }

  /**
   * 当前样式设置显示名
   */
  private resultStyleLabel(): string {
    if (appSettings.search_result_style === 'card') {
      return '卡片'
    }
    if (appSettings.search_result_style === 'list') {
      return '列表'
    }
    return '自动'
  }

  /**
   * 删除单条搜索历史（删除模式）
   */
  private async deleteHistoryItem(keyword: string) {
    await searchViewModel.deleteHistory(keyword)
    if (searchViewModel.searchHistoryList.length === 0) {
      this.historyEditMode = false
    }
  }

  /**
   * 搜索设置菜单项（精准搜索/屏蔽词/源管理/范围限定）
   */
  private getSearchMenuItems(): MenuItem[] {
    const menuItems: MenuItem[] = [
      {
        name: '精准搜索',
        value: 'precise_search',
        symbolStart: 'curve_magnifyingglass',
        checked: appSettings.search_precise,
        action: () => {
          appSettings.search_precise = !appSettings.search_precise
        }
      },
      {
        name: '结果屏蔽词',
        value: 'block_words',
        symbolStart: 'minus_magnifyingglass',
        action: () => {
          this.showBlockWordsDialog()
        }
      },
      {
        name: '视频源管理',
        value: 'source_manage',
        symbolStart: 'satellite_map',
        action: () => {
          AnimeState.pageStack.pushPathByName('VideoSources', '', true)
        }
      }
    ]
    // 结果展示样式（二级子菜单：卡片/列表/自动），仅在显示搜索结果时出现
    const state = this.categoryViewModel.state
    if (state !== ViewState.CUSTOM && state !== ViewState.LOADING) {
      menuItems.push({
        name: '切换样式',
        value: 'result_style',
        symbolStart: 'adjustment',
        labelInfo: this.resultStyleLabel(),
        children: [
          {
            name: '卡片',
            value: 'style_card',
            symbolStart: 'square_grid_2x2',
            checked: appSettings.search_result_style === 'card',
            action: (): void => {
              this.setResultStyle('card')
            }
          },
          {
            name: '列表',
            value: 'style_list',
            symbolStart: 'square_text_grid_1x2',
            checked: appSettings.search_result_style === 'list',
            action: (): void => {
              this.setResultStyle('list')
            }
          },
          {
            name: '自动',
            value: 'style_auto',
            symbolStart: 'character_square',
            checked: appSettings.search_result_style === 'auto',
            action: (): void => {
              this.setResultStyle('auto')
            }
          }
        ]
      })
    }
    menuItems.push(
      {
        name: '多分组/源',
        value: 'scope_select',
        symbolStart: 'square_grid_2x2_checkmark_topleft_filled',
        checked: appSettings.search_scope !== 'all',
        action: () => {
          this.openScopeSheet()
        }
      },
      {
        name: '全部源',
        value: 'scope_all',
        symbolStart: 'more',
        checked: appSettings.search_scope === 'all',
        action: () => {
          appSettings.search_scope = 'all'
        }
      }
    )
    // 追加源分组项（与视频源管理同步），单击即在对应分组内搜索
    const selectedGroups = appSettings.search_scope === 'group'
      ? searchViewModel.parseStringArray(appSettings.search_scope_groups)
      : []
    for (const group of searchViewModel.getSyncedGroups()) {
      menuItems.push({
        name: group,
        value: 'scope_group_' + group,
        symbolStart: 'search_things',
        checked: selectedGroups.includes(group),
        action: (): void => {
          appSettings.search_scope = 'group'
          appSettings.search_scope_groups = JSON.stringify([group])
        }
      })
    }
    return menuItems
  }

  /**
   * 屏蔽词弹窗（复用公共弹窗，首选项持久化）
   */
  private showBlockWordsDialog(): void {
    this.dialogMode = 'block_words'
    this.dialogTitle = '搜索结果屏蔽词'
    this.dialogSubtitle = '多个屏蔽词用逗号或空格分隔，标题命中屏蔽词的结果将被过滤'
    this.blockWordsInput = appSettings.search_block_words
    this.commonDialog?.open()
  }

  private confirmBlockWords(): void {
    appSettings.search_block_words = this.blockWordsInput.trim()
    this.commonDialog?.close()
    ToastUtil.showToast({ message: '屏蔽词已保存' }, `${tag}.confirmBlockWords`)
  }

  @Builder blockWordsContent() {
    Column({ space: 12 }) {
      TextInput({ text: this.blockWordsInput, placeholder: '输入屏蔽词，逗号或空格分隔' })
        .type(InputType.Normal)
        .width('100%')
        .height(48)
        .borderRadius(8)
        .fontSize(16)
        .onChange((v: string) => {
          this.blockWordsInput = v
        })
    }
    .width('100%')
  }

  /**
   * 打开搜索范围选择弹窗（分组与视频源管理同步）
   */
  private openScopeSheet(): void {
    this.scopeGroupOptions = searchViewModel.getSyncedGroups()
    this.scopeSourceOptions = searchViewModel.getSearchableSourceConfigs()
    this.selectedScopeGroups = searchViewModel.parseStringArray(appSettings.search_scope_groups)
    this.selectedScopeSources = searchViewModel.parseStringArray(appSettings.search_scope_sources)
    this.scopeTab = appSettings.search_scope === 'source' ? 'source' : 'group'
    this.scopeSelectedIndex = this.scopeTab === 'source' ? 1 : 0
    this.showScopeSheet = true
  }

  private toggleScopeGroup(group: string): void {
    if (this.selectedScopeGroups.includes(group)) {
      this.selectedScopeGroups = this.selectedScopeGroups.filter((item: string): boolean => item !== group)
    } else {
      this.selectedScopeGroups = [...this.selectedScopeGroups, group]
    }
  }

  private toggleScopeSource(sourceKey: string): void {
    if (this.selectedScopeSources.includes(sourceKey)) {
      this.selectedScopeSources = this.selectedScopeSources.filter((item: string): boolean => item !== sourceKey)
    } else {
      this.selectedScopeSources = [...this.selectedScopeSources, sourceKey]
    }
  }

  private toggleScopeSelectAll(): void {
    if (this.scopeTab === 'group') {
      this.selectedScopeGroups = this.selectedScopeGroups.length === this.scopeGroupOptions.length
        ? [] : [...this.scopeGroupOptions]
    } else {
      this.selectedScopeSources = this.selectedScopeSources.length === this.scopeSourceOptions.length
        ? [] : this.scopeSourceOptions.map((config: DataSourceConfig): string => config.key)
    }
  }

  private isScopeAllSelected(): boolean {
    if (this.scopeTab === 'group') {
      return this.scopeGroupOptions.length > 0
        && this.selectedScopeGroups.length === this.scopeGroupOptions.length
    }
    return this.scopeSourceOptions.length > 0
      && this.selectedScopeSources.length === this.scopeSourceOptions.length
  }

  /**
   * 确认搜索范围选择（持久化勾选结果）
   */
  private confirmScopeSelection(): void {
    if (this.scopeTab === 'group') {
      if (this.selectedScopeGroups.length === 0) {
        ToastUtil.showToast({ message: '请至少选择一个分组' }, `${tag}.confirmScopeSelection`)
        return
      }
      appSettings.search_scope = 'group'
      appSettings.search_scope_groups = JSON.stringify(this.selectedScopeGroups)
    } else {
      if (this.selectedScopeSources.length === 0) {
        ToastUtil.showToast({ message: '请至少选择一个源' }, `${tag}.confirmScopeSelection`)
        return
      }
      appSettings.search_scope = 'source'
      appSettings.search_scope_sources = JSON.stringify(this.selectedScopeSources)
    }
    this.showScopeSheet = false
    ToastUtil.showToast({ message: '搜索范围已保存' }, `${tag}.confirmScopeSelection`)
  }

  /**
   * 搜索范围选择弹窗（顶部切换多分组/多源，下方勾选列表）
   */
  @Builder ScopeSheet() {
    Column() {
      TitleBar({ showBack: false, title: '搜索范围', rightInset: 56 })
      // 顶部切换：多分组 / 多源（系统V2胶囊分段按钮）
      Column() {
        CapsuleSegmentButtonV2({
          items: this.scopeSegmentItems,
          selectedIndex: this.scopeSelectedIndex!!,
          onItemClicked: (index: number) => {
            this.scopeTab = index === 1 ? 'source' : 'group'
          }
        })
      }
      .margin({ top: 8, left: 16, right: 16 })

      Text(this.scopeTab === 'group' ? '在选中的分组内搜索，分组与视频源管理保持同步' : '在选中的源内搜索')
        .fontSize(12)
        .fontColor($r('app.color.color_text_minor'))
        .margin({ top: 10, bottom: 10 })

      List({ space: 10 }) {
        if (this.scopeTab === 'group') {
          ForEach(this.scopeGroupOptions, (group: string) => {
            ListItem() {
              Row({ space: 12 }) {
                Image(this.selectedScopeGroups.includes(group) ?
                  $r('app.media.ic_selection_selected') :
                  $r('app.media.ic_selection_none'))
                  .width(22)
                  .height(22)
                  .fillColor(this.selectedScopeGroups.includes(group) ?
                    $r('app.color.primary_color_accent') :
                    $r('app.color.color_text_minor'))
                Text(group)
                  .fontSize(15)
                  .fontColor($r('app.color.color_text_major'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ top: 14, bottom: 14, left: 14, right: 14 })
              .borderRadius(12)
              .backgroundColor($r('sys.color.button_background_color_transparent'))
              .onClick(() => {
                this.toggleScopeGroup(group)
              })
            }
          }, (group: string): string => group)
        } else {
          ForEach(this.scopeSourceOptions, (config: DataSourceConfig) => {
            ListItem() {
              Row({ space: 12 }) {
                Image(this.selectedScopeSources.includes(config.key) ?
                  $r('app.media.ic_selection_selected') :
                  $r('app.media.ic_selection_none'))
                  .width(22)
                  .height(22)
                  .fillColor(this.selectedScopeSources.includes(config.key) ?
                    $r('app.color.primary_color_accent') :
                    $r('app.color.color_text_minor'))
                Column() {
                  Text(config.name)
                    .fontSize(15)
                    .fontColor($r('app.color.color_text_major'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (config.group && config.group.trim() !== '') {
                    Text(config.group)
                      .fontSize(12)
                      .fontColor($r('app.color.color_text_minor'))
                      .margin({ top: 2 })
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .padding({ top: 12, bottom: 12, left: 14, right: 14 })
              .borderRadius(12)
              .backgroundColor($r('sys.color.button_background_color_transparent'))
              .onClick(() => {
                this.toggleScopeSource(config.key)
              })
            }
          }, (config: DataSourceConfig): string => config.key)
        }
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16 })

      // 底部操作栏
      Row() {
        Row({ space: 8 }) {
          Image(this.isScopeAllSelected() ?
            $r('app.media.ic_selection_selected') :
            $r('app.media.ic_selection_none'))
            .width(22)
            .height(22)
            .fillColor(this.isScopeAllSelected() ?
              $r('app.color.primary_color_accent') :
              $r('app.color.color_text_minor'))
          Text(this.isScopeAllSelected() ? '全不选' : '全选')
            .fontSize(14)
            .fontColor($r('app.color.color_text_major'))
        }
        .onClick(() => {
          this.toggleScopeSelectAll()
        })
        Blank()
        Button('确定')
          .fontSize(14)
          .height(36)
          .padding({ left: 24, right: 24 })
          .backgroundColor($r('app.color.primary_color'))
          .onClick(() => {
            this.confirmScopeSelection()
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 16 })
    }
    .width('100%')
    .height('100%')
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
