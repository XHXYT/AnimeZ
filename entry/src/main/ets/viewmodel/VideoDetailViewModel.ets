
import IPlayerManager, { PlayerListener, PlayerStatus } from '../player/model/IPlayerManager';
import { HISTORY_CHANGED_EVENT } from '../utils/EventBus';
import { BusinessError } from '@kit.BasicServicesKit';
import { DEFAULT_DURATION } from '../utils/TransitionHelper';
import { ToastUtil } from '../utils/ToastUtils';
import { AppConfigs } from '../entryability/Settings';
import { dataSourceManager } from '../api/DataSourceManager';
import { VideoNavigateInfo } from '../entity/VideoNavigateInfo';
import { PanelController } from '../components/CustomPanel';
import VideoDetailInfo from '../entity/VideoDetailInfo';
import EpisodeInfo from '../entity/EpisodeInfo';
import SystemBarUtils from '../utils/SystemBarUtils';
import Logger from '../utils/Logger';
import { ViewState } from '../components/StateView';
import { StringUtils } from '../utils/StringUtils';
import { window } from '@kit.ArkUI';
import VideoCollectionInfo from '../entity/VideoCollectionInfo';
import { VideoCollectionTable } from '../db/impl/VideoCollectionDao';
import VideoHistoryInfo, { HistoryInfo } from '../entity/VideoHistoryInfo';
import { VideoHistoryTable } from '../db/impl/VideoHistoryDao';


@Observed
export class VideoDetailViewModel {
  // 视频详情信息
  public videoDetailInfo: VideoDetailInfo = {
    title: '',
    sourceKey: '',
    coverUrl: '',
    episodes: [],
    recommends: []
  };

  // 播放状态
  public isCollect: boolean = false;
  public episodeIndex: number = 0;
  public episodeListIndex: number = 0;
  public isFullScreen: boolean = false;
  public isBackgroundLoaded: boolean = false;
  public state: number = 0;
  public errorMessage: string = '';
  public panelContentType: number = 0;
  public isFirstPlay: boolean = true;
  public isFreeWindow: boolean = false;

  // 视频信息
  public videoID: number | null = -1;
  public collectID: number | null = 0;
  public sourceKey: string = '';
  public title: string = '';
  public url: string = ''; // 剧集链接

  // 历史和收藏信息
  public historyInfo: VideoHistoryInfo = HistoryInfo;
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

  // 应用设置
  public appSettings: AppConfigs;

  // 私有变量
  private saveCount: number = 0
  private pausedOnHide = false;
  private onStatusChangedCallback?: (status: number) => void;
  private onFullScreenChangedCallback?: (isFullScreen: boolean) => void;
  private onProgressChangeCallback?: (totalTime: number, currentTime: number) => void;

