export class SafeScriptExecutor {
  private static allowedGlobals = {
    // 数学函数
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

    // 字符串方法
    String: {
      prototype: {
        replace: String.prototype.replace,
        match: String.prototype.match,
        split: String.prototype.split,
        substring: String.prototype.substring,
        toLowerCase: String.prototype.toLowerCase,
        toUpperCase: String.prototype.toUpperCase,
        trim: String.prototype.trim
      }
    },

    // 数组方法
    Array: {
      prototype: {
        map: Array.prototype.map,
        filter: Array.prototype.filter,
        find: Array.prototype.find,
        some: Array.prototype.some,
        every: Array.prototype.every,
        join: Array.prototype.join
      }
    },

    // 日期方法
    Date: {
      now: Date.now,
      parse: Date.parse
    },

    // JSON方法
    JSON: {
      parse: JSON.parse,
      stringify: JSON.stringify
    }
  };

  static async execute<T = any>(script: string, input: any = '', context: any = {}): Promise<T> {
    try {
      // 创建受限的执行环境
      const sandbox = this.createSandbox(input, context);

      // 构造安全的函数
      const func = new Function(
        ...Object.keys(sandbox),
        `
        'use strict';
        try {
          ${script}
        } catch(e) {
          console.error('脚本执行错误:', e.message);
          return null;
        }
        `
      );

      // 执行函数
      return func(...Object.values(sandbox));
    } catch (error) {
      console.error('SafeScriptExecutor执行失败:', error);
      return null as T;
    }
  }

  private static createSandbox(input: any, context: any) {
    return {
      result: input,
      context,
      // 提供受限的全局对象
      Math: this.allowedGlobals.Math,
      String: this.allowedGlobals.String,
      Array: this.allowedGlobals.Array,
      Date: this.allowedGlobals.Date,
      JSON: this.allowedGlobals.JSON,

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
}
