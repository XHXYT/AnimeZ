import { DataSourceConfig } from "../api/DataSourceConfig"
import { dataSourceManager } from "../api/DataSourceManager"
import { AppConfigs } from "../entryability/Settings"
import { VIDEO_SOURCE_EVENT } from "../utils/EventBus"
import Logger from "../utils/Logger"
import { SelectionManager } from "../utils/SelectionManager"
import { ToastUtil } from "../utils/ToastUtils"

// 排序类型枚举
export enum SortType {
  PRIORITY = 'priority',
  NAME = 'name',
  ENABLED = 'enabled',
  CUSTOM = 'custom'
}

// 视图状态枚举
export enum ViewState {
  LOADING = 0,
  CONTENT = 1,
  ERROR = 2,
  EMPTY = 3
}

@Observed
export class VideoSourcesViewModel {
  // 视图状态
  public state: ViewState
  public errorMessage: string

  // 弹窗输入文本
  public dialogInputTextValue: string = ''

  // 选择相关状态
  public selectCount: number
  public selectMode: boolean
  public hasSelectAll: boolean

  // 排序和分组控制
  public sortType: SortType
  public searchText: string

  // 分组管理相关状态
  public groupManagerVisible: boolean
  public groupType: string
  public customGroups: string[]
  public newGroupName: string

  // 数据源列表
  public videoSources: DataSourceConfig[]
  // 持久化配置
  public appSettings: AppConfigs = new AppConfigs()
  public pageStack: NavPathStack = new NavPathStack()

  // 业务逻辑对象
  public selectionManager: SelectionManager<DataSourceConfig>

  constructor(selectionManager: SelectionManager<DataSourceConfig>) {
    this.state = ViewState.CONTENT
    this.errorMessage = ''
    this.videoSources = []
    this.selectCount = 0
    this.selectMode = false
    this.hasSelectAll = false
    this.sortType = SortType.PRIORITY
    this.searchText = ''
    this.groupManagerVisible = false
    this.groupType = '不分组'
    this.customGroups = []
    this.newGroupName = ''
    this.selectionManager = selectionManager
  }

  // 初始化数据
  async initialize() {
    this.sortType = this.appSettings.video_sources_order
    try {
      this.state = ViewState.LOADING
      await this.loadSources()
      this.state = ViewState.CONTENT
    } catch (error) {
      this.state = ViewState.ERROR
      this.errorMessage = `加载失败: ${error.message}`
    }
  }

  // 加载数据源
  async loadSources() {
    this.getSources()
  }

  // 获取数据源（应用排序和分组）
  getSources() {
    // 获取原始数据
    let sources = dataSourceManager.getPrioritizedDataSourceConfigs()
    // 应用搜索过滤
    if (this.searchText) {
      sources = sources.filter(source =>
      source.name.toLowerCase().includes(this.searchText.toLowerCase()) ||
      source.key.toLowerCase().includes(this.searchText.toLowerCase())
      )
    }
    // 应用排序
    sources = this.applySorting(sources)
    // 应用分组
    this.videoSources = this.applyGrouping(sources)
  }

  // 加载自定义分组
  public loadCustomGroups() {
    try {
      let savedGroups: string[] = []
      const savedGroupsData = this.appSettings.video_sources_group_filter_manager
      if (savedGroupsData) {
        savedGroups = JSON.parse(savedGroupsData) as string[]
      }
      // 从数据源中提取当前分组
      this.extractGroupsFromSources()
      const sourceGroups = this.customGroups
      // 合并持久化分组和数据源分组
      const mergedGroups = this.mergeGroups(savedGroups, sourceGroups)
      // 保存合并后的分组（不自动清理）
      this.customGroups = mergedGroups
      this.saveCustomGroups()
    } catch (error) {
      console.error('加载自定义分组失败:', error)
      this.customGroups = []
    }
  }

  // 合并分组列表
  private mergeGroups(savedGroups: string[], sourceGroups: string[]): string[] {
    const mergedSet = new Set<string>()
    // 添加持久化分组
    savedGroups.forEach(group => mergedSet.add(group))
    // 添加数据源分组
    sourceGroups.forEach(group => mergedSet.add(group))
    return Array.from(mergedSet).sort()
  }

  /**
   * 获取无效分组列表 => 供用户选择是否清理
   */
  private getUnusedGroups(): string[] {
    const allSources = dataSourceManager.getAllDataSourceConfigs()
    const usedGroups = new Set<string>()
    // 收集所有被使用的分组
    allSources.forEach(source => {
      if (source.group && source.group.trim() !== '') {
        // 使用 parseGroups 方法拆分分组字符串
        const sourceGroups = this.parseGroups(source.group)
        sourceGroups.forEach(group => {
          if (group && group.trim() !== '') {
            usedGroups.add(group.trim())
          }
        })
      }
    })
    // 返回未被使用的自定义分组（排除默认分组）
    return this.customGroups.filter(group =>
    !['不分组', '已启用', '已禁用'].includes(group) && !usedGroups.has(group)
    )
  }

