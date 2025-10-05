
// 定义泛型约束
export type SettingGroupType = boolean | string | number

export interface Preference<T extends SettingGroupType> {
  key: string,
  type: 'switch' | 'radio' | 'menu'
  defaultValue: T
  menu: MenuItem[]
  onValueChange?: (key: string, value: T) => void
}

export interface MenuItem {
  view: ResourceStr
  value: string
}

export interface SettingItem<T extends SettingGroupType> {
  title: string
  info?: string | Resource
  icon?: string | Resource
  iconBlendColor?: ResourceColor
  onClick?: (item: SettingItem<T>, callback: () => void, event?: ClickEvent) => void
  preference?: Preference<T>
}

export interface SettingGroup<T extends SettingGroupType> {
  title?: string
  name?: string
  introduce?: string
  image?: Resource
  settings: SettingItem<T>[]
}