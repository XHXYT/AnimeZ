// ScriptProcessor.ts
import Logger from '../utils/Logger';
import { StringProcessor } from './StringProcessor';
import { ProcessConfig } from './DataSourceConfig';

export class ScriptProcessor {
  /**
   * 执行通用脚本/表达式
   */
  static async execute<T = any>(input: any, config: ProcessConfig): Promise<T> {
    if (!config) return input;

    try {
      switch (config.type) {
        case 'script':
          return await this.executeScript(input, config);
        case 'expression':
          return await this.executeExpression(input, config);
        case 'string':
          return await this.executeStringProcess(input, config);
        case 'condition':
          return await this.executeCondition(input, config);
        case 'transform':
          return await this.executeTransform(input, config);
        case 'pipeline':
          return await this.executePipeline(input, config);
        default:
          return input;
      }
    } catch (error) {
      Logger.e('tips', `ScriptProcessor 执行失败: ${error.message}`);
      return input;
    }
  }

  /**
   * 执行安全脚本
   */
  private static async executeScript<T>(input: any, config: ProcessConfig): Promise<T> {
    try {
      // 创建受限的执行环境
      const sandbox = this.createSandbox(input, config.context || {});

      // 构造安全的函数
      const func = new Function(
        ...Object.keys(sandbox),
        `
        'use strict';
        try {
          ${config.script}
        } catch(e) {
          console.error('脚本执行错误:', e.message);
          return null;
        }
        `
      );

      // 执行函数
      const result = func(...Object.values(sandbox));
      return result as T;
    } catch (error) {
      Logger.e('tips', `ScriptProcessor Script执行失败: ${error.message}`);
      return input as T;
    }
  }

  /**
   * 执行表达式 - 修复版本
   */
  private static async executeExpression<T>(input: any, config: ProcessConfig): Promise<T> {
    try {
      const result = this.evaluateExpression(config.expression || 'result', { result: input });
      return result as T;
    } catch (error) {
      Logger.e('tips', `ScriptProcessor Expression执行失败: ${error.message}`);
      return input as T; // 直接返回，因为外层已经用await调用
    }
  }

  /**
   * 执行字符串处理
   */
  private static async executeStringProcess<T>(input: string, config: ProcessConfig): Promise<T> {
    if (config.stringProcess) {
      return await StringProcessor.process(input, config.stringProcess) as T;
    }
    return input as T;
  }

  /**
   * 执行条件处理
   */
  private static async executeCondition<T>(input: any, config: ProcessConfig): Promise<T> {
    try {
      const condition = this.evaluateExpression(config.condition || 'false', { result: input });
      const result = condition ? config.trueValue : config.falseValue;
      return result as T;
    } catch (error) {
      Logger.e('tips', `ScriptProcessor Condition执行失败: ${error.message}`);
      return input as T;
    }
  }

  /**
   * 执行数据转换
   */
  private static async executeTransform<T>(input: any, config: ProcessConfig): Promise<T> {
    if (config.transform?.map) {
      const result = config.transform.map[input];
      return (result !== undefined ? result : input) as T;
    }

    if (config.transform?.template) {
      // 简单的模板替换
      let result = config.transform.template;
      result = result.replace(/\$\{input\}/g, String(input));
      result = result.replace(/\$\{(\w+)\}/g, (match, key) => {
        return config.transform?.map?.[key] || match;
      });
      return result as T;
    }

    return input as T;
  }

  /**
   * 执行管道处理
   */
  private static async executePipeline<T>(input: any, config: ProcessConfig): Promise<T> {
    let result = input;
    if (config.steps) {
      for (const step of config.steps) {
        result = await this.execute(result, step);
      }
    }
    return result as T;
  }

