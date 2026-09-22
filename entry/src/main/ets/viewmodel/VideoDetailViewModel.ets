
import IPlayerManager, { PlayerListener, PlayerStatus } from '../player/model/IPlayerManager';
import { HISTORY_CHANGED_EVENT, PLAYER_SWITCH_EVENT } from '../utils/EventBus';
import emitter from '@ohos.events.emitter';
import { BusinessError } from '@kit.BasicServicesKit';
import { ToastUtil } from '../utils/ToastUtils';
import { AppConfigs, appSettings } from '../entryability/Settings';
import { dataSourceManager } from '../api/DataSourceManager';
import { VideoNavigateInfo } from '../entity/VideoNavigateInfo';
import { PanelController } from '../components/CustomPanel';
import VideoDetailInfo from '../entity/VideoDetailInfo';
import EpisodeInfo from '../entity/EpisodeInfo';
import SystemBarUtils from '../utils/SystemBarUtils';
import Logger from '../utils/Logger';
import { ViewState } from '../components/StateView';
import { StringUtils } from '../utils/StringUtils';
import { _AnimeState, AnimeState } from '../entryability/AnimeState';
import { window } from '@kit.ArkUI';
import VideoCollectionInfo from '../entity/VideoCollectionInfo';
import { VideoCollectionTable } from '../db/impl/VideoCollectionDao';
import VideoHistoryInfo, { HistoryInfo } from '../entity/VideoHistoryInfo';
import { VideoHistoryTable } from '../db/impl/VideoHistoryDao';


/** 续播定位结果：校正后的剧集索引 + 是否保留播放进度 */
class ResumeTarget {
  listIndex: number = 0;
  episodeIndex: number = 0;
  keepPosition: boolean = false;
}

@ObservedV2
export class VideoDetailViewModel {
  // 视频详情信息
  @Trace public videoDetailInfo: VideoDetailInfo = {
    title: '',
    sourceKey: '',
    coverUrl: '',
    episodes: [],
    recommends: []
  };

  // 播放状态
  @Trace public isCollect: boolean = false;
  @Trace public episodeIndex: number = 0;
  @Trace public episodeListIndex: number = 0;
  @Trace public isFullScreen: boolean = false;
  @Trace public isBackgroundLoaded: boolean = false;
  @Trace public state: number = 0;
  @Trace public errorMessage: string = '';
  @Trace public panelContentType: number = 0;
  /** 视频宽高（用于布局判断视频横竖方向） */
  @Trace public videoWidth: number = 0;
  @Trace public videoHeight: number = 0;
  public isFirstPlay: boolean = true;
  public isFreeWindow: boolean = false;

  // 视频信息
  public videoID: number | null = -1;
  public collectID: number | null = 0;
  public sourceKey: string = '';
  public title: string = '';
  public url: string = ''; // 剧集链接

  // 历史和收藏信息
  @Trace public historyInfo: VideoHistoryInfo = HistoryInfo;
  public collectionInfo: VideoCollectionInfo = {
    id: null,
    link: '',
    title: '',
    coverUrl: '',
    sourceKey: '',
    accessTime: 0
  }

  public videoCollectionInfoDB: VideoCollectionTable
  public videoHistoryInfoDB: VideoHistoryTable
  // 播放器管理
  public playerManager: IPlayerManager;

  // 应用设置（模块级单例）
  public readonly appSettings: AppConfigs = appSettings;

  // 私有变量
  private saveCount: number = 0
  private pausedOnHide = false;

  constructor(playerManager: IPlayerManager, context: Context) {
    this.videoCollectionInfoDB = new VideoCollectionTable(context)
    this.videoHistoryInfoDB = new VideoHistoryTable(context)
    this.playerManager = playerManager;
    this.initPlayerListener();
    // 控制面板切换播放器后端：以当前进度重播当前集
    PLAYER_SWITCH_EVENT.on((data: emitter.EventData) => {
      const resumePos = data.data ? data.data['resumePos'] as number : -1
      this.onPlayerSwitch(resumePos)
    })
  }

