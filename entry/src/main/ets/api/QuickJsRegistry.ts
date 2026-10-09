// QuickJsRegistry.ts
// QuickJS 引擎注册表：@devzeng/quickjs 库入口是 .ets，而 ScriptProcessor 等 .ts 调用方
// 不能 import .ets —— 由 QuickJsRuntime.ets 在应用启动时注入实现。

/** QuickJS 脚本执行封装（由 QuickJsRuntime.ets 提供） */
export interface QuickJsFns {
  /**
   * 在全新 QuickJS 上下文中执行脚本（用完即释放，线程安全）
   * @param script JS 代码，以 result/context/utils 为入参（与旧版沙箱同签名），return 返回结果
   * @param inputJson result 入参的 JSON 字面量（JSON.stringify 产物，可直接嵌入 JS）
   * @param contextJson context 入参的 JSON 字面量
   * @returns 脚本返回值的字符串形式（对象/数组 JSON 序列化）；脚本异常或返回 null/undefined 时为 null
   */
  evalScript: (script: string, inputJson: string, contextJson: string) => string | null;
}

let quickJsFns: QuickJsFns | null = null;

/** 由 QuickJsRuntime.ets 在应用启动时调用（EntryAbility.onCreate -> initQuickJsRuntime） */
export function registerQuickJs(fns: QuickJsFns): void {
  quickJsFns = fns;
}

/** 获取 QuickJS 执行封装；未注册时返回 null，调用方走旧版 new Function 沙箱兜底 */
export function getQuickJsFns(): QuickJsFns | null {
  return quickJsFns;
}