  /**
   * 创建安全沙箱环境
   */
  private static createSandbox(input: any, context: any) {
    return {
      result: input,
      context,

      // 受限的全局对象
      Math: {
        abs: Math.abs,
        round: Math.round,
        floor: Math.floor,
        ceil: Math.ceil,
        max: Math.max,
        min: Math.min,
        random: Math.random,
        pow: Math.pow,
        sqrt: Math.sqrt
      },

      // 工具函数
      utils: {
        // 字符串工具
        string: {
          extract: (text: string, pattern: string, group = 0) => {
            const match = text.match(new RegExp(pattern));
            return match ? match[group] : '';
          },
          extractAll: (text: string, pattern: string) => {
            const regex = new RegExp(pattern, 'g');
            const matches = [];
            let match;
            while ((match = regex.exec(text)) !== null) {
              matches.push(match);
            }
            return matches;
          },
          replaceAll: (text: string, search: string, replace: string) =>
          text.replace(new RegExp(search, 'g'), replace),
          between: (text: string, start: string, end: string) => {
            const startIndex = text.indexOf(start);
            if (startIndex === -1) return '';
            const startEnd = startIndex + start.length;
            const endIndex = text.indexOf(end, startEnd);
            return endIndex === -1 ? text.substring(startEnd) : text.substring(startEnd, endIndex);
          }
        },

        // 数值工具
        number: {
          format: (num: number, decimals = 2) => Number(num.toFixed(decimals)),
          parse: (text: string) => parseFloat(text) || 0,
          isInt: (num: number) => Number.isInteger(num),
          isFloat: (num: number) => !Number.isInteger(num) && !isNaN(num)
        },

        // 数组工具
        array: {
          first: (arr: any[]) => arr[0],
          last: (arr: any[]) => arr[arr.length - 1],
          unique: (arr: any[]) => [...new Set(arr)],
          chunk: (arr: any[], size: number) => {
            const chunks = [];
            for (let i = 0; i < arr.length; i += size) {
              chunks.push(arr.slice(i, i + size));
            }
            return chunks;
          }
        },

        // 条件工具
        condition: {
          if: (condition: any, trueValue: any, falseValue: any) =>
          condition ? trueValue : falseValue,
          switch: (value: any, cases: Record<string, any>, defaultValue: any) =>
          cases[value] !== undefined ? cases[value] : defaultValue
        }
      }
    };
  }

  /**
   * 简单表达式求值
   */
  private static evaluateExpression(expression: string, context: any): any {
    try {
      // 替换变量
      let processedExpr = expression.replace(/\b(\w+)\b/g, (match) => {
        if (match === 'result') return JSON.stringify(context.result || '');
        if (match === 'context') return JSON.stringify(context);
        if (context[match] !== undefined) return JSON.stringify(context[match]);
        return match;
      });

      // 安全的表达式求值
      if (processedExpr.match(/^[\d+\-*/().\s]+$/)) {
        return Function(`"use strict"; return (${processedExpr})`)();
      }

      // 函数调用
      const functionMatch = processedExpr.match(/^(\w+)\((.*)\)$/);
      if (functionMatch) {
        const [, funcName, argsStr] = functionMatch;
        const args = argsStr ? argsStr.split(',').map(arg =>
        this.evaluateExpression(arg.trim(), context)
        ) : [];

        return this.callFunction(funcName, args, context);
      }

      return processedExpr;
    } catch (error) {
      Logger.e('tips', `ScriptProcessor Expression求值失败: ${error.message}`);
      return null;
    }
  }

  /**
   * 调用安全函数
   */
  private static callFunction(funcName: string, args: any[], context: any): any {
    const utils = this.createSandbox(context.input, context).utils;

    // 支持的函数映射
    const functionMap: Record<string, Function> = {
      // 字符串函数
      extract: utils.string.extract,
      replaceAll: utils.string.replaceAll,
      between: utils.string.between,

      // 数学函数
      round: Math.round,
      floor: Math.floor,
      ceil: Math.ceil,
      parseFloat: parseFloat,
      parseInt: parseInt,

      // 条件函数
      if: utils.condition.if
    };
    return functionMap[funcName]?.(...args);
  }

}