  /**
   * 播放器后端切换：appSettings.default_player 变更触发 MultiVideoPlayer
   * 重建（旧组件卸载释放、新组件挂载注册），等待新实例注册完成后
   * 以切换前的播放位置重播当前集
   */
  private async onPlayerSwitch(resumePos: number) {
    Logger.e('tips', `onPlayerSwitch resumePos=${resumePos}`)
    // AVPlayer 等后端为异步创建，留足新组件挂载注册时间
    await this.sleep(500)
    this.resumePosition = resumePos > 0 ? resumePos : -1
    this.playVideo(this.episodeListIndex, this.episodeIndex)
  }

  // 初始化播放器监听器
  private initPlayerListener() {
    const playerListener: PlayerListener = {
      onStatusChanged: (status: number) => {
        if (status == PlayerStatus.DONE && this.appSettings.auto_play_next_episode && this.videoDetailInfo.episodes) {
          const episodeList = this.videoDetailInfo.episodes[this.episodeListIndex];
          if (this.episodeIndex < episodeList.episodes.length - 1) {
            this.playVideo(this.episodeListIndex, this.episodeIndex + 1);
          }
        }
      },
      onEpisodeChanged: (episodeList: EpisodeInfo[], episodeIndex: number) => {
        if (this.episodeIndex !== episodeIndex) {
          this.episodeIndex = episodeIndex;
          this.playVideo(this.episodeListIndex, this.episodeIndex);
        }
      },
      onVideoSpeedChanged: () => {},
      onFullScreenChanged: (isFullScreen: boolean) => {
        this.isFullScreen = isFullScreen;
        const windowClass = _AnimeState.window
        if (windowClass) {
          if (!isFullScreen) {
            // 退出横屏小窗
            const promise = windowClass.disableLandscapeMultiWindow().catch(() => {
              console.error(`VideoDetailViewModel..onFullScreenChanged Failed to 获取 windowClass.disableLandscapeMultiWindow promise.`)});
            promise.then(() => {
              console.info('VideoDetailViewModel..onFullScreenChanged Succeeded in 退出 multi-window become landscape.');
            }).catch((err: BusinessError) => {
              console.error(`VideoDetailViewModel..onFullScreenChanged Failed to 退出 multi-window become landscape. Cause code: ${err.code}, message: ${err.message}`);
            });
            // 退出全屏后按设置恢复方向锁定，防止关闭自动旋屏时旋转窗口导致"伪全屏"
            this.applyOrientationLock();
          } else {
            // 进入横屏小窗
            const promise = windowClass.enableLandscapeMultiWindow().catch(() => {
              console.error(`VideoDetailViewModel..onFullScreenChanged Failed to 获取 windowClass.enableLandscapeMultiWindow promise.`)});
            promise.then(() => {
              console.info('VideoDetailViewModel..onFullScreenChanged Succeeded in making multi-window become landscape.');
            }).catch((err: BusinessError) => {
              console.error(`VideoDetailViewModel..onFullScreenChanged Failed to make multi-window become landscape. Cause code: ${err.code}, message: ${err.message}`);
            });
          }
        } else {
          console.error(`VideoDetailViewModel..onFullScreenChanged 未获取WindowClass`)
        }
      },
    onVideoFitChanged: (videoFit) => videoFit,
    onVideoSizeChange: (w: number, h: number): void => {
      this.videoWidth = w;
      this.videoHeight = h;
    },
      onProgressChange: (totalTime: number, currentTime: number) => {
        if (this.historyInfo) {
          this.historyInfo.totalTime = totalTime;
          this.historyInfo.currentTime = currentTime;
          this.saveHistoryInfo();
        }
      },
      onBuffering: (type, value) => value
    };
    this.playerManager.addListener(playerListener);
  }

  // 历史续播：仅首次进入详情页时携带，消费后立即复位，换集/重试不续播旧位置
  private resumePosition: number = -1;

  // 初始化数据
  public async initialize(params: VideoNavigateInfo) {
    this.url = params.url as string;
    this.videoID = params.id;
    this.title = params.title;
    this.sourceKey = params.sourceKey as string;

    if (this.videoID !== null) {
      this.isFirstPlay = false;
    }

    await this.checkVideoInfo();
    this.getDetailInfo();
    this.checkCollectionInfo();
  }

