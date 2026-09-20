
import Logger from '../utils/Logger';
import { StringProcessConfig } from './DataSourceConfig';

export class StringProcessor {
  /**
   * 处理字符串
   */
  static async process(input: string, config: StringProcessConfig): Promise<string> {
    if (!input || !config) return input;

    try {
      switch (config.type) {
        case 'regex':
          return this.processRegex(input, config);
        case 'replace':
          return this.processReplace(input, config);
        case 'substring':
          return this.processSubstring(input, config);
        case 'split':
          return this.processSplit(input, config);
        default:
          Logger.w('StringProcessor', `Unknown process type: ${config.type}`);
          return input;
      }
    } catch (error) {
      Logger.e('tips', `Process failed: ${error.message}`);
      return input;
    }
  }

  private static processRegex(input: string, config: StringProcessConfig): string {
    const regex = new RegExp(config.pattern || '', config.flags || 'g');
    const match = input.match(regex);
    return match && config.group !== undefined ? match[config.group] || '' : match?.[0] || '';
  }

  private static processReplace(input: string, config: StringProcessConfig): string {
    const search = new RegExp(config.search || '', config.flags || 'g');
    return input.replace(search, config.replace || '');
  }

  private static processSubstring(input: string, config: StringProcessConfig): string {
    const start = typeof config.start === 'string'
      ? input.indexOf(config.start) + config.start.length
      : config.start || 0;
    const end = typeof config.end === 'string'
      ? input.indexOf(config.end, start)
      : config.end;
    return input.substring(start, end);
  }

  private static processSplit(input: string, config: StringProcessConfig): string {
    const parts = input.split(config.delimiter || '');
    return config.index !== undefined ? parts[config.index] || '' : parts[0];
  }
}
