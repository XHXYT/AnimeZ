// QuickJsRuntime.ets
// QuickJS 引擎封装：@devzeng/quickjs（.ets 入口）经 QuickJsRegistry 注入供 ScriptProcessor(.ts) 调用。
// 每次执行新建独立上下文、用完即释放（QuickJS 轻量，微秒级创建开销），无跨线程共享。
// 注意：实测 evaluateScript 之间不共享顶层 var（module 作用域隔离），所有代码必须合并为单次求值。
import { JSContext, JSValue } from '@devzeng/quickjs'
import { registerQuickJs } from './QuickJsRegistry'
import Logger from '../utils/Logger'

// 工具函数定义：与旧版 new Function 沙箱同签名（utils.string/number/array/condition），
// 保证既有源配置的后处理脚本语义不变；QuickJS 原生提供 Math/JSON/RegExp/encodeURIComponent 等
const UTILS_DEF: string =
  'var __utils={string:{extract:function(t,p,g){g=g||0;var m=String(t).match(new RegExp(p));return m?m[g]:\'\'' +
  '},extractAll:function(t,p){var r=[],m,re=new RegExp(p,\'g\');while((m=re.exec(String(t)))!==null){r.push(m)}return r' +
  '},replaceAll:function(t,s,r){return String(t).replace(new RegExp(s,\'g\'),r)' +
  '},between:function(t,a,b){var s=String(t).indexOf(a);if(s===-1)return\'\'' +
  ';var e=s+a.length;var f=String(t).indexOf(b,e);return f===-1?String(t).substring(e):String(t).substring(e,f)}}' +
  ',number:{format:function(n,d){d=d||2;return Number(Number(n).toFixed(d))},parse:function(t){return parseFloat(t)||0' +
  '},isInt:function(n){return Number.isInteger(n)},isFloat:function(n){return !Number.isInteger(n)&&!isNaN(n)}}' +
  ',array:{first:function(a){return a[0]},last:function(a){return a[a.length-1]},unique:function(a){return Array.from(new Set(a))}' +
  ',chunk:function(a,s){var r=[];for(var i=0;i<a.length;i+=s){r.push(a.slice(i,i+s))}return r}}' +
  ',condition:{if:function(c,t,f){return c?t:f}}};' +
  'if(typeof console===\'undefined\'){var console={log:function(){},error:function(){},warn:function(){}};}'

/** 应用启动时调用（EntryAbility.onCreate），把 QuickJS 执行封装注入注册表供 .ts 调用方使用 */
export function initQuickJsRuntime(): void {
  registerQuickJs({
    evalScript: (script: string, inputJson: string, contextJson: string): string | null => {
      let ctx: JSContext | null = null
      try {
        ctx = new JSContext()
        // 单次求值：工具定义 + 入参注入（result/context/utils）+ 严格模式 + 异常兜底 + 返回值统一字符串化
        const full: string = UTILS_DEF +
          'var __r=(function(result, context, utils){"use strict";try{' + script +
          '}catch(e){return null;}})(' + inputJson + ',' + contextJson + ',__utils);' +
          '(__r===null||__r===undefined)?null:((typeof __r===\'object\')?JSON.stringify(__r):String(__r));'
        const out: JSValue = ctx.evaluateScript(full, 'ScriptProcessor')
        if (out.isException) {
          const ex: JSValue | null = ctx.exception
          Logger.e('tips', `QuickJS 脚本异常: ${ex !== null ? ex.errorMessage : 'unknown'} @ ${ex !== null ? ex.errorStack : ''}`)
          return null
        }
        if (out.isNull || out.isUndefined) {
          return null
        }
        return out.toString()
      } catch (error) {
        Logger.e('tips', `QuickJS 执行失败: ${error.message}`)
        return null
      } finally {
        if (ctx !== null) {
          ctx.release()
        }
      }
    }
  })
  Logger.d('tips', 'QuickJS 运行时已注册（ScriptProcessor 脚本后处理走 QuickJS 引擎）')
}