  // 获取视频详情
  public async getDetailInfo() {
    this.state = ViewState.LOADING
    try {
      // 获取视频详情
      console.log(`VideoDetailViewModel.playVideo 等待获取视频详情的链接，url：${this.url}`)
      const info = await dataSourceManager.getVideoDetailInfo(this.url, this.appSettings.episodes_order)
      this.videoDetailInfo = info;
      console.log(`VideoDetailViewModel.playVideo 获取视频详情成功，info：${JSON.stringify(this.videoDetailInfo, null, 2)}`)
      // 更新视频信息
      this.historyInfo.link = this.videoDetailInfo.url as string;
      this.historyInfo.title = this.videoDetailInfo.title;
      this.historyInfo.coverUrl = this.videoDetailInfo.coverUrl;
      this.historyInfo.sourceKey = this.sourceKey;
      this.state = ViewState.CONTENT
      SystemBarUtils.setWindowSystemBarTransparent(true);
      // 历史续播：先校正索引（源站列表可能增删集导致索引错位），再恢复播放位置
      const resumeMs = this.historyInfo.currentTime;
      const canResume = resumeMs > 0 && (this.historyInfo.totalTime <= 0 || resumeMs < this.historyInfo.totalTime - 5000);
      const target = this.resolveResumeIndex(this.historyInfo.episodeListIndex, this.historyInfo.episodeIndex, this.historyInfo.episodeName);
      if (canResume && target.keepPosition) {
        this.resumePosition = resumeMs;
      }
      // 尝试播放视频
      this.playVideo(target.listIndex, target.episodeIndex);
    } catch (err) {
      this.errorMessage = err.message;
      this.state = ViewState.ERROR;
      Logger.e('fail', `VideoDetailViewModel.getDetailInfo 视频详情获取`, err);
    }
  }

  /**
   * 校正历史记录中的剧集索引并决定是否保留续播进度：
   * 源站剧集列表可能增删集或调整顺序，DB 存的纯位置索引会错位。
   * - 列表索引越界 → 回退第一集并放弃进度
   * - 集索引越界 → 按剧集名回查；命中则用新索引并保留进度，否则回退第一集并放弃进度
   * - 索引均合法但名称对不上 → 按剧集名回查；命中则用新索引，否则信任原索引（名称格式变化）
   */
  private resolveResumeIndex(listIndex: number, episodeIndex: number, episodeName: string): ResumeTarget {
    const target = new ResumeTarget();
    const episodes = this.videoDetailInfo.episodes;
    if (!episodes || episodes.length === 0) {
      return target;
    }
    if (listIndex < 0 || listIndex >= episodes.length) {
      // 剧集列表整体变化：回退第一集，进度已不可信
      return target;
    }
    target.listIndex = listIndex;
    target.keepPosition = true;
    const list = episodes[listIndex].episodes;
    if (!list || list.length === 0) {
      target.keepPosition = false;
      return target;
    }
    if (episodeIndex >= 0 && episodeIndex < list.length) {
      if (episodeName === '' || list[episodeIndex].title === episodeName) {
        target.episodeIndex = episodeIndex;
        return target;
      }
      // 名称对不上：按名称回查（列表增删集导致错位），查不到则信任原索引
      const byName = list.findIndex((item: EpisodeInfo) => item.title === episodeName);
      target.episodeIndex = byName >= 0 ? byName : episodeIndex;
      return target;
    }
    // 集索引越界：按名称回查，找不到则回退第一集并放弃进度
    if (episodeName !== '') {
      const byName = list.findIndex((item: EpisodeInfo) => item.title === episodeName);
      if (byName >= 0) {
        target.episodeIndex = byName;
        return target;
      }
    }
    target.episodeIndex = 0;
    target.keepPosition = false;
    return target;
  }

