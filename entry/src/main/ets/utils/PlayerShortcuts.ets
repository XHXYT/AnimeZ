import { KeyCode } from '@kit.InputKit'
import { appSettings } from '../entryability/Settings'
import Logger from './Logger'

/**
 * 快捷键定义（action 唯一标识 / 显示名 / 默认键值 / 是否按住生效）
 */
export class ShortcutDef {
  action: string = ''
  label: string = ''
  defaultKeyCode: number = 0
  /** 按住生效：DOWN 触发开始、UP 触发结束 */
  hold: boolean = false

  constructor(action: string, label: string, defaultKeyCode: number, hold: boolean) {
    this.action = action
    this.label = label
    this.defaultKeyCode = defaultKeyCode
    this.hold = hold
  }
}

/** 全部快捷键动作及默认绑定 */
export const SHORTCUT_DEFS: ShortcutDef[] = [
  new ShortcutDef('play_pause', '播放 / 暂停', KeyCode.KEYCODE_SPACE, false),
  new ShortcutDef('seek_forward', '快进', KeyCode.KEYCODE_DPAD_RIGHT, false),
  new ShortcutDef('seek_rewind', '快退', KeyCode.KEYCODE_DPAD_LEFT, false),
  new ShortcutDef('rewind_hold', '按住快退', KeyCode.KEYCODE_J, true),
  new ShortcutDef('speed_boost', '按住倍速', KeyCode.KEYCODE_L, true),
  new ShortcutDef('volume_up', '音量增加', KeyCode.KEYCODE_DPAD_UP, false),
  new ShortcutDef('volume_down', '音量减小', KeyCode.KEYCODE_DPAD_DOWN, false),
  new ShortcutDef('brightness_up', '亮度增加', KeyCode.KEYCODE_W, false),
  new ShortcutDef('brightness_down', '亮度减小', KeyCode.KEYCODE_S, false),
  new ShortcutDef('toggle_controller', '显示/隐藏控制层', KeyCode.KEYCODE_C, false),
  new ShortcutDef('toggle_fullscreen', '进入/退出全屏', KeyCode.KEYCODE_F, false)
]

const LETTER_KEYS: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'

/**
 * 播放器键盘快捷键存取工具：
 * 覆盖项持久化在 appSettings.player_shortcuts（JSON Record<string, number>，空串表示全部默认），
 * 解析结果按原始字符串缓存，仅在配置变化时重新解析。
 */
export class PlayerShortcuts {

  private static cachedRaw: string = '__never__'
  private static overrides: Record<string, number> = {}

  /** 解析覆盖配置（带缓存：player_shortcuts 未变化时直接复用） */
  private static ensureOverrides(): void {
    const raw: string = appSettings.player_shortcuts
    if (raw === PlayerShortcuts.cachedRaw) {
      return
    }
    PlayerShortcuts.cachedRaw = raw
    const parsed: Record<string, number> = {}
    if (raw.length > 0) {
      try {
        const json: Record<string, Object> = JSON.parse(raw)
        // 仅拷贝已定义的 action，忽略非法/未知字段
        for (const def of SHORTCUT_DEFS) {
          const numVal: number = Number(json[def.action])
          if (!Number.isNaN(numVal) && numVal > 0) {
            parsed[def.action] = numVal
          }
        }
      } catch (e) {
        Logger.e('fail', '解析播放器快捷键配置', e)
      }
    }
    PlayerShortcuts.overrides = parsed
  }

  /** 查询 action 当前绑定的键值（无覆盖时返回默认值，未知 action 返回 -1） */
  public static getShortcutKeyCode(action: string): number {
    PlayerShortcuts.ensureOverrides()
    const override: number = PlayerShortcuts.overrides[action]
    if (override !== undefined && override > 0) {
      return override
    }
    const def: ShortcutDef | undefined =
      SHORTCUT_DEFS.find((d: ShortcutDef): boolean => d.action === action)
    return def ? def.defaultKeyCode : -1
  }

  /** 查询 action 当前绑定的键名（用于设置页与帮助面板展示） */
  public static getShortcutLabel(action: string): string {
    return keyCodeToLabel(PlayerShortcuts.getShortcutKeyCode(action))
  }

  /**
   * 设置/清除 action 绑定的键值（keyCode <= 0 表示恢复该 action 默认），
   * 重建整个覆盖表写回，保证存储内容只含合法 action。
   */
  public static setShortcutKeyCode(action: string, keyCode: number): void {
    PlayerShortcuts.ensureOverrides()
    const next: Record<string, number> = {}
    for (const def of SHORTCUT_DEFS) {
      if (def.action === action) {
        continue
      }
      const cur: number = PlayerShortcuts.overrides[def.action]
      if (cur !== undefined && cur > 0) {
        next[def.action] = cur
      }
    }
    if (keyCode > 0) {
      next[action] = keyCode
    }
    appSettings.player_shortcuts = JSON.stringify(next)
  }

  /** 恢复全部快捷键默认绑定 */
  public static resetShortcuts(): void {
    appSettings.player_shortcuts = ''
  }
}

/** 键值转显示名（空格/方向键/ESC/字母/F1-F12/音量键） */
export function keyCodeToLabel(keyCode: number): string {
  if (keyCode === KeyCode.KEYCODE_SPACE) {
    return '空格'
  }
  if (keyCode === KeyCode.KEYCODE_ENTER) {
    return 'Enter'
  }
  if (keyCode === KeyCode.KEYCODE_ESCAPE) {
    return 'ESC'
  }
  if (keyCode === KeyCode.KEYCODE_DPAD_UP) {
    return '↑'
  }
  if (keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
    return '↓'
  }
  if (keyCode === KeyCode.KEYCODE_DPAD_LEFT) {
    return '←'
  }
  if (keyCode === KeyCode.KEYCODE_DPAD_RIGHT) {
    return '→'
  }
  if (keyCode === KeyCode.KEYCODE_VOLUME_UP) {
    return '音量+'
  }
  if (keyCode === KeyCode.KEYCODE_VOLUME_DOWN) {
    return '音量-'
  }
  if (keyCode >= KeyCode.KEYCODE_A && keyCode <= KeyCode.KEYCODE_Z) {
    return LETTER_KEYS.charAt(keyCode - KeyCode.KEYCODE_A)
  }
  if (keyCode >= KeyCode.KEYCODE_F1 && keyCode <= KeyCode.KEYCODE_F12) {
    return `F${keyCode - KeyCode.KEYCODE_F1 + 1}`
  }
  return `键码 ${keyCode}`
}

/** 按键冲突检测：返回已占用该键值的其它动作，无冲突返回 undefined */
export function findShortcutConflict(keyCode: number, excludeAction: string): ShortcutDef | undefined {
  for (const def of SHORTCUT_DEFS) {
    if (def.action === excludeAction) {
      continue
    }
    if (PlayerShortcuts.getShortcutKeyCode(def.action) === keyCode) {
      return def
    }
  }
  return undefined
}

/** 按键反查 action（播放器键盘事件分发用），未绑定返回空串 */
export function findActionByKeyCode(keyCode: number): string {
  for (const def of SHORTCUT_DEFS) {
    if (PlayerShortcuts.getShortcutKeyCode(def.action) === keyCode) {
      return def.action
    }
  }
  return ''
}
