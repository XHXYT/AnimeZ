import { abilityAccessCtrl, PermissionRequestResult, Permissions } from "@kit.AbilityKit";
import { bundleManager } from '@kit.AbilityKit';
import { hilog } from "@kit.PerformanceAnalysisKit";

let TAG = 'PermissionManage';

export class PermissionManage {
  /** @description 权限列表数组 */
  private PERMISSION_ARRAY: Array<Permissions> = [
    "ohos.permission.DISTRIBUTED_DATASYNC",
  ];

  /** @description 检查权限
   * @returns true:已授权 false:未授权
   * */
  public async checkPermission(): Promise<boolean> {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const tokenID: number =
      bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
        .appInfo
        .accessTokenId
    const accessArray: abilityAccessCtrl.GrantStatus[] =
      this.PERMISSION_ARRAY.map((permission) => atManager.checkAccessTokenSync(tokenID, permission));

    return accessArray.every((status) => status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
  }

  /** @description 启动首次申请权限 */
  public async requestPermission(context: Context) {
    // 检查是否授权过
    if (await this.checkPermission()) {
      return
    }

    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    // 首次授权
    try {
      const result: PermissionRequestResult = await atManager.requestPermissionsFromUser(context, this.PERMISSION_ARRAY)
      const flag = result.authResults.every((status) => status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
    } catch (e) {
      const error = e as Error;
      hilog.error(0x0000, TAG, `requestPermission catch error: ${JSON.stringify(error)}`);
    }
  }

  /** @description 功能校验权限校验
   * @returns true:已授权 false:未授权
   * */
  public async functionCheckPermission(context: Context): Promise<boolean> {
    // 检查是否授权过
    if (await this.checkPermission()) {
      return true
    }

    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();

    // 拉起半模态授权逻辑
    atManager.requestPermissionOnSetting(context, this.PERMISSION_ARRAY)
      .then((result) => {
        hilog.info(0x0000, TAG, 'Permission request result: ' + JSON.stringify(result));
        const flag = result.every((status) => status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED)

        return flag
      })
      .catch((e: Error) => {
        hilog.error(0x0000, TAG, `requestPermissionOnSetting catch error: ${JSON.stringify(e)}`);
      })

    return false
  }
}

export const permissionManage = new PermissionManage()