  // 播放视频
  public async playVideo(episodeListIndex: number, episodeIndex: number) {
    Logger.e('tips', `playVideo episodeListIndex = ${episodeListIndex} episodeIndex=${episodeIndex}`);
    this.episodeListIndex = episodeListIndex;
    this.episodeIndex = episodeIndex;
    // 读取并复位续播位置（仅首次进入详情页时为有效值）
    const startPos = this.resumePosition;
    this.resumePosition = -1;

    const episodeList = this.videoDetailInfo.episodes[this.episodeListIndex];
    const episode = episodeList.episodes[this.episodeIndex];

    this.historyInfo.episodeListIndex = episodeListIndex;
    this.historyInfo.episodeIndex = episodeIndex;
    this.historyInfo.episodeName = episode.title;
    this.historyInfo.videoUrl = episode.videoUrl as string;

    if (episode.videoUrl) {
      await this.saveHistoryInfo(true);
      await this.checkVideoInfo();
      this.playerManager.playEpisodeList(episodeList.episodes, this.episodeIndex, startPos);
    } else {
      try {
        console.log(`VideoDetailViewModel.playVideo 视频剧集链接，link：${episode.link}`)
        let url = await dataSourceManager.parseVideoUrl(episode.link)
        console.log(`VideoDetailViewModel.playVideo 视频播放链接解析成功，url：${url}`)
        // 检查链接是否需要js
        const finalUrl = await this.checkParesVideoLink(url)
        episode.videoUrl = finalUrl
        this.historyInfo.videoUrl = finalUrl
        await this.saveHistoryInfo(true);
        await this.checkVideoInfo();
        this.playerManager.playEpisodeList(episodeList.episodes, this.episodeIndex, startPos)
      } catch (err) {
        this.playerManager.setStatus(PlayerStatus.ERROR);
        Logger.e('fail', `VideoDetailViewModel.playVideo 视频链接解析`, err);
      }
    }
  }

  /**
   * 检查并解析视频链接
   * @param url 输入的URL，格式可能为 'selector_|_attribute_|_actual_url' 或直接的URL
   * @returns Promise<string> 返回解析后的视频链接
   */
  private async checkParesVideoLink(url: string): Promise<string> {
    // 情况一：需要通过JS解析
    if (url.includes('_|_')) {
      // 解析输入的URL字符串
      // 格式: 'rawLink_|_selector@attribute'
      const rawLink = StringUtils.splitString(url, '_|_').first;
      const js = StringUtils.splitString(url, '_|_').second;

      if (!rawLink || !js) {
        console.error('checkParesVideoLink: URL格式错误，无法解析。');
        return Promise.reject(new Error('Invalid URL format for JS parsing.'));
      }

      // 准备并激活WebView
      // *** 在开始轮询前，先清空上一次的结果，防止读到旧数据 ***
      AnimeState.webJsVideoLink = ''
      AnimeState.webviewUrl = rawLink
      AnimeState.runJs = js
      AnimeState.showWebView = true
      console.info(`checkParesVideoLink: 已激活WebView，目标URL: ${url}, JS:${js}`);

      // 开始轮询等待结果
      const pollingIntervalMs = 500; // 轮询间隔500毫秒，避免过于频繁
      const timeoutMs = 20000; // 超时时间20秒（JS 在页面加载完成 4 秒后才注入，需留足余量）
      const startTime = Date.now();

      while (true) {
        // 检查是否超时
        if (Date.now() - startTime > timeoutMs) {
          // 超时后，隐藏WebView并抛出错误
          AnimeState.showWebView = false
          console.error('checkParesVideoLink: 轮询超时，未能获取JS结果。');
          return Promise.reject(new Error('JS execution timed out.'));
        }

        // 从全局状态获取JS执行结果
        const jsLink = AnimeState.webJsVideoLink;

        // 页面内JS以 ERR_ 开头返回时表示解析失败，立即终止等待
        if (jsLink && jsLink !== '' && jsLink.startsWith('ERR_')) {
          AnimeState.showWebView = false
          console.error(`checkParesVideoLink: 页面内JS解析失败: ${jsLink}`);
          return Promise.reject(new Error(`播放地址解析失败: ${jsLink}`));
        }

        // 如果结果存在且不为空，说明JS已执行并返回了值
        if (jsLink && jsLink !== '' && jsLink.includes('http')) {
          console.info(`checkParesVideoLink: 成功获取JS链接: ${jsLink}`);
          // 隐藏WebView
          AnimeState.showWebView = false
          // 返回结果
          return jsLink;
        }

        // 如果还没结果，等待一段时间后继续下一次轮询
        console.debug(`checkParesVideoLink: 轮询中... 未获取到结果，${pollingIntervalMs}ms后重试。`);
        await this.sleep(pollingIntervalMs);
      }

    } else {
      // 情况二：直接返回输入的URL
      console.info(`checkParesVideoLink: 直接返回URL: ${url}`);
      return url;
    }
  }