  // 用户主动清理无效分组
  public cleanupUnusedGroups() {
    const unusedGroups = this.getUnusedGroups()
    if (unusedGroups.length === 0) {
      ToastUtil.showToast({ message: "没有需要清理的分组" })
      return
    }
    // 显示确认对话框
    ToastUtil.showAlertDialog({
      title: '清理无效分组',
      message: `发现 ${unusedGroups.length} 个未被使用的分组：\n${unusedGroups.join(', ')}\n\n确认要删除这些分组吗？`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '确认删除',
        fontColor: Color.Red,
        action: () => {
          // 执行清理
          const allSources = dataSourceManager.getAllDataSourceConfigs()
          const usedGroups = new Set<string>()
          allSources.forEach(source => {
            if (source.group && source.group.trim() !== '') {
              usedGroups.add(source.group.trim())
            }
          })
          // 保留被使用的分组和默认分组
          this.customGroups = this.customGroups.filter(group =>
          ['不分组', '已启用', '已禁用'].includes(group) || usedGroups.has(group)
          )
          this.saveCustomGroups()
          ToastUtil.showToast({ message: `已清理 ${unusedGroups.length} 个无效分组` })
        }
      }
    })
  }

  // 从现有源配置中提取分组
  private extractGroupsFromSources() {
    const allSources = dataSourceManager.getAllDataSourceConfigs()
    const groups = new Set<string>()
    allSources.forEach(source => {
      if (source.group && source.group.trim() !== '') {
        // 使用 parseGroups 方法拆分分组字符串
        const sourceGroups = this.parseGroups(source.group)
        sourceGroups.forEach(group => {
          if (group && group.trim() !== '') {
            groups.add(group.trim())
          }
        })
      }
    })
    this.customGroups = Array.from(groups.values()).sort()
    this.saveCustomGroups()
  }

  // 添加新分组
  addCustomGroup(groupName: string) {
    if (groupName && groupName.trim() !== '') {
      const trimmedName = groupName.trim()
      // 检查是否已存在
      const exists = this.customGroups.some(group => group === trimmedName)
      if (!exists) {
        // 创建新数组而不是直接修改原数组
        this.customGroups = [...this.customGroups, trimmedName]
        this.saveCustomGroups()
        this.newGroupName = ''
        return true
      }
    }
    return false
  }

  // 删除自定义分组
  async removeCustomGroup(group: string) {
    // 检查是否为默认分组
    if (['不分组', '已启用', '已禁用'].includes(group)) {
      ToastUtil.showToast({ message: "默认分组不能删除哦" })
      return
    }
    // 更新所有使用该分组的源，从group字符串中移除该分组
    const allSources = dataSourceManager.getAllDataSourceConfigs()
    const updatePromises: Promise<void>[] = []
    allSources.forEach(source => {
      if (this.hasGroup(source, group)) {
        const updatedConfig = this.removeGroupFromSource(source, group)
        updatePromises.push(dataSourceManager.updateDataSource(source.key, updatedConfig))
      }
    })
    try {
      await Promise.all(updatePromises)
      // 从自定义分组列表中删除
      const index = this.customGroups.findIndex(g => g === group)
      if (index > -1) {
        this.customGroups.splice(index, 1)
        this.saveCustomGroups()
      }
      // 重新加载数据源
      await this.loadSources()
      ToastUtil.showToast({ message: `已删除分组"${group}"` })
    } catch (error) {
      ToastUtil.showToast({ message: "删除分组失败" })
    }
  }

  // 编辑分组名称
  async editCustomGroup(groupName: string, newGroupName: string) {
    if (!newGroupName || newGroupName.trim() === '') return false
    // 检查是否为默认分组
    if (['不分组', '已启用', '已禁用'].includes(groupName)) {
      ToastUtil.showToast({ message: "默认分组不能编辑哦" })
      return false
    }
    const trimmedName = newGroupName.trim()
    const groupToEditIndex = this.customGroups.findIndex(g => g === groupName)
    if (groupToEditIndex === -1) return false
    const groupToEdit = this.customGroups[groupToEditIndex]  // 通过索引获取
    // 检查新名称是否已存在
    const exists = this.customGroups.some(g => g === trimmedName && g !== groupName)
    if (exists) {
      ToastUtil.showToast({ message: "分组名称已存在" })
      return false
    }
    // 更新所有使用该分组的源
    const allSources = dataSourceManager.getAllDataSourceConfigs()
    const updatePromises: Promise<void>[] = []
    allSources.forEach(source => {
      if (this.hasGroup(source, groupToEdit)) {
        // 使用正则表达式替换分组名称
        const newGroupString = source.group.replace(
          new RegExp(`\\b${groupToEdit}\\b`, 'g'),
          trimmedName
        )
        const updatedConfig: DataSourceConfig = {
          key: source.key,
          version: source.version,
          name: source.name,
          group: newGroupString,
          description: source.description,
          baseUrl: source.baseUrl,
          enabled: source.enabled,
          priority: source.priority,
          defaultSource: source.defaultSource,
          parserConfig: source.parserConfig
        }
        updatePromises.push(dataSourceManager.updateDataSource(source.key, updatedConfig))
      }
    })
    try {
      await Promise.all(updatePromises)
      // 更新分组名称
      this.customGroups[groupToEditIndex] = trimmedName
      this.saveCustomGroups()
      // 重新加载数据源
      await this.loadSources()
      ToastUtil.showToast({ message: "分组名称已更新" })
      return true
    } catch (error) {
      ToastUtil.showToast({ message: "更新分组失败" })
      return false
    }
  }

  // 获取所有分组选项（包括默认选项和自定义分组）
  getAllGroupOptions(): Array<string> {
    const options: string[] = ['不分组', '已启用', '已禁用']
    // 添加自定义分组
    this.customGroups.forEach(group => {
      options.push(group)
    })
    return options
  }

  // 获取分组数据
  private getGroupedData(sources: DataSourceConfig[]): Map<string, DataSourceConfig[]> {
    const groups = new Map<string, DataSourceConfig[]>()
    switch (this.groupType) {
      case '已启用':
        groups.set('已启用', sources.filter(s => s.enabled))
        break
      case '已禁用':
        groups.set('已禁用', sources.filter(s => !s.enabled))
        break
      default:
      // 自定义分组 - 检查数据源是否包含该分组
        const groupConfig = this.customGroups.find(g => g === this.groupType)
        if (groupConfig) {
          groups.set(groupConfig, sources.filter(s => {
            const sourceGroups = this.parseGroups(s.group)
            return sourceGroups.includes(groupConfig)
          }))
        }
        break
    }
    return groups
  }

  // 检查分组名称是否存在
  isGroupNameExists(name: string, excludeValue?: string): boolean {
    return this.customGroups.some(g => g === name)
  }

  // 保存自定义分组到持久化存储
  private saveCustomGroups() {
    this.appSettings.video_sources_group_filter_manager = JSON.stringify(this.customGroups)
  }

  // 显示/隐藏分组管理窗口
  toggleGroupManager() {
    this.groupManagerVisible = !this.groupManagerVisible
  }

  // 获取过滤后的源（用于全选判断）
  public getFilteredSources(): DataSourceConfig[] {
    let sources = dataSourceManager.getAllDataSourceConfigs()
    if (this.searchText) {
      sources = sources.filter(source =>
      source.name.toLowerCase().includes(this.searchText.toLowerCase()) ||
      source.key.toLowerCase().includes(this.searchText.toLowerCase())
      )
    }
    return sources
  }

  // 排序逻辑
  private applySorting(sources: DataSourceConfig[]): DataSourceConfig[] {
    switch (this.sortType) {
      case SortType.PRIORITY:
        return sources.sort((a, b) => a.priority - b.priority)
      case SortType.NAME:
        return sources.sort((a, b) => a.name.localeCompare(b.name))
      case SortType.ENABLED:
        return sources.sort((a, b) => {
          if (a.enabled === b.enabled) return 0
          return a.enabled ? -1 : 1
        })
      case SortType.CUSTOM:
        return sources.sort((a, b) => {
          if (a.defaultSource !== b.defaultSource) {
            return a.defaultSource ? -1 : 1
          }
          if (a.enabled !== b.enabled) {
            return a.enabled ? -1 : 1
          }
          return a.priority - b.priority
        })
      default:
        return sources
    }
  }

  // 分组逻辑
  private applyGrouping(sources: DataSourceConfig[]): DataSourceConfig[] {
    if (this.groupType === '不分组') {
      return sources
    }
    // 对于分组筛选，直接返回过滤后的数据源，不添加分组标题
    const groups = this.getGroupedData(sources)
    let filteredSources: DataSourceConfig[] = []
    groups.forEach((items) => {
      filteredSources = filteredSources.concat(items)
    })
    return filteredSources
  }

  // 设置列表排序类型
  setSortType(type: SortType) {
    this.sortType = type
    this.appSettings.video_sources_order = type
    this.getSources()
  }

  // 设置分组筛选类型
  setGroupType(type: string) {
    if (type == 'group_manage') return
    this.groupType = type
    this.appSettings.video_sources_group_filter = type
    this.getSources()
  }

  // 设置搜索文本
  setSearchText(text: string) {
    this.searchText = text
    this.getSources()
  }

  // 切换界面选择状态
  toggleSelectionMode() {
    this.selectionManager.toggleSelectionMode()
  }

  // 切换项选择状态
  toggleItemSelection(item: DataSourceConfig) {
    this.selectionManager.toggleSelectItem(item)
  }

  // 全选/全不选
  toggleSelectAll() {
    if (this.hasSelectAll) {
      this.selectionManager.clearSelections()
    } else {
      this.selectionManager.selectItems(this.getFilteredSources())
    }
  }

  /**
   * 执行智能区间选择
   * 根据当前选中项自动确定区间并选中
   */
  executeRangeSelection(): void {
    if (!this.selectionManager.isSelectionMode()) {
      ToastUtil.showToast({ message: "请先进入选择模式" })
      return
    }
    const selectedCount = this.selectionManager.getSelectionCount()
    if (selectedCount < 2) {
      ToastUtil.showToast({ message: "请至少选择两个项目来创建区间" })
      return
    }
    const success = this.selectionManager.selectRangeBasedOnSelection(this.videoSources)
    if (success) {
      const firstItem = this.selectionManager.getFirstSelected()
      const lastItem = this.selectionManager.getLastSelected()
      const firstIndex = this.videoSources.findIndex(s => s.key === firstItem!.key)
      const lastIndex = this.videoSources.findIndex(s => s.key === lastItem!.key)
      ToastUtil.showToast({
        message: `已选中区间 ${firstIndex + 1} 到 ${lastIndex + 1}`
      })
    } else {
      ToastUtil.showToast({ message: "区间选择失败" })
    }
  }

  /**
   * 获取选中项的区间信息（用于提示）
   */
  getRangeInfo(): string {
    if (!this.selectionManager.isSelectionMode()) {
      return ""
    }
    const selectedCount = this.selectionManager.getSelectionCount()
    if (selectedCount === 0) {
      return "请选择项目"
    } else if (selectedCount === 1) {
      return "已选择1项，请继续选择"
    } else if (selectedCount === this.videoSources.length) {
      return "已经全选了哦"
    }  else {
      const firstItem = this.selectionManager.getFirstSelected()
      const lastItem = this.selectionManager.getLastSelected()
      if (firstItem && lastItem) {
        const firstIndex = this.videoSources.findIndex(s => s.key === firstItem.key)
        const lastIndex = this.videoSources.findIndex(s => s.key === lastItem.key)
        return `将选中区间 ${firstIndex + 1} 到 ${lastIndex + 1}`
      }
    }
    return ""
  }

  /**
   * 反选功能
   */
  toggleInverseSelection(): void {
    // 获取当前过滤后的所有数据源
    const filteredSources = this.getFilteredSources()
    // 获取当前已选中的数据源
    const selectedSources = Array.from(this.selectionManager.getSelections())
    // 清除所有选中状态
    this.selectionManager.clearSelections()
    // 选中之前未被选中的项
    const toSelect: DataSourceConfig[] = []
    for (let i = 0; i < filteredSources.length; i++) {
      const source = filteredSources[i]
      let isSelected = false
      // 检查是否在已选中列表中
      for (let j = 0; j < selectedSources.length; j++) {
        if (selectedSources[j].key === source.key) {
          isSelected = true
          break
        }
      }
      // 如果之前未被选中，则添加到待选中列表
      if (!isSelected) {
        toSelect.push(source)
      }
    }
    // 批量选中
    if (toSelect.length > 0) {
      this.selectionManager.selectItems(toSelect)
    }
    // 更新状态
    this.selectCount = toSelect.length
    this.hasSelectAll = toSelect.length === filteredSources.length
    Logger.i(this, `DataSourceManager.toggleInverseSelection Inverse selection completed: selected ${toSelect.length} items`)
  }

  /**
   * 重置为默认配置
   */
  resetToDefault() {
    ToastUtil.showAlertDialog({
      title: '重置配置',
      message: '确认要重置所有数据源为默认配置吗？此操作不可恢复。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '确定',
        fontColor: Color.Red,
        action: async () => {
          try {
            await dataSourceManager.resetToDefault()
            await this.initialize() // 重新加载数据
            ToastUtil.showToast({ message: "已重置为默认配置" })
          } catch (error) {
            ToastUtil.showToast({ message: "重置失败" })
          }
        }
      }
    })
  }

  /**
   * 启用选中的数据源
   */
  async enableSelectedItems(): Promise<boolean> {
    if (this.selectCount === 0) {
      return false
    }
    return new Promise((resolve) => {
      ToastUtil.showAlertDialog({
        title: '启用视频源',
        message: `确认启用选中的${this.selectCount}项视频源？`,
        primaryButton: {
          value: '取消',
          fontColor: $r('app.color.primary_color_accent'),
          action: () => resolve(false)
        },
        secondaryButton: {
          value: '确定',
          action: async () => {
            try {
              const data = Array.from(this.selectionManager.getSelections())
              const total = data.filter(item => item.key).length
              let completed = 0
              await Promise.all(
                data.map(async (item) => {
                  if (item.key && !item.enabled) {
                    // 手动创建新对象
                    const updatedConfig: DataSourceConfig = {
                      key: item.key,
                      name: item.name,
                      group: item.group,
                      baseUrl: item.baseUrl,
                      version: item.version,
                      enabled: true,
                      priority: item.priority,
                      description: item.description,
                      defaultSource: item.defaultSource,
                      parserConfig: item.parserConfig
                    }
                    await dataSourceManager.updateDataSource(item.key, updatedConfig)
                    completed++
                    ToastUtil.showToast({
                      message: `启用进度: ${completed}/${total}`
                    })
                  }
                }))
              ToastUtil.showToast({ message: "已启用选中的视频源" })
              this.selectionManager.clearSelections()
              // this.selectionManager.toggleSelectionMode()
              await this.loadSources()
              resolve(true)
            } catch (error) {
              ToastUtil.showToast({ message: "启用失败" })
              resolve(false)
            }
          }
        }
      })
    })
  }

  /**
   * 禁用选中的数据源
   */
  async disableSelectedItems(): Promise<boolean> {
    if (this.selectCount === 0) {
      return false
    }
    return new Promise((resolve) => {
      ToastUtil.showAlertDialog({
        title: '禁用视频源',
        message: `确认禁用选中的${this.selectCount}项视频源？`,
        primaryButton: {
          value: '取消',
          action: () => resolve(false)
        },
        secondaryButton: {
          value: '确定',
          fontColor: Color.Orange,
          action: async () => {
            try {
              const data = Array.from(this.selectionManager.getSelections())
              const total = data.filter(item => item.key).length
              let completed = 0
              await Promise.all(
                data.map(async (item) => {
                  if (item.key && item.enabled) {
                    // 手动创建新对象
                    const updatedConfig: DataSourceConfig = {
                      key: item.key,
                      name: item.name,
                      group: item.group,
                      baseUrl: item.baseUrl,
                      version: item.version,
                      enabled: false,
                      priority: item.priority,
                      description: item.description,
                      defaultSource: item.defaultSource,
                      parserConfig: item.parserConfig
                    }
                    await dataSourceManager.updateDataSource(item.key, updatedConfig)
                    completed++
                    ToastUtil.showToast({
                      message: `禁用进度: ${completed}/${total}`
                    })
                  }
                }))
              ToastUtil.showToast({ message: "已禁用选中的视频源" })
              this.selectionManager.clearSelections()
              // this.selectionManager.toggleSelectionMode()
              await this.loadSources()
              resolve(true)
            } catch (error) {
              ToastUtil.showToast({ message: "禁用失败" })
              resolve(false)
            }
          }
        }
      })
    })
  }

  /**
   * 为选中的数据源添加分组（支持多分组）
   */
  async addGroupToSelected(): Promise<boolean> {
    if (this.selectCount === 0) {
      return false
    }
    // 显示添加分组输入弹窗
    this.showInputDialog('添加分组', '请输入分组名称，多个分组用空格分隔')
    // 监听输入值变化
    return new Promise((resolve) => {
      // 使用定时器检查输入值
      const checkInput = setInterval(() => {
        if (this.dialogInputTextValue !== '') {
          clearInterval(checkInput)
          // 解析输入的分组名称
          const inputGroups = this.parseGroups(this.dialogInputTextValue)
          if (inputGroups.length === 0) {
            ToastUtil.showToast({ message: "请输入有效的分组名称" })
            this.dialogInputTextValue = ''
            resolve(false)
            return
          }
          // 检查分组名称是否有效
          const validGroups: string[] = []
          for (let i = 0; i < inputGroups.length; i++) {
            const group = inputGroups[i]
            if (group.trim() !== '') {
              validGroups.push(group.trim())
            }
          }
          if (validGroups.length === 0) {
            ToastUtil.showToast({ message: "请输入有效的分组名称" })
            this.dialogInputTextValue = ''
            resolve(false)
            return
          }
          // 执行添加操作
          this.executeAddGroups(validGroups).then(success => {
            this.dialogInputTextValue = ''
            this.selectionManager.clearSelections()
            resolve(success)
          })
        }
      }, 500)
    })
  }

  /**
   * 从选中的数据源移除分组（支持多分组）
   */
  async removeGroupFromSelected(): Promise<boolean> {
    if (this.selectCount === 0) {
      return false
    }
    const data = Array.from(this.selectionManager.getSelections())
    const allGroups = new Set<string>()
    data.forEach(item => {
      const groups = this.getSourceGroups(item)
      groups.forEach(group => allGroups.add(group))
    })
    if (allGroups.size === 0) {
      ToastUtil.showToast({ message: "选中的视频源没有分组" })
      return false
    }
    // 显示移除分组输入弹窗
    this.showInputDialog('移除分组', '请输入要移除的分组名称，多个分组用空格分隔')
    // 监听输入值变化
    return new Promise((resolve) => {
      // 使用定时器检查输入值变化
      const checkInput = setInterval(() => {
        if (this.dialogInputTextValue !== '') {
          clearInterval(checkInput)
          // 解析输入的分组名称
          const inputGroups = this.parseGroups(this.dialogInputTextValue)
          if (inputGroups.length === 0) {
            ToastUtil.showToast({ message: "请输入有效的分组名称" })
            this.dialogInputTextValue = ''
            resolve(false)
            return
          }
          // 检查输入的分组是否存在于选中项的分组中
          const validGroups: string[] = []
          const allGroupsArray: string[] = []
          allGroups.forEach(group => allGroupsArray.push(group))
          for (let i = 0; i < inputGroups.length; i++) {
            const group = inputGroups[i]
            if (group.trim() !== '' && allGroupsArray.includes(group)) {
              validGroups.push(group.trim())
            }
          }
          if (validGroups.length === 0) {
            ToastUtil.showToast({ message: "输入的分组不存在于选中项中" })
            this.dialogInputTextValue = ''
            resolve(false)
            return
          }
          // 执行移除操作
          this.executeRemoveGroups(validGroups).then(success => {
            this.dialogInputTextValue = ''
            this.selectionManager.clearSelections()
            resolve(success)
          })
        }
      }, 500)
    })
  }

  /**
   * 置顶选中的数据源
   */
  async pinSelectedItems(): Promise<boolean> {
    if (this.selectCount === 0) {
      return false
    }
    return new Promise((resolve) => {
      ToastUtil.showAlertDialog({
        title: '置顶视频源',
        message: `确认置顶选中的${this.selectCount}项视频源？\n这将按次序调整它们的优先级到最前面`,
        primaryButton: {
          value: '取消',
          action: () => resolve(false)
        },
        secondaryButton: {
          value: '确定',
          fontColor: $r('app.color.primary_color_accent'),
          action: async () => {
            try {
              const allSources = dataSourceManager.getAllDataSourceConfigs()
              const selectedData = Array.from(this.selectionManager.getSelections())
              // 获取当前最小优先级
              let minPriority = allSources[0].priority
              for (let i = 1; i < allSources.length; i++) {
                if (allSources[i].priority < minPriority) {
                  minPriority = allSources[i].priority
                }
              }
              // 为选中的数据源分配新的优先级
              const updates: Promise<void>[] = []
              for (let i = 0; i < selectedData.length; i++) {
                const item = selectedData[i]
                if (item.key) {
                  // 手动创建新对象
                  const updatedConfig: DataSourceConfig = {
                    key: item.key,
                    name: item.name,
                    group: item.group,
                    baseUrl: item.baseUrl,
                    version: item.version,
                    enabled: item.enabled,
                    priority: minPriority - (selectedData.length - i),
                    description: item.description,
                    defaultSource: item.defaultSource,
                    parserConfig: item.parserConfig
                  }
                  updates.push(dataSourceManager.updateDataSource(item.key, updatedConfig))
                }
              }
              const total = updates.length
              let completed = 0
              await Promise.all(
                updates.map(async (update) => {
                  await update
                  completed++
                  ToastUtil.showToast({
                    message: `置顶进度: ${completed}/${total}`
                  })
                })
              )
              // 置顶完成后，重新规范化所有优先级
              ToastUtil.showToast({ message: "正在优化优先级..." })
              await this.normalizeAllPriorities()
              ToastUtil.showToast({ message: "已置顶选中的视频源" })
              await this.loadSources()
              resolve(true)
            } catch (error) {
              ToastUtil.showToast({ message: "置顶失败" })
              resolve(false)
            }
          }
        }
      })
    })
  }

  async importFromFile(context:Context, overwrite: boolean) {
    const message = await dataSourceManager.importSourceConfigFromFile(context, overwrite)
    // 通知数据源变更
    VIDEO_SOURCE_EVENT.emit()
    ToastUtil.showToast({ message: message, duration: 2000 })
  }

  /**
   * 从网络导入数据源配置
   */
  async importFromNetwork(overwrite: boolean, importUrl?: string): Promise<boolean> {
    // 显示网络导入输入弹窗
    this.showNetworkImportDialog(importUrl)
    // 监听输入值变化
    return new Promise((resolve) => {
      // 使用定时器检查输入值
      const checkInput = setInterval(() => {
        if (this.dialogInputTextValue !== '') {
          clearInterval(checkInput)
          const urls = this.dialogInputTextValue.trim()
          if (!urls) {
            ToastUtil.showToast({ message: "请输入有效的URL" })
            this.dialogInputTextValue = ''
            resolve(false)
            return
          }
          // 执行网络导入操作
          this.executeNetworkImport(urls, overwrite).then(success => {
            this.dialogInputTextValue = ''
            // 通知数据源变更
            VIDEO_SOURCE_EVENT.emit()
            resolve(success)
          })
        }
      }, 500)
    })
  }

  /** 二维码导入 */
  async importFromQR(): Promise<boolean> {
    return new Promise((resolve) => {
      this.dialogInputTextValue = ''
      // 设置超时
      const timeout = setTimeout(() => {
        ToastUtil.showToast({ message: "扫描超时" })
        resolve(false)
      }, 30000) // 30秒超时
      ToastUtil.showQRDialog((value) => {
        clearTimeout(timeout)
        this.dialogInputTextValue = value
      }, 'VideoSourcesViewModel.importFromQR')
      // 监听QR返回值变化
      const checkInput = setInterval(() => {
        if (this.dialogInputTextValue !== '') {
          clearInterval(checkInput)
          clearTimeout(timeout)
          this.processQRResult(this.dialogInputTextValue.trim())
            .then(success => {
              this.dialogInputTextValue = ''
              resolve(success)
            })
            .catch((error: Error) => {
              this.dialogInputTextValue = ''
              Logger.e('fail', `二维码导入`, error)
              resolve(false)
            })
        }
      }, 500)
    })
  }

  /** 剪贴板导入 */
  async importFromClipboard(overwrite: boolean): Promise<boolean> {
    // 显示粘贴导入输入弹窗
    this.showClipboardImportDialog()
    // 监听输入值变化
    return new Promise((resolve) => {
      // 使用定时器检查输入值
      const checkInput = setInterval(() => {
        if (this.dialogInputTextValue !== '') {
          clearInterval(checkInput)
          const content = this.dialogInputTextValue.trim()
          if (!content) {
            ToastUtil.showToast({ message: "请输入有效配置文本" })
            this.dialogInputTextValue = ''
            resolve(false)
            return
          }
          // 执行剪贴板导入操作
          this.executeClipboardImport(content, overwrite).then(success => {
            this.dialogInputTextValue = ''
            // 通知数据源变更
            VIDEO_SOURCE_EVENT.emit()
            resolve(success)
          })
        }
      }, 500)
    })
  }

  /**
   * 处理二维码扫描结果
   */
  private async processQRResult(value: string): Promise<boolean> {
    if (!value) {
      ToastUtil.showToast({ message: "无效二维码" })
      return false
    }
    try {
      if (value.startsWith('http')) {
        // 链接导入弹窗
        this.importFromNetwork(this.appSettings.video_source_import_overwrite, value)
        return true
      } else {
        // JSON配置导入
        const message = await dataSourceManager.importSourceConfigFromJSON(
          value,
          this.appSettings.video_source_import_overwrite
        )
        // 通知数据源变更
        VIDEO_SOURCE_EVENT.emit()
        ToastUtil.showToast({ message: message, duration: 2000 })
        return true
      }
    } catch (error) {
      ToastUtil.showToast({ message: "导入失败" })
      Logger.e('tips', `processQRResult failed: ${error.message}`)
      return false
    }
  }

  /**
   * 执行网络导入操作
   */
  private async executeNetworkImport(urls: string, overwrite: boolean): Promise<boolean> {
    try {
      ToastUtil.showToast({ message: "正在从网络导入..." })
      // 调用 DataSourceManager 的远程导入方法
      const result = await dataSourceManager.importSourceConfigFromRemote(urls, overwrite)
      // 显示导入结果
      ToastUtil.showToast({ message: result })
      // 重新加载数据源
      await this.loadSources()
      Logger.i(this, `VideoSourcesViewModel.executeNetworkImport Import completed: ${result}`)
      return true
    } catch (error) {
      const message = `网络导入失败: ${error.message}`
      ToastUtil.showToast({ message: message, duration: 3000 })
      console.error(`VideoSourcesViewModel.executeNetworkImport ${message}`)
      return false
    }
  }

  /**
   * 执行剪贴板导入操作
   */
  private async executeClipboardImport(content: string, overwrite: boolean): Promise<boolean> {
    try {
      ToastUtil.showToast({ message: "正在从配置文本导入..." })
      // 调用 DataSourceManager 的JSON导入方法
      const result = await dataSourceManager.importSourceConfigFromJSON(content, overwrite)
      // 显示导入结果
      ToastUtil.showToast({ message: result, duration: 1500 })
      // 重新加载数据源
      await this.loadSources()
      Logger.i(this, `VideoSourcesViewModel.executeClipboardImport Import completed: ${result}`)
      return true
    } catch (error) {
      const message = `粘贴导入失败: ${error.message}`
      ToastUtil.showToast({ message: message, duration: 3000 })
      console.error(`VideoSourcesViewModel.executeClipboardImport ${message}`)
      return false
    }
  }

  /**
   * 显示网络导入输入弹窗
   */
  private showNetworkImportDialog(importUrl?: string): void {
    // 重置输入值
    if (importUrl) {
      this.dialogInputTextValue = importUrl
    } else {
      this.dialogInputTextValue = ''
    }
    // 构建帮助文本
    const helpText = `请输入远程配置文件的URL，支持：
• 单个URL：https://example.com/config.json
• 多个URL：用逗号或空格分隔
• 支持三种格式：
  - 标准配置文件
  - 配置数组
  - 单个配置对象`
    // 显示输入对话框
    ToastUtil.showInputDialog(
      '网络导入',
      helpText,
      (value) => {
        this.dialogInputTextValue = value
      },
      importUrl,
      'VideoSourcesViewModel.showNetworkImportDialog'
    )
  }

  /**
   * 显示粘贴导入输入弹窗
   */
  private showClipboardImportDialog(): void {
    // 重置输入值
    this.dialogInputTextValue = ''
    // 构建帮助文本
    const helpText = `请输入配置文件，支持三种格式：
  - 标准配置文本
  - 配置对象数组
  - 单个配置对象`
    // 显示输入对话框
    ToastUtil.showInputDialog(
      '粘贴导入',
      helpText,
      (value) => {
        this.dialogInputTextValue = value
      },
      '',
      'VideoSourcesViewModel.showNetworkImportDialog'
    )
  }

  /**
   * 导出选中的数据源配置
   */
  async exportSelectedItems(context: Context): Promise<boolean> {
    if (this.selectCount === 0) {
      ToastUtil.showToast({ message: "请先选择要导出的数据源" })
      return false
    }
    return new Promise((resolve) => {
      ToastUtil.showAlertDialog({
        title: '导出视频源',
        message: `确认导出选中的${this.selectCount}项视频源配置？`,
        primaryButton: {
          value: '取消',
          action: () => resolve(false)
        },
        secondaryButton: {
          value: '确定',
          fontColor: $r('app.color.primary_color_accent'),
          action: async () => {
            try {
              // 获取选中的配置
              const selectedConfigs = Array.from(this.selectionManager.getSelections())
              if (selectedConfigs.length === 0) {
                ToastUtil.showToast({ message: "请先选中配置哦" })
                resolve(false)
                return
              }
              // 调用 DataSourceManager 的导出方法
              const result = await dataSourceManager.exportDataSourceConfigs(
                context,
                selectedConfigs
              )
              // 显示导出结果
              ToastUtil.showToast({ message: result, duration: 3000 })
              Logger.i(this, `VideoSourcesViewModel.exportSelectedItems Export completed: ${result}`)
              resolve(true)
            } catch (error) {
              const message = `导出失败: ${error.message}`
              ToastUtil.showToast({ message: message })
              Logger.e('tips', `VideoSourcesViewModel.exportSelectedItems ${message}`)
              resolve(false)
            }
          }
        }
      })
    })
  }

  async exportSource(context: Context, config?: DataSourceConfig) {
    let message = ''
    if (config) {
      message = await dataSourceManager.exportDataSourceConfigs(context, [config])
    } else {
      message = await dataSourceManager.exportDataSourceConfigs(context)
    }
    ToastUtil.showToast({ message: message })
  }

  // 删除选中项
  async deleteSelectedItems(): Promise<boolean> {
    if (this.selectCount === 0) {
      return false
    }
    return new Promise((resolve) => {
      ToastUtil.showAlertDialog({
        title: '移除视频源',
        message: `确认移除选中的${this.selectCount}项视频源？`,
        primaryButton: {
          value: '取消',
          action: () => resolve(false)
        },
        secondaryButton: {
          value: '确定',
          fontColor: Color.Red,
          action: async () => {
            try {
              const data = Array.from(this.selectionManager.getSelections())
              // 显示一个更通用的提示，因为精确计数会因失败而误导
              ToastUtil.showToast({ message: "正在删除，请稍候..." })
              // 并行执行所有内存中的删除操作, 这里操作很快，因为不涉及文件IO
              await Promise.all(
                data.map(async (item) => {
                  if (item.key) {
                    await dataSourceManager.removeDataSource(item.key)
                  }
                }))
              // 所有内存配置删除成功后，统一保存一次配置文件，避免文件写入竞态条件
              await dataSourceManager.saveCurrentConfig()
              // 只有在全部成功后才执行到这里
              ToastUtil.showToast({ message: "全部删除成功" })
              this.selectionManager.toggleSelectionMode()
              await this.loadSources()
              resolve(true)
            } catch (error) {
              // 如果任何步骤出错，都会被这里捕获
              Logger.e('tips', `VideoSourcesViewModel.deleteSelectedItems failed: ${error.message}`)
              ToastUtil.showToast({ message: `删除失败: ${error.message || '未知错误'}` })
              // 即使失败，也尝试重新加载数据，以恢复界面状态
              await this.loadSources()
              resolve(false)
            }
          }
        }
      })
    })
  }

  /**
   * 重新规范化所有数据源的优先级
   * 将优先级重新分配为 10, 20, 30... 这样的间隔，便于后续插入
   */
  private async normalizeAllPriorities(): Promise<void> {
    try {
      const allSources = dataSourceManager.getAllDataSourceConfigs()
      // 按当前优先级排序
      const sortedSources = allSources.sort((a, b) => a.priority - b.priority)
      // 重新分配优先级，以10为间隔
      const updates: Promise<void>[] = []
      for (let i = 0; i < sortedSources.length; i++) {
        const source = sortedSources[i]
        const newPriority = (i + 1) * 10  // 从10开始，10, 20, 30...
        // 只有当优先级确实需要改变时才更新
        if (source.priority !== newPriority) {
          const updatedConfig: DataSourceConfig = {
            key: source.key,
            name: source.name,
            group: source.group,
            baseUrl: source.baseUrl,
            version: source.version,
            enabled: source.enabled,
            priority: newPriority,
            description: source.description,
            defaultSource: source.defaultSource,
            parserConfig: source.parserConfig
          }
          updates.push(dataSourceManager.updateDataSource(source.key, updatedConfig))
        }
      }
      // 批量更新
      if (updates.length > 0) {
        await Promise.all(updates)
        Logger.i(this, `Normalized priorities for ${updates.length} sources`)
      }
    } catch (error) {
      Logger.e('tips', `Failed to normalize priorities: ${error.message}`)
      throw new Error(`Failed to normalize priorities: ${error.message}`)
    }
  }

  /**
   * 执行添加分组操作
   */
  private async executeAddGroups(groups: string[]): Promise<boolean> {
    try {
      const data = Array.from(this.selectionManager.getSelections())
      const total = data.filter(item => item.key).length
      let completed = 0

      await Promise.all(
        data.map(async (item) => {
          if (item.key) {
            // 先复制原始配置
            let updatedConfig: DataSourceConfig = {
              key: item.key,
              name: item.name,
              group: item.group,
              baseUrl: item.baseUrl,
              version: item.version,
              enabled: item.enabled,
              priority: item.priority,
              description: item.description,
              defaultSource: item.defaultSource,
              parserConfig: item.parserConfig
            }

            // 添加输入的分组
            for (let i = 0; i < groups.length; i++) {
              updatedConfig = this.addGroupToSource(updatedConfig, groups[i])
            }

            await dataSourceManager.updateDataSource(item.key, updatedConfig)
            completed++
            ToastUtil.showToast({
              message: `分组进度: ${completed}/${total}`
            })
          }
        })
      )

      // 更新自定义分组列表
      for (let i = 0; i < groups.length; i++) {
        if (!this.customGroups.includes(groups[i])) {
          this.customGroups.push(groups[i])
        }
      }
      this.saveCustomGroups()

      ToastUtil.showToast({ message: `已添加到${groups.length}个分组` })
      await this.loadSources()
      return true
    } catch (error) {
      ToastUtil.showToast({ message: "添加分组失败" })
      return false
    }
  }

  /**
   * 执行移除分组操作
   */
  private async executeRemoveGroups(groups: string[]): Promise<boolean> {
    try {
      const data = Array.from(this.selectionManager.getSelections())
      const total = data.filter(item => item.key).length
      let completed = 0
      await Promise.all(
        data.map(async (item) => {
          if (item.key) {
            // 先复制原始配置
            let updatedConfig: DataSourceConfig = {
              key: item.key,
              name: item.name,
              group: item.group,
              baseUrl: item.baseUrl,
              version: item.version,
              enabled: item.enabled,
              priority: item.priority,
              description: item.description,
              defaultSource: item.defaultSource,
              parserConfig: item.parserConfig
            }
            // 移除输入的分组
            for (let i = 0; i < groups.length; i++) {
              updatedConfig = this.removeGroupFromSource(updatedConfig, groups[i])
            }
            await dataSourceManager.updateDataSource(item.key, updatedConfig)
            completed++
            ToastUtil.showToast({
              message: `移除进度: ${completed}/${total}`
            })
          }
        })
      )

      ToastUtil.showToast({ message: `已移除${groups.length}个分组` })
      await this.loadSources()
      return true
    } catch (error) {
      ToastUtil.showToast({ message: "移除分组失败" })
      return false
    }
  }

  /**
   * 为数据源添加分组
   */
  private addGroupToSource(source: DataSourceConfig, group: string): DataSourceConfig {
    const groups = this.parseGroups(source.group)
    if (!groups.includes(group)) {
      groups.push(group)
      // 手动创建新对象
      const newConfig: DataSourceConfig = {
        key: source.key,
        name: source.name,
        group: this.joinGroups(groups),
        baseUrl: source.baseUrl,
        version: source.version,
        enabled: source.enabled,
        priority: source.priority,
        description: source.description,
        defaultSource: source.defaultSource,
        parserConfig: source.parserConfig
      }
      return newConfig
    }
    return source
  }

  /**
   * 从数据源移除分组
   */
  private removeGroupFromSource(source: DataSourceConfig, group: string): DataSourceConfig {
    const groups = this.parseGroups(source.group)
    const index = groups.indexOf(group)
    if (index > -1) {
      groups.splice(index, 1)
      // 手动创建新对象
      const newConfig: DataSourceConfig = {
        key: source.key,
        name: source.name,
        group: this.joinGroups(groups),
        baseUrl: source.baseUrl,
        version: source.version,
        enabled: source.enabled,
        priority: source.priority,
        description: source.description,
        defaultSource: source.defaultSource,
        parserConfig: source.parserConfig
      }
      return newConfig
    }
    return source
  }

  /**
   * 获取数据源的所有分组
   */
  private getSourceGroups(source: DataSourceConfig): string[] {
    return this.parseGroups(source.group)
  }

  /**
   * 解析分组字符串为数组
   */
  private parseGroups(groupString: string): string[] {
    if (!groupString || groupString.trim() === '') {
      return []
    }
    return groupString.trim().split(/\s+/).filter(group => group.trim() !== '')
  }

  /**
   * 将分组数组连接为字符串
   */
  private joinGroups(groups: string[]): string {
    return groups.join(' ')
  }

  /**
   * 检查数据源是否属于指定分组
   */
  private hasGroup(source: DataSourceConfig, group: string): boolean {
    const groups = this.parseGroups(source.group)
    return groups.includes(group)
  }

  /**
   * 显示分组操作输入弹窗
   * @param title 弹窗标题
   * @param placeholder 输入框占位符
   */
  private showInputDialog(title: string, placeholder: string): void {
    // 重置输入值及弹窗
    this.dialogInputTextValue = ''
    // 动态更新弹窗配置
    ToastUtil.showInputDialog(title, placeholder, (value) => {
      this.dialogInputTextValue = value
    }, '', 'VideoSourcesViewModel.showInputDialog')
  }

  // 处理返回键
  handleBackPressed(): boolean {
    if (this.selectionManager.isSelectionMode()) {
      this.selectionManager.toggleSelectionMode()
      return true
    }
    return false
  }

  // 释放资源
  dispose() {

  }

}
