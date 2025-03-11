import UIAbility from '@ohos.app.ability.UIAbility';
import hilog from '@ohos.hilog';
import window from '@ohos.window';
import { AbilityConstant, common, Configuration, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

export default class EntryAbility extends UIAbility {
    onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
        hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
        // AppStorage.setOrCreate('currentColorMode', this.context.config.colorMode)
    }

    onDestroy() {
        hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
    }

    onConfigurationUpdate(newConfig: Configuration): void {
        // AppStorage.setOrCreate('currentColorMode', newConfig.colorMode);
        // hilog.info(0x0000, 'testTag', 'the newConfig.colorMode is %{public}s', JSON.stringify(AppStorage.get('currentColorMode')) ?? '');
    }

    onWindowStageCreate(windowStage: window.WindowStage) {
        // Main window is created, set main page for this ability
        hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

        windowStage.loadContent('pages/Index', (err, data) => {
            if (err.code) {
                hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
                return;
            }
            // 初始化数据库
            let context = getContext(this) as common.UIAbilityContext
            // ZDbUtil.initDatabase({ context: context })
            hilog.info(0x0000, 'testTag', 'Succeeded in loading the content. Data: %{public}s', JSON.stringify(data) ?? '');
        });

        windowStage.getMainWindow((err, windowClass) => {
            // 全屏
            windowClass.setWindowLayoutFullScreen(true)
                .then(() => {
                    console.info('已成功将窗口布局设置为全屏模式')
                })
                .catch((err: BusinessError) => {
                    console.error('无法将窗口布局设置为全屏模式 Cause:' + JSON.stringify(err))
                })

            // 获取上下遮挡区域
            let type = window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR //导航栏
            let avoidArea = windowClass.getWindowAvoidArea(type)
            let bottomRectHeight = avoidArea.bottomRect.height
            AppStorage.setOrCreate('bottomRectHeight', px2vp(bottomRectHeight))

            // 2. 获取导航栏避让遮挡的区域
            type = window.AvoidAreaType.TYPE_SYSTEM // 状态栏
            avoidArea = windowClass.getWindowAvoidArea(type)
            let topRectHeight = avoidArea.topRect.height
            AppStorage.setOrCreate('topRectHeight', px2vp(topRectHeight))

        })
    }

    onWindowStageDestroy() {
        // Main window is destroyed, release UI related resources
        hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
    }


    onForeground() {
        // Ability has brought to foreground
        hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
    }

    onBackground() {
        // Ability has back to background
        hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackground');
    }
}
