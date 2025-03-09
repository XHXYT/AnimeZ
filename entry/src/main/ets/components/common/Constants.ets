
// 定义泛型约束
export type SettingGroupType = boolean | string | number

export interface Preference<T extends SettingGroupType> {
  key: string,
  type: 'switch' | 'radio' | 'menu'
  defaultValue: T
  values: string[]
  onValueChange?: (key: string, value: T) => void
}

interface NormalPreference {
  info: string,
  onClick?: (event?: ClickEvent) => void
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