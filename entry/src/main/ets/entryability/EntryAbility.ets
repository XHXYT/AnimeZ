import UIAbility from '@ohos.app.ability.UIAbility';
import hilog from '@ohos.hilog';
import window from '@ohos.window';
import { AbilityConstant, bundleManager, Configuration, ConfigurationConstant, Want, wantConstant } from '@kit.AbilityKit';
import { BusinessError, deviceInfo, SuppressWarnings, SuppressWarningsType } from '@kit.BasicServicesKit';
import { dataSourceManager } from '../api/DataSourceManager';
import { appSettings, AppSettings } from './Settings';
import { _AnimeState, AnimeState } from './AnimeState';
import { preferenceUtil } from '../utils/PreferenceUtil';
import { ColorModeManager } from '../utils/ColorModeManager';
import { ToastUtil } from '../utils/ToastUtils';
import { RedPlayerConfigBuilder, RedPlayerInitManager, RedPlayerPreload } from '@rte-xhs/redplayer';
import { permissionManage } from '../utils/PermissionManage';
import SystemBarUtils from '../utils/SystemBarUtils';
import { appContinueModel, IAppContinue } from '../viewmodel/AppContinueModel';
import SQLite from '../db/SQLite';


export default class EntryAbility extends UIAbility {
    private storage: LocalStorage = new LocalStorage();
    private uiContext?: UIContext;
    private mainWindow?: window.Window;
    // 窗口尺寸变化监听（合并断点与窗口尺寸更新，持有引用供解绑）
    private onWindowSizeChange: (windowSize: window.Size) => void = (windowSize: window.Size) => {
        if (!this.uiContext) {
            return;
        }
        const widthBp: WidthBreakpoint = this.uiContext.getWindowWidthBreakpoint();
        const width: number = this.uiContext.px2vp(windowSize.width);
        const height: number = this.uiContext.px2vp(windowSize.height);
        // V2 全局状态
        AnimeState.widthBp = widthBp;
        AnimeState.windowWidth = width;
        AnimeState.windowHeight = height;
        // 高度断点
        const heightBp: HeightBreakpoint = this.getHeightBreakpoint(height, width);
        AnimeState.heightBp = heightBp;
        hilog.info(0x0000, 'WindowLog', '窗口高度：%{public}f vp 宽度：%{public}f vp', height, width);
    };
    // 自由窗口模式变化监听（true 为 PC 窗口模式，false 为普通窗口模式，持有引用供解绑）
    private onFreeWindowModeChange: (data: boolean) => void = (data: boolean) => {
        AnimeState.windowMode = data;
        if (this.mainWindow) {
            this.applyWindowDecor(this.mainWindow);
            this.readTitleButtonRect(this.mainWindow);
        }
        hilog.info(0x0000, 'WindowLog', '当前窗口模式 freeWindowMode：%{public}s', JSON.stringify(data));
    };
    // 窗口三键区域变化监听（持有引用供解绑）
    private onTitleButtonRectChange: (rect: window.TitleButtonRect) => void = (rect: window.TitleButtonRect) => {
        AnimeState.titleButtonWidth = rect.width + rect.right;
        AnimeState.titleButtonCenter = rect.top + rect.height / 2;
    };
    // 避让区域变化监听（持有引用供解绑）
    private onAvoidAreaChange: (data: window.AvoidAreaOptions) => void = (data: window.AvoidAreaOptions) => {
        if (!this.uiContext) {
            return;
        }
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
            const topRectHeight: number = this.uiContext.px2vp(data.area.topRect.height);
            AnimeState.topRectHeight = topRectHeight;
        } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
            const bottomRectHeight: number = this.uiContext.px2vp(data.area.bottomRect.height);
            AnimeState.bottomRectHeight = bottomRectHeight;
        }
    };

    async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
        // 关闭应用接续 -> 在特定的页面才打开
        this.context.setMissionContinueState(AbilityConstant.ContinueState.INACTIVE, (result) => {
            console.log(`setMissionContinueState: ${JSON.stringify(result)}`)
        })
        hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
        // 初始化 源管理器、数据库 上下文
        await dataSourceManager.init(this.context)
        // 检查设备形式
        _AnimeState.DeviceProductModel = deviceInfo.productModel
        // 构建RedPlayer
        const redPlayerConfigBuilder = new RedPlayerConfigBuilder()
        // redPlayerConfigBuilder.cachePath = 'your player cache path'
        // redPlayerConfigBuilder.logger?.d('your custom logger')
        // 初始化 RedPlayer
        RedPlayerInitManager.initPlayer(redPlayerConfigBuilder)
        // Init RedPlayer preload component
        // RedPlayerPreload.globalInit('your preload cache path', 20, 4, 0)

        this.getContinueData(want, launchParam);
        // 初始化数据库
        SQLite.context = this.context
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
                appContinueModel.RecoverData(data)
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
        // 系统深浅色等配置变化时同步全局状态（替代 V1 幽灵 key currentColorMode）
        AnimeState.currentColorMode = newConfig.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
        // 深浅色切换后按当前样式重绘系统栏内容颜色，避免状态栏字色残留旧模式
        SystemBarUtils.reapplyWindowSystemBar()
    }

    onWindowStageCreate(windowStage: window.WindowStage) {
        // Main window is created, set main page for this ability
        hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

        this.stageLoadPage(windowStage);
    }

    /**
     * 启动链路：preferences → 应用设置加载 → 版本号 → 颜色模式 → 加载首页 → 窗口初始化
     * 保证设置先于首帧就绪，避免首帧使用默认配置
     */
    private async stageLoadPage(windowStage: window.WindowStage): Promise<void> {
        try {
            // 1. 初始化 preferences
            try {
                await preferenceUtil.init(this.context)
            } catch (e) {
                const err = e as BusinessError
                hilog.error(0x0000, 'testTag', 'preferences 初始化失败，设置将使用默认值。Cause: %{public}s',
                    JSON.stringify(err) ?? '');
            }
            // 2. 加载应用设置（含旧版 PersistentStorage 数据一次性迁移）
            await appSettings.load()
            // 3. 初始化应用版本名
            try {
                await AppSettings.initVersion()
            } catch (e) {
                hilog.error(0x0000, 'testTag', '应用版本号初始化失败。Cause: %{public}s', JSON.stringify(e) ?? '');
            }
            // 4. 初始化颜色模式（首帧前生效）
            ColorModeManager.switchColorMode(this.context, appSettings.color_mode)
            AnimeState.currentColorMode =
                this.context.config.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
            // 5. 加载首页
            await windowStage.loadContent('pages/Index')
            hilog.info(0x0000, 'testTag', 'Succeeded in loading the content.');
            // 6. 主窗口初始化（UIContext、避让高度、断点、监听器注册）
            await this.initMainWindow(windowStage)
        } catch (e) {
            const err = e as BusinessError
            hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{public}s',
                JSON.stringify(err) ?? '');
            // 兜底：确保首页加载，避免白屏
            windowStage.loadContent('pages/Index')
            try {
                await this.initMainWindow(windowStage)
            } catch (error) {
                hilog.error(0x0000, 'testTag', 'Failed to init main window. Cause: %{public}s',
                    JSON.stringify(error) ?? '');
            }
        }
    }

    /**
     * 主窗口初始化：全屏、UIContext、权限、避让高度、断点、监听器注册（写入 AnimeState）
     */
    @SuppressWarnings({ rules: [SuppressWarningsType.SYSCAP] })
    private async initMainWindow(windowStage: window.WindowStage): Promise<void> {
        const mainWindow = await windowStage.getMainWindow()
        this.mainWindow = mainWindow

        // 开启窗口尺寸记忆（仅支持的设备生效，其余由系统返回 801 忽略）
        try {
            windowStage.setWindowRectAutoSave(true)
                .then(() => {
                    console.info('窗口尺寸记忆已开启');
                })
                .catch((err: BusinessError) => {
                    console.error(`窗口尺寸记忆开启失败，code: ${err.code} message: ${err.message}`);
                });
        } catch (error) {
            const err = error as BusinessError
            console.error(`窗口尺寸记忆调用失败，code: ${err.code} message: ${err.message}`);
        }

        // 设置窗口全屏
        mainWindow.setWindowLayoutFullScreen(true)
            .then(() => {
                console.info('已成功将窗口布局设置为全屏模式');
            })
            .catch((err: BusinessError) => {
                console.error('无法将窗口布局设置为全屏模式 Cause:' + JSON.stringify(err));
            });

        try {
            const uiContext = mainWindow.getUIContext();
            this.uiContext = uiContext;
            // V2 全局状态
            _AnimeState.UIContext = uiContext
            _AnimeState.Context = this.context
            _AnimeState.window = mainWindow

            // 初始化通知
            ToastUtil.initContext(uiContext);
            // 初始化权限
            permissionManage.requestPermission(uiContext.getHostContext() as Context);

            // 宽度断点初始值
            const widthBp: WidthBreakpoint = uiContext.getWindowWidthBreakpoint();
            AnimeState.widthBp = widthBp

            // 窗口模式初始值（PC 自由窗口模式）
            try {
                AnimeState.windowMode = mainWindow.isInFreeWindowMode()
            } catch (error) {
                const err = error as BusinessError
                console.error(`窗口模式获取失败，code: ${err.code} message: ${err.message}`);
            }

            // 窗口模式：隐藏装饰栏（保留三键）并读取三键避让区域
            this.applyWindowDecor(mainWindow)
            this.readTitleButtonRect(mainWindow)

            // 避让高度初始值
            this.readAvoidAreas(mainWindow)
            // 窗口尺寸初始值
            this.readWindowRect(mainWindow)

            // 注册监听器
            mainWindow.on('windowSizeChange', this.onWindowSizeChange)
            mainWindow.on('avoidAreaChange', this.onAvoidAreaChange)
            try {
                mainWindow.on('freeWindowModeChange', this.onFreeWindowModeChange)
            } catch (error) {
                const err = error as BusinessError
                console.error(`窗口模式监听注册失败，code: ${err.code} message: ${err.message}`);
            }
            try {
                mainWindow.on('windowTitleButtonRectChange', this.onTitleButtonRectChange)
            } catch (error) {
                const err = error as BusinessError
                console.error(`三键区域监听注册失败，code: ${err.code} message: ${err.message}`);
            }
        } catch (error) {
            const err = error as BusinessError
            console.error(`UI上下文获取失败，code: ${err.code} message: ${err.message}`);
        }
    }

    /**
     * 窗口模式下隐藏系统装饰栏（三键保留，下沉到页面右上角）
     */
    @SuppressWarnings({ rules: [SuppressWarningsType.SYSCAP] })
    private applyWindowDecor(mainWindow: window.Window): void {
        if (!AnimeState.windowMode) {
            return;
        }
        try {
            mainWindow.setWindowDecorVisible(false)
        } catch (error) {
            const err = error as BusinessError
            console.error(`窗口装饰栏隐藏失败，code: ${err.code} message: ${err.message}`);
        }
    }

    /**
     * 读取三键区域宽度写入全局状态（非窗口模式置 0）
     */
    private readTitleButtonRect(mainWindow: window.Window): void {
        if (!AnimeState.windowMode) {
            AnimeState.titleButtonWidth = 0
            AnimeState.titleButtonCenter = 0
            return;
        }
        try {
            const rect: window.TitleButtonRect = mainWindow.getTitleButtonRect()
            AnimeState.titleButtonWidth = rect.width + rect.right
            AnimeState.titleButtonCenter = rect.top + rect.height / 2
        } catch (error) {
            AnimeState.titleButtonWidth = 0
            AnimeState.titleButtonCenter = 0
            const err = error as BusinessError
            console.error(`三键区域获取失败，code: ${err.code} message: ${err.message}`);
        }
    }

    /**
     * 读取避让高度初始值
     */
    private readAvoidAreas(mainWindow: window.Window): void {
        // 导航栏遮挡区域
        try {
            const avoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
            const bottomRectHeight = this.uiContext?.px2vp(avoidArea.bottomRect.height) ?? 0
            AnimeState.bottomRectHeight = bottomRectHeight
        } catch (error) {
            console.error(`导航栏避让获取失败，code: ${error.code} message: ${error.messsage}`)
        }
        // 状态栏遮挡区域
        try {
            const topAvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
            const topRectHeight = this.uiContext?.px2vp(topAvoidArea.topRect.height) ?? 0
            AnimeState.topRectHeight = topRectHeight
        } catch (error) {
            console.error(`状态栏避让获取失败，code: ${error.code} message: ${error.messsage}`)
        }
    }

    /**
     * 读取窗口尺寸初始值并计算高度断点
     */
    private readWindowRect(mainWindow: window.Window): void {
        try {
            const properties = mainWindow.getWindowProperties()
            const rect = properties.windowRect
            const windowWidth = this.uiContext?.px2vp(rect.width) ?? 0
            const windowHeight = this.uiContext?.px2vp(rect.height) ?? 0
            AnimeState.windowWidth = windowWidth
            AnimeState.windowHeight = windowHeight
            const heightBp = this.getHeightBreakpoint(windowHeight, windowWidth)
            AnimeState.heightBp = heightBp
            hilog.info(0x0000, 'WindowLog', '窗口高度：%{public}d vp 宽度：%{public}i vp', windowHeight, windowWidth)
        } catch (error) {
            console.error(`窗口大小获取失败，code: ${error.code} message: ${error.messsage}`)
        }
    }

    /**
     * 根据窗口高宽比计算高度断点
     */
    private getHeightBreakpoint(height: number, width: number): HeightBreakpoint {
        const aspectRatio = height / width
        if (aspectRatio < 0.79) {
            return HeightBreakpoint.HEIGHT_SM
        } else if (aspectRatio < 1.2) {
            return HeightBreakpoint.HEIGHT_MD
        }
        return HeightBreakpoint.HEIGHT_LG
    }

    onWindowStageDestroy() {
        // Main window is destroyed, release UI related resources
        hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
        // 解绑窗口监听器（强杀/窗口已销毁时 off 会抛 1300002，需兜底避免崩溃）
        try {
            this.mainWindow?.off('windowSizeChange', this.onWindowSizeChange)
            this.mainWindow?.off('avoidAreaChange', this.onAvoidAreaChange)
            this.mainWindow?.off('freeWindowModeChange', this.onFreeWindowModeChange)
            this.mainWindow?.off('windowTitleButtonRectChange', this.onTitleButtonRectChange)
        } catch (error) {
            hilog.error(0x0000, 'testTag', 'onWindowStageDestroy off failed: %{public}s', JSON.stringify(error));
        }
        this.mainWindow = undefined
        this.uiContext = undefined
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

        let continueInput = appContinueModel.getCurrentVideoPageDetail();
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

}