  constructor(playerManager: IPlayerManager, appSettings: AppConfigs, context: Context) {
    this.videoCollectionInfoDB = new VideoCollectionTable(context)
    this.videoHistoryInfoDB = new VideoHistoryTable(context)
    this.playerManager = playerManager;
    this.appSettings = appSettings;
    this.initPlayerListener();
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
        this.onStatusChangedCallback?.(status);
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
        this.onFullScreenChangedCallback?.(isFullScreen);
        const windowClass = AppStorage.get<window.Window>('WindowClass')
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
      onVideoSizeChange: () => {},
      onProgressChange: (totalTime: number, currentTime: number) => {
        if (this.historyInfo) {
          this.historyInfo.totalTime = totalTime;
          this.historyInfo.currentTime = currentTime;
          this.saveHistoryInfo();
        }
        this.onProgressChangeCallback?.(totalTime, currentTime);
      },
      onBuffering: (type, value) => value
    };
    this.playerManager.addListener(playerListener);
  }

  // 设置回调函数
  public setOnStatusChangedCallback(callback: (status: number) => void) {
    this.onStatusChangedCallback = callback;
  }

  public setOnFullScreenChangedCallback(callback: (isFullScreen: boolean) => void) {
    this.onFullScreenChangedCallback = callback;
  }

  public setOnProgressChangeCallback(callback: (totalTime: number, currentTime: number) => void) {
    this.onProgressChangeCallback = callback;
  }

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
      // 尝试播放视频
      this.playVideo(this.historyInfo.episodeListIndex, this.historyInfo.episodeIndex);
    } catch (err) {
      this.errorMessage = err.message;
      this.state = ViewState.ERROR;
      Logger.e('fail', `VideoDetailViewModel.getDetailInfo 视频详情获取`, err);
    }
  }

  // 播放视频
  public async playVideo(episodeListIndex: number, episodeIndex: number) {
    Logger.e('tips', `playVideo episodeListIndex = ${episodeListIndex} episodeIndex=${episodeIndex}`);
    this.episodeListIndex = episodeListIndex;
    this.episodeIndex = episodeIndex;

    const episodeList = this.videoDetailInfo.episodes[this.episodeListIndex];
    const episode = episodeList.episodes[this.episodeIndex];

    this.historyInfo.episodeListIndex = episodeListIndex;
    this.historyInfo.episodeIndex = episodeIndex;
    this.historyInfo.episodeName = episode.title;
    this.historyInfo.videoUrl = episode.videoUrl as string;

    if (episode.videoUrl) {
      this.saveHistoryInfo(true);
      this.checkVideoInfo();
      this.playerManager.playEpisodeList(episodeList.episodes, this.episodeIndex);
    } else {
      try {
        console.log(`VideoDetailViewModel.playVideo 视频剧集链接，link：${episode.link}`)
        let url = await dataSourceManager.parseVideoUrl(episode.link)
        console.log(`VideoDetailViewModel.playVideo 视频播放链接解析成功，url：${url}`)
        // 检查链接是否需要js
        const finalUrl = await this.checkParesVideoLink(url)
        episode.videoUrl = finalUrl
        this.historyInfo.videoUrl = finalUrl
        this.saveHistoryInfo(true);
        this.checkVideoInfo();
        this.playerManager.playEpisodeList(episodeList.episodes, this.episodeIndex)
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
      AppStorage.setOrCreate<string>('web_js_video_link', '');
      AppStorage.setOrCreate<string>('webview_url', rawLink);
      AppStorage.setOrCreate<string>('run_js', js);
      AppStorage.setOrCreate<boolean>('showWebView', true)
      console.info(`checkParesVideoLink: 已激活WebView，目标URL: ${url}, JS:${js}`);

      // 开始轮询等待结果
      const pollingIntervalMs = 500; // 轮询间隔500毫秒，避免过于频繁
      const timeoutMs = 9000; // 超时时间5秒
      const startTime = Date.now();

      while (true) {
        // 检查是否超时
        if (Date.now() - startTime > timeoutMs) {
          // 超时后，隐藏WebView并抛出错误
          AppStorage.setOrCreate<boolean>('showWebView', false);
          console.error('checkParesVideoLink: 轮询超时，未能获取JS结果。');
          return Promise.reject(new Error('JS execution timed out.'));
        }

        // 从AppStorage获取JS执行结果
        const jsLink = AppStorage.get<string>('web_js_video_link');

        // 如果结果存在且不为空，说明JS已执行并返回了值
        if (jsLink && jsLink !== '' && jsLink.includes('http')) {
          console.info(`checkParesVideoLink: 成功获取JS链接: ${jsLink}`);
          // 隐藏WebView
          AppStorage.setOrCreate<boolean>('showWebView', false);
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
    const HistoryList = await this.videoHistoryInfoDB.queryByTitle(this.title);
    if (!HistoryList) {
      console.warn(`没有查询到历史记录，暂无历史记录`)
      return
    }
    if (HistoryList.length !== 0) {
      const HistoryDetail = HistoryList[0];
      if (HistoryDetail) {
        this.historyInfo = HistoryDetail;
        this.videoID = this.historyInfo.id;
      }
    }
  }

  // 检查收藏信息
  private async checkCollectionInfo() {
    const CollectionInfo = await this.videoCollectionInfoDB.queryOneByTitle(this.title);
    if (CollectionInfo.id) {
      this.collectionInfo = CollectionInfo
      if (this.collectionInfo !== undefined && this.videoID !== null) {
        this.isCollect = true;
      }
    }
  }

  // 收藏视频
  public async collect() {
    Logger.d('collect', 'collect() called');
    try {
      // 创建收藏对象
      const theCollectionInfo: VideoCollectionInfo = {
        id: this.collectID,
        link: this.url,
        title: this.videoDetailInfo.title,
        coverUrl: this.videoDetailInfo.coverUrl,
        sourceKey: this.sourceKey,
        accessTime: Date.now()
      };
      // 保存到数据库，返回插入的记录ID
      const insertId = await this.videoCollectionInfoDB.save(theCollectionInfo);
      // 更新 collectID 为数据库返回的实际ID
      this.collectID = insertId;
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
      await this.videoCollectionInfoDB.deleteByLink(this.url);
      this.isCollect = false;
      ToastUtil.showToast({ message: "取消收藏" });
    } catch (err) {
      console.error(`取消收藏失败：${err.message}`)
    }
  }

  // 处理页面显示
  public onPageShow() {
    if (this.pausedOnHide) {
      if (!this.playerManager.isPlaying()) {
        this.playerManager.start();
      }
      this.pausedOnHide = false;
    }
  }

  // 处理页面隐藏
  public async onPageHide() {
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

  // 销毁资源
  public onDestroy() {
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

  // 处理手机横屏变化
  public onPhoneLandscape(isPhoneLandscape: boolean) {
    if (isPhoneLandscape) {
      this.playerManager.enterFullScreen();
    } else {
      this.playerManager.exitFullScreen();
    }
  }

}
