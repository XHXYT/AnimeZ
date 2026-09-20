export class ExpressionEngine {
  // 支持的表达式类型
  private static operators = {
    // 算术运算
    '+': (a: number, b: number) => a + b,
    '-': (a: number, b: number) => a - b,
    '*': (a: number, b: number) => a * b,
    '/': (a: number, b: number) => a / b,
    '%': (a: number, b: number) => a % b,

    // 比较运算
    '==': (a: any, b: any) => a === b,
    '!=': (a: any, b: any) => a !== b,
    '>': (a: any, b: any) => a > b,
    '<': (a: any, b: any) => a < b,
    '>=': (a: any, b: any) => a >= b,
    '<=': (a: any, b: any) => a <= b,

    // 逻辑运算
    '&&': (a: any, b: any) => a && b,
    '||': (a: any, b: any) => a || b,
    '!': (a: any) => !a
  };

  static evaluate(expression: string, context: any = {}): any {
    try {
      // 预处理表达式
      const processedExpr = this.preprocessExpression(expression, context);

      // 简单的表达式求值
      return this.evaluateSimple(processedExpr);
    } catch (error) {
      console.error('ExpressionEngine求值失败:', error);
      return null;
    }
  }

  private static preprocessExpression(expression: string, context: any): string {
    // 替换变量
    return expression.replace(/\b(\w+)\b/g, (match) => {
      if (match === 'result') return JSON.stringify(context.result || '');
      if (match === 'context') return JSON.stringify(context);
      if (context[match] !== undefined) return JSON.stringify(context[match]);
      return match;
    });
  }

  private static evaluateSimple(expression: string): any {
    // 处理字符串字面量
    if (expression.startsWith('"') && expression.endsWith('"')) {
      return expression.slice(1, -1);
    }

    // 处理数字
    if (/^\d+(\.\d+)?$/.test(expression)) {
      return parseFloat(expression);
    }

    // 处理布尔值
    if (expression === 'true') return true;
    if (expression === 'false') return false;

    // 处理函数调用
    const functionMatch = expression.match(/^(\w+)\((.*)\)$/);
    if (functionMatch) {
      const [, funcName, argsStr] = functionMatch;
      const args = argsStr ? argsStr.split(',').map(arg => this.evaluateSimple(arg.trim())) : [];
      return this.callFunction(funcName, args);
    }

    // 处理运算符
    for (const op of Object.keys(this.operators)) {
      if (expression.includes(op)) {
        const parts = expression.split(op);
        if (parts.length === 2) {
          const left = this.evaluateSimple(parts[0].trim());
          const right = this.evaluateSimple(parts[1].trim());
          return (this.operators as any)[op](left, right);
        }
      }
    }

    return expression;
  }

  private static callFunction(funcName: string, args: any[]): any {
    const utils = {
      // 字符串函数
      extract: (text: string, pattern: string, group = 0) => {
        const match = text.match(new RegExp(pattern));
        return match ? match[group] : '';
      },
      replace: (text: string, search: string, replace: string) =>
      text.replace(new RegExp(search, 'g'), replace),

      // 数学函数
      round: (num: number) => Math.round(num),
      floor: (num: number) => Math.floor(num),
      ceil: (num: number) => Math.ceil(num),

      // 条件函数
      if: (condition: any, trueValue: any, falseValue: any) =>
      condition ? trueValue : falseValue
    };

    return (utils as any)[funcName]?.(...args);
  }
}
