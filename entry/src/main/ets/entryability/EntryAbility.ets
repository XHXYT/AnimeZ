import UIAbility from '@ohos.app.ability.UIAbility';
import hilog from '@ohos.hilog';
import window from '@ohos.window';
import { AbilityConstant, bundleManager, Configuration, Want, wantConstant } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { dataSourceManager } from '../api/DataSourceManager';
import { AppSettings } from './Settings';
import { ToastUtil } from '../utils/ToastUtils';
import { RedPlayerConfigBuilder, RedPlayerInitManager, RedPlayerPreload } from '@rte-xhs/redplayer';
import { videoHistoryInfoDB } from '../database/VideoHistoryInfoDB';
import { permissionManage } from '../utils/PermissionManage';
import { appContinue, IAppContinue } from '../utils/AppContinue';


export default class EntryAbility extends UIAbility {
    private storage: LocalStorage = new LocalStorage();
    private uiContext?: UIContext;
    // 设备断点获取
    private onWindowSizeChange: (windowSize: window.Size) => void = (windowSize: window.Size) => {
        let widthBp: WidthBreakpoint = this.uiContext!.getWindowWidthBreakpoint();
        AppStorage.setOrCreate('currentWidthBreakpoint', widthBp);
        console.log(`断点测试 widthBp: ${widthBp}`)
    };

    async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
        // 关闭应用接续 -> 在特定的页面才打开
        this.context.setMissionContinueState(AbilityConstant.ContinueState.INACTIVE, (result) => {
            console.log(`setMissionContinueState: ${JSON.stringify(result)}`)
        })

        hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
        // 初始化 源管理器、数据库 上下文
        await dataSourceManager.init(this.context)
        await videoHistoryInfoDB.init(this.context)
        // 检查设备形式
        AppStorage.setOrCreate<string>('DeviceProductModel', deviceInfo.productModel)
        // 构建RedPlayer
        const redPlayerConfigBuilder = new RedPlayerConfigBuilder()
        // redPlayerConfigBuilder.cachePath = 'your player cache path'
        // redPlayerConfigBuilder.logger?.d('your custom logger')
        // 初始化 RedPlayer
        RedPlayerInitManager.initPlayer(redPlayerConfigBuilder)
        // Init RedPlayer preload component
        // RedPlayerPreload.globalInit('your preload cache path', 20, 4, 0)

