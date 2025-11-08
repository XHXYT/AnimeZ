import Logger from "./Logger";

/**
 * 多选监听者
 */
export interface OnSelectChangeObserver<T> {

    /**
     * 进入或退出选择模式
     */
    onSelectionModeChange(isSelectionMode: boolean): void

    /**
     * 选中或取消选中
     */
    onSelectChange(item: T, isSelect: boolean): void

}

/**
 * 多选管理器
 */
export class SelectionManager <T> {

    // 记录选中顺序的数组
    private selectionOrder: T[] = []
    // 锚点项目（用于区间选择）
    private anchorItem: T | null = null
    private selectionMode: boolean = false;
    private observers: OnSelectChangeObserver<T>[] = null
    private readonly selectionSet: Set<T> = new Set<T>()

    toggleSelectionMode() {
        this.clearSelections()
        this.selectionMode = !this.selectionMode
        if (this.observers) {
            this.observers.forEach((o) => {
                o.onSelectionModeChange(this.selectionMode)
            })
        }
    }

    isSelectionMode(): boolean {
        return this.selectionMode
    }

    selectItem(item: T): boolean {
        if (this.selectionSet.has(item)) {
            return false
        }
        this.selectionSet.add(item)
        this.notifySelectionChange(item, true)
        return true
    }

    selectItems(items: T[]) {
        items.forEach((item) => {
            this.selectItem(item)
        })
    }

    unselectItems(items: T[]) {
        items.forEach((item) => {
            this.unselectItem(item)
        })
    }

    unselectItem(item: T): boolean {
        if (this.selectionSet.has(item)) {
            if (this.selectionSet.delete(item)) {
                this.notifySelectionChange(item, false)
                return true;
            }
        }
        return false
    }

    /**
     * 清除选中及选中顺序
     */
    clearSelections() {
        if (this.selectionSet.size > 0) {
            this.selectionSet.forEach((item) => {
                this.unselectItem(item)
            })
            this.selectionSet.clear()
        }
        // 清除选中顺序
        this.selectionOrder = []
    }

    /**
     * 重写 toggleSelectItem，记录选中顺序
     */
    toggleSelectItem(item: T) {
        const wasSelected = this.isSelect(item)

        if (this.selectItem(item)) {
            // 新选中，添加到顺序数组末尾
            if (!this.selectionOrder.includes(item)) {
                this.selectionOrder.push(item)
            }
            return
        }
        if (this.unselectItem(item)) {
            // 取消选中，从顺序数组中移除
            const index = this.selectionOrder.indexOf(item)
            if (index > -1) {
                this.selectionOrder.splice(index, 1)
            }
        }
    }

    /**
     * 获取选中顺序数组
     */
    getSelectionOrder(): T[] {
        return [...this.selectionOrder] // 返回副本
    }

    /**
     * 获取第一个选中的项目
     */
    getFirstSelected(): T | null {
        return this.selectionOrder.length > 0 ? this.selectionOrder[0] : null
    }

    /**
     * 获取最后一个选中的项目
     */
    getLastSelected(): T | null {
        return this.selectionOrder.length > 0 ? this.selectionOrder[this.selectionOrder.length - 1] : null
    }

    /**
     * 执行区间选择（基于当前选中项）
     * @param allItems 所有项目列表
     */
    selectRangeBasedOnSelection(allItems: T[]): boolean {
        if (this.selectionOrder.length < 2) {
            console.warn('SelectionManager.selectRangeBasedOnSelection Need at least 2 items to select range')
            return false
        }
        const firstItem = this.getFirstSelected()!
        const lastItem = this.getLastSelected()!
        // 找到起始项目和结束项目在列表中的索引
        const startIndex = allItems.findIndex(i => this.isEqual(i, firstItem))
        const endIndex = allItems.findIndex(i => this.isEqual(i, lastItem))
        if (startIndex === -1 || endIndex === -1) {
            console.warn('SelectionManager.selectRangeBasedOnSelection Cannot find items in list')
            return false
        }
        // 确定选择范围
        const minIndex = Math.min(startIndex, endIndex)
        const maxIndex = Math.max(startIndex, endIndex)
        // 清除现有选择
        this.clearSelections()
        // 选中区间内的所有项目
        for (let i = minIndex; i <= maxIndex; i++) {
            this.selectItem(allItems[i])
            // 更新选中顺序
            this.selectionOrder.push(allItems[i])
        }
        console.info(`SelectionManager.selectRangeBasedOnSelection Selected range ${minIndex} to${maxIndex}`)
        return true
    }

    private notifySelectionChange(item: T, isSelect: boolean) {
        if (this.observers) {
            this.observers.forEach((o) => {
                o.onSelectChange(item, isSelect)
            })
        }
    }

    /**
     * 判断两个项目是否相等（需要根据实际情况实现）
     */
    private isEqual(item1: T, item2: T): boolean {
        // 对于对象类型，直接比较 key
        if (item1 && item2 && typeof item1 == 'object' && typeof item2 == 'object') {
            if ('key' in item1 && 'key' in item2) {
                return (item1 as any).key === (item2 as any).key
            }
        }
        return item1 === item2
    }

    isSelect(item: T): boolean {
        return this.selectionSet.has(item)
    }

    getSelections(): Set<T> {
        return this.selectionSet
    }

    getSelectionCount(): number {
        return this.selectionSet.size
    }

    addObserver(observer: OnSelectChangeObserver<T>) {
        if (!this.observers) {
            this.observers = []
        }
        this.observers.push(observer)
    }

    removeObserver(observer: OnSelectChangeObserver<T>): boolean {
        if (this.observers) {
            let index = this.observers.indexOf(observer);
            if (index >= 0) {
                this.observers.splice(index, 1);
                if (this.observers.length == 0) {
                    this.observers = null;
                }
                return true;
            }
        }
        return false;
    }
}