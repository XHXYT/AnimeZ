import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import Logger from './Logger';

/**
 * 网络类型检测工具
 */
export function isUnmeteredNetwork(): boolean {
  try {
    const netHandle = connection.getDefaultNetSync();
    if (!netHandle || netHandle.netId === 0) {
      // 无默认网络：不拦截自动播放，由播放流程自行报错
      return true;
    }
    const capabilities = connection.getNetCapabilitiesSync(netHandle);
    if (!capabilities) {
      return true;
    }
    const bearers = capabilities.bearerTypes;
    return bearers.includes(connection.NetBearType.BEARER_WIFI)
      || bearers.includes(connection.NetBearType.BEARER_ETHERNET);
  } catch (error) {
    const err = error as BusinessError;
    Logger.e('fail', `isUnmeteredNetwork 网络类型检测 code=${err.code}`, err);
    return true;
  }
}