  /**
   * 辅助函数：异步等待
   * @param ms 等待的毫秒数
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  // 保存历史记录
  private async saveHistoryInfo(needSave: boolean = false) {
    console.log(`当前执行保存历史记录次数：${this.saveCount}`)
    if (this.saveCount > 210 || needSave) {
      if (!this.historyInfo) return;
      this.historyInfo.id = this.videoID;
      this.historyInfo.accessTime = new Date().getTime();
      try {
        const insertId = await this.videoHistoryInfoDB.save(this.historyInfo)
        if (insertId <= 0) {
          console.error(`历史数据保存失败`)
          return
        }
        Logger.w('tips', `保存历史记录成功，ID: ${insertId}`);
        this.videoID = insertId;
      } catch (error) {
        Logger.e('fail', `saveHistoryInfo 保存历史记录`, error);
      }
      this.saveCount = 0
    } else {
      this.saveCount++
    }
  }

  // 检查视频历史信息
  private async checkVideoInfo() {
    // 优先按详情页链接精确匹配（与 save 的 upsert 键一致），
    // 避免标题互含的影片（如"海贼王"与"海贼王 剧场版"）通过模糊查询串记录
    let historyDetail = await this.videoHistoryInfoDB.queryByLink(this.url);
    if (!historyDetail && this.title !== '') {
      // 链接未命中（源站链接格式变化等），按标题+数据源精确匹配兜底
      const byTitle = await this.videoHistoryInfoDB.queryByTitleExact(this.title, this.sourceKey);
      historyDetail = byTitle[0];
    }
    if (historyDetail) {
      this.historyInfo = historyDetail;
      this.videoID = this.historyInfo.id;
    }
  }

  // 检查收藏信息
  private async checkCollectionInfo() {
    // 优先按链接精确匹配（与 save 的 upsert 键一致），
    // 未命中（源站链接格式变化等）按标题+数据源精确匹配兜底
    let collectionInfo = await this.videoCollectionInfoDB.queryByLink(this.url);
    if (!collectionInfo && this.title !== '') {
      collectionInfo = await this.videoCollectionInfoDB.queryOneByTitle(this.title, this.sourceKey);
    }
    if (collectionInfo && collectionInfo.id) {
      this.collectionInfo = collectionInfo
      this.collectID = collectionInfo.id
      this.isCollect = true;
    }
  }

  // 收藏视频
  public async collect() {
    Logger.d('collect', 'collect() called');
    try {
      // 以详情接口返回的链接为收藏键（与历史表一致）
      const detailUrl = (this.videoDetailInfo.url as string) || this.url;
      // 查找已有收藏（链接优先，标题+数据源兜底），命中则沿用原记录，避免链接变体产生重复收藏
      let existing = await this.videoCollectionInfoDB.queryByLink(detailUrl);
      if (!existing) {
        existing = await this.videoCollectionInfoDB.queryOneByTitle(this.videoDetailInfo.title, this.sourceKey);
      }
      // 创建收藏对象（已有记录沿用其 id 和 link 作为键）
      const theCollectionInfo: VideoCollectionInfo = {
        id: existing && existing.id ? existing.id : null,
        link: existing ? existing.link : detailUrl,
        title: this.videoDetailInfo.title,
        coverUrl: this.videoDetailInfo.coverUrl,
        sourceKey: this.sourceKey,
        accessTime: Date.now()
      };
      // 保存到数据库，返回插入的记录ID
      const insertId = await this.videoCollectionInfoDB.save(theCollectionInfo);
      // 更新 collectID 为数据库返回的实际ID
      this.collectID = insertId;
      this.collectionInfo = theCollectionInfo;
      this.isCollect = true;
      ToastUtil.showToast({ message: "收藏成功" });
      Logger.d('collect', `collect() success, new ID: ${insertId}`);
    } catch (error) {
      Logger.e('fail', 'collect()', error);
      ToastUtil.showToast({ message: "收藏失败" });
    }
  }

  // 取消收藏
  public async removeCollect() {
    try {
      // 优先按已加载的收藏记录 id 精确删除
      if (this.collectionInfo.id) {
        await this.videoCollectionInfoDB.deleteById(this.collectionInfo.id)
      } else if (this.collectID !== null && this.collectID > 0) {
        await this.videoCollectionInfoDB.deleteById(this.collectID)
      }
      // 兼容不同入口/历史数据的链接变体：导航链接与详情链接均尝试清理
      await this.videoCollectionInfoDB.deleteByLink(this.url)
      const detailUrl = this.videoDetailInfo.url as string
      if (detailUrl && detailUrl !== this.url) {
        await this.videoCollectionInfoDB.deleteByLink(detailUrl)
      }
      this.isCollect = false;
      this.collectID = 0;
      ToastUtil.showToast({ message: "取消收藏" });
    } catch (err) {
      console.error(`取消收藏失败：${err.message}`)
    }
  }

  // 处理页面显示
  public onPageShow() {
    // 关闭"自动旋屏"时在视频页锁定竖屏，旋转手机不再改变窗口方向
    this.applyOrientationLock();
    if (this.pausedOnHide) {
      if (!this.playerManager.isPlaying()) {
        this.playerManager.start();
      }
      this.pausedOnHide = false;
    }
  }

  // 处理页面隐藏
  public async onPageHide() {
    this.restoreOrientation();
    // 任何路径离开详情页（返回键/页面内返回/手势）都恢复默认系统栏样式
    SystemBarUtils.setWindowSystemBarTransparent(false);
    await this.saveHistoryInfo(true);
    ToastUtil.showToast({ message: '历史记录已保存' });
    // 触发历史记录更新事件
    HISTORY_CHANGED_EVENT.emit();

    if (this.playerManager.isPlaying()) {
      this.playerManager.stop();
      this.pausedOnHide = true;
    } else {
      this.pausedOnHide = false;
    }
  }

  /**
   * 按设置应用窗口方向：
   * 开启"自动旋屏"→ 跟随系统（受锁定限制的自动旋转）；
   * 关闭"自动旋屏"→ 视频页锁定竖屏，旋转手机不改变布局
   */
  private applyOrientationLock(): void {
    const windowClass = _AnimeState.window
    if (!windowClass) {
      return
    }
    const orientation: window.Orientation = this.appSettings.auto_sensor_rotate
      ? window.Orientation.AUTO_ROTATION_RESTRICTED
      : window.Orientation.PORTRAIT
    windowClass.setPreferredOrientation(orientation).catch((err: BusinessError) => {
      Logger.e('fail', `applyOrientationLock 设置窗口方向 code=${err.code}`, err)
    })
  }

