import { DataSourceConfig, ParserConfig } from "../api/DataSourceConfig"
import { dataSourceManager } from "../api/DataSourceManager"
import { AppConfigs } from "../entryability/Settings"
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

export interface GroupConfig {
  name: string
  value: string,
  action?: () => void
}

@Observed
export class VideoSourcesViewModel {
  // 视图状态
  public state: ViewState = ViewState.CONTENT
  public errorMessage: string = ''

  // 选择相关状态
  public selectCount: number = 0
  public selectMode: boolean = false
  public hasSelectAll: boolean = false

  // 排序和分组控制
  public sortType: SortType = SortType.PRIORITY
  public searchText: string = ''

  // 分组管理相关状态
  public groupManagerVisible: boolean = false
  public groupType: string = 'not_filter'
  public customGroups: GroupConfig[] = []
  public newGroupName: string = ''

  // 数据源列表
  public videoSources: DataSourceConfig[] = []
  // 持久化配置
  public appSettings: AppConfigs = new AppConfigs()
  public pageStack: NavPathStack = new NavPathStack()

  // 业务逻辑对象
  public selectionManager: SelectionManager<DataSourceConfig>
  private selectionObserver: OnSelectChangeObserver<DataSourceConfig> = {
    onSelectionModeChange: (isSelectionMode: boolean) => {
      this.selectMode = isSelectionMode
      if (!this.selectMode) {
        this.selectCount = 0
      }
    },
    onSelectChange: (item: DataSourceConfig, isSelected) => {
      this.selectCount = this.selectionManager.getSelectionCount()
      this.hasSelectAll = this.selectCount == this.getFilteredSources().length
    }
  }

  constructor() {
    this.selectionManager = new SelectionManager<DataSourceConfig>()
    this.initSelectionObserver()
  }

  // 初始化选择观察者
  private initSelectionObserver() {
    this.selectionManager.addObserver(this.selectionObserver)
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
      const savedGroups = this.appSettings.video_sources_group_filter_manager
      if (savedGroups) {
        this.customGroups = JSON.parse(savedGroups) as GroupConfig[]
      } else {
        // 如果没有保存的自定义分组，从现有源配置中提取
        this.extractGroupsFromSources()
      }
    } catch (error) {
      console.error('加载自定义分组失败:', error)
      this.customGroups = []
    }
  }

  // 从现有源配置中提取分组
  private extractGroupsFromSources() {
    const allSources = dataSourceManager.getAllDataSourceConfigs()
    const groups = new Map<string, GroupConfig>()
    allSources.forEach(source => {
      if (source.group && source.group.trim() !== '') {
        const groupName = source.group.trim()
        if (!groups.has(groupName)) {
          groups.set(groupName, {
            name: groupName,
            value: 'group_' + groupName.replace(/\s+/g, '_').toLowerCase()
          })
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
      const exists = this.customGroups.some(group => group.name === trimmedName)

      if (!exists) {
        const newGroup: GroupConfig = {
          name: trimmedName,
          value: 'group_' + trimmedName.replace(/\s+/g, '_').toLowerCase() + Date.now()
        }
        this.customGroups.push(newGroup)
        this.saveCustomGroups()
        this.newGroupName = ''
        return true
      }
    }
    return false
  }

  // 删除自定义分组
  async removeCustomGroup(group: GroupConfig) {
    const groupToRemove = this.customGroups.find(g => g.value === group.value)
    if (!groupToRemove) return
    // 更新所有使用该分组的源，将其group设为空
    const allSources = dataSourceManager.getAllDataSourceConfigs()
    const updatePromises: Promise<void>[] = []
    allSources.forEach(source => {
      if (source.group === groupToRemove.name) {
        const updatedConfig: DataSourceConfig = {
          key: source.key,
          name: source.name,
          group: '',
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
      const index = this.customGroups.findIndex(g => g.value === group.value)
      if (index > -1) {
        this.customGroups.splice(index, 1)
        this.saveCustomGroups()
      }
      // 重新加载数据源
      await this.loadSources()
      ToastUtil.showToast({ message: `已删除分组"${groupToRemove.name}"` })
    } catch (error) {
      ToastUtil.showToast({ message: "删除分组失败" })
    }
  }

  // 编辑分组名称
  async editCustomGroup(groupValue: string, newName: string) {
    if (!newName || newName.trim() === '') return false

    const trimmedName = newName.trim()
    const groupToEdit = this.customGroups.find(g => g.value === groupValue)
    if (!groupToEdit) return false

    // 检查新名称是否已存在
    const exists = this.customGroups.some(g => g.name === trimmedName && g.value !== groupValue)
    if (exists) {
      ToastUtil.showToast({ message: "分组名称已存在" })
      return false
    }

    // 更新所有使用该分组的源
    const allSources = dataSourceManager.getAllDataSourceConfigs()
    const updatePromises: Promise<void>[] = []

    allSources.forEach(source => {
      if (source.group === groupToEdit.name) {
        const updatedConfig: DataSourceConfig = {
          key: source.key,
          name: source.name,
          group: trimmedName,
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
      groupToEdit.name = trimmedName
      // value保持不变，避免影响当前筛选状态
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
  getAllGroupOptions(): Array<GroupConfig> {
    const options: GroupConfig[] = [
      { name: '不分组', value: 'not_filter' },
      { name: '已启用', value: 'enabled' },
      { name: '已禁用', value: 'disabled' }
    ]

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
      case 'enabled':
        groups.set('已启用', sources.filter(s => s.enabled))
        break
      case 'disabled':
        groups.set('已禁用', sources.filter(s => !s.enabled))
        break
      default:
      // 自定义分组
        const groupConfig = this.customGroups.find(g => g.value === this.groupType)
        if (groupConfig) {
          groups.set(groupConfig.name, sources.filter(s => s.group === groupConfig.name))
        }
        break
    }

    return groups
  }

  // 根据value获取分组名称
  getGroupNameByValue(value: string): string {
    const group = this.customGroups.find(g => g.value === value)
    return group ? group.name : value
  }

  // 检查分组名称是否存在
  isGroupNameExists(name: string, excludeValue?: string): boolean {
    return this.customGroups.some(g => g.name === name && g.value !== excludeValue)
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
  private getFilteredSources(): DataSourceConfig[] {
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
    if (this.groupType === 'not_filter') {
      return sources
    }
    const groupedSources: DataSourceConfig[] = []
    const groups = this.getGroupedData(sources)
    groups.forEach((items, groupName) => {
      // 添加分组标题
      groupedSources.push(this.createGroupHeader(groupName))
      // 添加组内项目
      groupedSources.push(...items)
    })

    return groupedSources
  }

  // 创建分组标题项
  private createGroupHeader(groupName: string): DataSourceConfig {
    return {
      key: `group_header_${groupName}`,
      name: groupName,
      group: groupName,
      baseUrl: '',
      enabled: true,
      priority: -1,
      defaultSource: false,
      parserConfig: {} as ParserConfig
    }
  }

  // 设置排序类型
  setSortType(type: SortType) {
    this.sortType = type
    this.appSettings.video_sources_order = type
    this.getSources()
  }

  // 设置分组类型
  setGroupType(type: string) {
    this.groupType = type
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
    this.selectionManager.removeObserver(this.selectionObserver)
  }

}
