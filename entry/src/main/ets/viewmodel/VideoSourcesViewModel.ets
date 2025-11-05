import { DataSourceConfig, ParserConfig } from "../api/DataSourceConfig"
import { dataSourceManager } from "../api/DataSourceManager"
import { AppConfigs } from "../entryability/Settings"
import { VIDEO_SOURCES_EDIT_EVENT } from "../utils/EventBus"
import { OnSelectChangeObserver, SelectionManager } from "../utils/SelectionManager"
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
        usedGroups.add(source.group.trim())
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
    const groups = new Map<string, string>()
    allSources.forEach(source => {
      if (source.group && source.group.trim() !== '') {
        const groupName = source.group.trim()
        if (!groups.has(groupName)) {
          groups.set(groupName, groupName)
        }
      }
    })
    this.customGroups = Array.from(groups.values())
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
    const groupToRemove = this.customGroups.find(g => g === group)
    if (!groupToRemove) return
    // 更新所有使用该分组的源，将其group设为空
    const allSources = dataSourceManager.getAllDataSourceConfigs()
    const updatePromises: Promise<void>[] = []
    allSources.forEach(source => {
      if (source.group === groupToRemove) {
        const updatedConfig: DataSourceConfig = {
          key: source.key,
          version: source.version,
          name: source.name,
          group: '',
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
      // 从自定义分组列表中删除
      const index = this.customGroups.findIndex(g => g === group)
      if (index > -1) {
        this.customGroups.splice(index, 1)
        this.saveCustomGroups()
      }
      // 重新加载数据源
      await this.loadSources()
      ToastUtil.showToast({ message: `已删除分组"${groupToRemove}"` })
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
    let groupToEdit = this.customGroups.find(g => g === groupName)
    if (!groupToEdit) return false
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
      if (source.group === groupToEdit) {
        const updatedConfig: DataSourceConfig = {
          key: source.key,
          version: source.version,
          name: source.name,
          group: trimmedName,
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
      const index = this.customGroups.findIndex(g => g === groupName)
      if (index > -1) {
        this.customGroups[index] = trimmedName
        this.saveCustomGroups()
      }
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
      // 自定义分组
        const groupConfig = this.customGroups.find(g => g === this.groupType)
        if (groupConfig) {
          groups.set(groupConfig, sources.filter(s => s.group === groupConfig))
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

  goToSourceDetail(isNew: boolean) {
    if (isNew) {

    }
    // 跳转到新数据源详情页
    this.pageStack.pushPathByName('DataSourceDetailPage', null, true)
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
              const total = data.filter(item => item.key).length
              let completed = 0
              await Promise.all(
                data.map(async (item) => {
                  if (item.key) {
                    await dataSourceManager.removeDataSource(item.key)
                    completed++
                    ToastUtil.showToast({
                      message: `删除进度: ${completed}/${total}`
                    })
                  }
                })
              )
              ToastUtil.showToast({ message: "全部删除成功" })
              this.selectionManager.toggleSelectionMode()
              await this.loadSources() // 重新加载数据
              resolve(true)
            } catch (error) {
              ToastUtil.showToast({ message: "删除失败" })
              resolve(false)
            }
          }
        }
      })
    })
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