  /** 恢复窗口方向为跟随系统旋转 */
  private restoreOrientation(): void {
    const windowClass = _AnimeState.window
    if (!windowClass) {
      return
    }
    windowClass.setPreferredOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED).catch((err: BusinessError) => {
      Logger.e('fail', `restoreOrientation 恢复窗口方向 code=${err.code}`, err)
    })
  }

  // 销毁资源
  public onDestroy() {
    this.restoreOrientation();
    PLAYER_SWITCH_EVENT.off()
    this.playerManager.destroy();
  }

  // 处理返回键
  public handleBackPressed(panelController: PanelController): boolean {
    if (panelController.isShow()) {
      panelController.close();
      return true;
    }

    if (this.isFullScreen) {
      this.playerManager.exitFullScreen();
      return true;
    }

    return false;
  }

  /** 当前视频是否为竖向视频（宽 < 高） */
  public isVerticalVideo(): boolean {
    return this.videoWidth > 0 && this.videoHeight > 0 && this.videoHeight > this.videoWidth;
  }

  // 处理手机横屏变化
  public onPhoneLandscape(isPhoneLandscape: boolean) {
    // 仅在开启"自动旋屏"设置时响应传感器横竖屏切换
    if (!this.appSettings.auto_sensor_rotate) {
      return
    }
    if (isPhoneLandscape) {
      // 传感器触发的全屏保持跟随传感器，转回竖屏时可自动退出
      this.playerManager.enterFullScreen(true);
    } else {
      this.playerManager.exitFullScreen();
    }
  }

}