        this.getContinueData(want, launchParam);
    }

    onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
        this.getContinueData(want, launchParam);
    }

    private getContinueData(want: Want, launchParam: AbilityConstant.LaunchParam) {
        if (launchParam.launchReason !== AbilityConstant.LaunchReason.CONTINUATION) {
            return;
        }

        if (want.parameters != undefined) {
            const data: IAppContinue = want.parameters.data as IAppContinue
            hilog.info(0x0000, 'AppContinue', 'EntryAbility - %{public}s', JSON.stringify(data))
            if (data.currentPage !== '' && typeof data.currentPageParams === 'object') {
                // 保存页面恢复所需的数据
                appContinue.jumpVideoDetail(data.currentPage, data.currentPageParams)
                if (launchParam) {
                    this.context.restoreWindowStage(this.storage);
                }
            }
        }
    }

    onDestroy() {
        hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
    }

    onConfigurationUpdate(newConfig: Configuration): void {
    }

    onWindowStageCreate(windowStage: window.WindowStage) {
        // Main window is created, set main page for this ability
        hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

        this.stageLoadPage(windowStage);
    }

    private stageLoadPage(windowStage: window.WindowStage) {
        windowStage.loadContent('pages/Index', async (err, data) => {
            if (err.code) {
                hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{public}s',
                    JSON.stringify(err) ?? '');
                return;
            }
            // 初始化应用设置
            await AppSettings.init();
            hilog.info(0x0000, 'testTag', 'Succeeded in loading the content. Data: %{public}s',
                JSON.stringify(data) ?? '');
        });

        windowStage.getMainWindow(async (err, data) => {
            // 全屏
            data.setWindowLayoutFullScreen(true)
                .then(() => {
                    console.info('已成功将窗口布局设置为全屏模式');
                })
                .catch((err: BusinessError) => {
                    console.error('无法将窗口布局设置为全屏模式 Cause:' + JSON.stringify(err));
                });

            try {
                const UIContext = data.getUIContext();
                this.uiContext = UIContext;
                AppStorage.setOrCreate('UIContext', UIContext);
                AppStorage.setOrCreate<window.Window>('WindowClass', data);
                // 初始化通知
                ToastUtil.initContext(UIContext);
                // 设备宽度断点获取
                const widthBp: WidthBreakpoint = UIContext.getWindowWidthBreakpoint();
                AppStorage.setOrCreate('currentWidthBreakpoint', widthBp);
                data.on('windowSizeChange', this.onWindowSizeChange);
                // 初始化窗口
                this.intRectWindow(windowStage);

                // 初始化权限
                permissionManage.requestPermission(this.uiContext.getHostContext() as Context);
            } catch (error) {
                console.error(`UI上下文获取失败，code: ${error.code} message: ${error.messsage}`);
            }

        });
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

    /** @description 应用接续迁移准备过程的生命周期 -> 保存数据 */
    onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult | Promise<AbilityConstant.OnContinueResult> {
        let versionDst = wantParam.version; // 获取迁移对端应用的版本号

        const bundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
        let versionSrc: number = bundleInfo?.versionCode ?? 0; // 获取迁移源端即本端应用的版本号

        if (versionDst > versionSrc) { // 兼容性校验
            // 兼容性校验不满足
            return AbilityConstant.OnContinueResult.MISMATCH; //版本不匹配，拒绝迁移
        }

        let continueInput = appContinue.getCurrentVideoPageDetail();
        if (typeof continueInput === "object") {
            // 将要迁移的数据保存在wantParam的自定义字段（如：data）中;
            wantParam["data"] = continueInput;
            // 取消 页面栈 自动迁移
            wantParam[wantConstant.Params.SUPPORT_CONTINUE_PAGE_STACK_KEY] = false;
            // 按需退出
            // wantParam[wantConstant.Params.SUPPORT_CONTINUE_SOURCE_EXIT_KEY] = false;
        }

        return AbilityConstant.OnContinueResult.AGREE;
    }

    /** @description 应用接续恢复窗口的生命周期 -> 恢复数据 */
    onWindowStageRestore(windowStage: window.WindowStage) {
        // 恢复页面 -> 使用 navigation 路由需通过 want 参数自行恢复
        this.stageLoadPage(windowStage);
    }

    private intRectWindow(windowStage: window.WindowStage) {
        // 获取应用主窗口
        try {
            const windowClass: window.Window = windowStage.getMainWindowSync()
            // 设置窗口全屏
            windowClass.setWindowLayoutFullScreen(true).then(() => {
                console.info('Succeeded in setting the window layout to full-screen mode.');
            }).catch((err: BusinessError) => {
                console.error('Failed to set the window layout to full-screen mode. Cause:' + JSON.stringify(err));
            });

            // 缓存window窗口对象
            AppStorage.setOrCreate('WindowClass', windowClass)
            console.info('Succeeded in 保存窗口对象.');

            // 获取布局避让遮挡的区域
            // 获取导航栏遮挡区域
            const bottomType = window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR
            try {
                const avoidArea = windowClass.getWindowAvoidArea(bottomType)
                const bottomRectHeight = avoidArea.bottomRect.height
                AppStorage.setOrCreate('bottomRectHeight', px2vp(bottomRectHeight))
                hilog.info(0x0000, 'EntryAbility', '导航栏初始避让高度 Top：%{public}d Bottom: %{public}i', bottomRectHeight);
            } catch (error) {
                console.error(`导航栏避让获取失败，code: ${error.code} message: ${error.messsage}`)
            }

            // 获取状态栏避让遮挡的区域
            const topType = window.AvoidAreaType.TYPE_SYSTEM // 状态栏
            try {
                const topAvoidArea = windowClass.getWindowAvoidArea(topType)
                const topRectHeight = topAvoidArea.topRect.height
                AppStorage.setOrCreate('topRectHeight', px2vp(topRectHeight))
                hilog.info(0x0000, 'EntryAbility', '状态栏初始避让高度 Top：%{public}d Bottom: %{public}i', topRectHeight)
            } catch (error) {
                console.error(`状态栏避让获取失败，code: ${error.code} message: ${error.messsage}`)
            }

            // 注册监听函数，动态获取避让区域数据
            windowClass.on('avoidAreaChange', (data) => {
                let topRectActiveHeight = 0
                let bottomRectActiveHeight = 0
                if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
                    topRectActiveHeight = data.area.topRect.height;
                    AppStorage.setOrCreate('topRectHeight', this.uiContext?.px2vp(topRectActiveHeight));
                } else if (data.type == window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
                    bottomRectActiveHeight = this.uiContext?.px2vp(data.area.bottomRect.height)!;
                    AppStorage.setOrCreate('bottomRectHeight', bottomRectActiveHeight);
                }
                hilog.info(0x0000, 'EntryAbility', '动态避让高度 Top：%{public}d Bottom: %{public}i', topRectActiveHeight, bottomRectActiveHeight);
            });

            // 应用窗口初始高度和宽度
            try {
                const properties = windowClass.getWindowProperties()
                const rect = properties.windowRect
                let WindowHeight = this.uiContext?.px2vp(rect.height)
                let WindowWidth = this.uiContext?.px2vp(rect.width)
                hilog.info(0x0000, 'WindowLog', '窗口高度：%{public}d vp 宽度：%{public}i vp', rect.height, rect.width)
                AppStorage.setOrCreate('windowHeight', WindowHeight)
                AppStorage.setOrCreate('windowWidth', WindowWidth)
                // 监听窗口大小变化
                try {
                    windowClass.on('windowSizeChange', async (data) => {
                        console.info('#WindowChange Succeeded in enabling the listener for window size changes. Data: ' +
                        JSON.stringify(data))
                        WindowWidth = this.uiContext?.px2vp(data.width)!
                        WindowHeight = this.uiContext?.px2vp(data.height)!
                        AppStorage.setOrCreate('windowWidth', WindowWidth)
                        AppStorage.setOrCreate('windowHeight', WindowHeight) // 980px 约等于 512vp
                        hilog.info(0x0000, 'WindowLog', '窗口高度：%{public}d vp 宽度：%{public}i vp', WindowHeight, WindowWidth)
                        // 动态监听高度断点
                        this.onHeightBpChange(WindowHeight, WindowWidth)
                    })
                } catch (exception) {
                    console.error(`#EntryAbility Failed to enable the listener for window size changes. Cause code: ${exception.code}, message: ${exception.message}`)
                }
            } catch (error) {
                console.error(`窗口大小获取失败，code: ${error.code} message: ${error.messsage}`)
            }
        } catch (error) {
            console.error(`窗口对象获取失败，code: ${error.code} message: ${error.messsage}`)
        }

    }

    private onHeightBpChange(WindowHeight: number, WindowWidth: number) {
        let heightBp = 0
        const WindowAspectRatio = WindowHeight / WindowWidth // 重写高度断点
        if (WindowAspectRatio < 0.79) {
            heightBp = 0
            AppStorage.setOrCreate('currentHeightBreakpoint', heightBp)
            console.log(`断点测试 heightBp: ${heightBp} 高宽比：${WindowAspectRatio}`)
        } else if (WindowAspectRatio >= 0.79 && WindowAspectRatio < 1.2) {
            heightBp = 1
            AppStorage.setOrCreate('currentHeightBreakpoint', heightBp)
            console.log(`断点测试 heightBp: ${heightBp} 高宽比：${WindowAspectRatio}`)
        } else if (WindowAspectRatio >= 1.2) {
            heightBp = 2
            AppStorage.setOrCreate('currentHeightBreakpoint', heightBp)
            console.log(`断点测试 heightBp: ${heightBp} 高宽比：${WindowAspectRatio}`)
        }
    }

}
