// VideoDetailViewModel.ets
import IPlayerManager, { PlayerListener, PlayerStatus } from '../entity/VideoPlayer/IPlayerManager';
import { HISTORY_CHANGED_EVENT } from '../utils/EventBus';
import { HistoryInfo, VideoHistoryInfo, videoHistoryInfoDB } from '../database/VideoHistoryInfoDB';
import { CollectionInfo, VideoCollectionInfo, videoCollectionInfoDB } from '../database/VideoCollectionInfoDB';
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
  public showWebview: boolean = false;
  public isFirstPlay: boolean = true;
  public isFreeWindow: boolean = false;

  // 视频信息
  public videoID: number | null = -1;
  public collectID: number | null = 0;
  public sourceKey: string = '';
  public title: string = '';
  public url: string = '';

  // 历史和收藏信息
  public historyInfo: VideoHistoryInfo = HistoryInfo;
  public collectionInfo: VideoCollectionInfo = CollectionInfo;

  // 播放器管理
  public playerManager: IPlayerManager;

  // 应用设置
  public appSettings: AppConfigs;

  // 私有变量
  private pausedOnHide = false;
  private onStatusChangedCallback?: (status: number) => void;
  private onFullScreenChangedCallback?: (isFullScreen: boolean) => void;
  private onProgressChangeCallback?: (totalTime: number, currentTime: number) => void;

  constructor(playerManager: IPlayerManager, appSettings: AppConfigs) {
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
    this.collectID = params.id;
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
      const info = await dataSourceManager.getVideoDetailInfo(this.url)
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
      this.saveHistoryInfo();
      this.checkVideoInfo();
      this.playerManager.playEpisodeList(episodeList.episodes, this.episodeIndex);
    } else {
      try {
        console.log(`VideoDetailViewModel.playVideo 视频剧集链接，link：${episode.link}`)
        const url = await dataSourceManager.parseVideoUrl(episode.link)
        console.log(`VideoDetailViewModel.playVideo 视频播放链接解析成功，link：${url}`)
        this.showWebview = false;
        episode.videoUrl = url;
        this.historyInfo.videoUrl = url;
        this.saveHistoryInfo();
        this.checkVideoInfo();
        this.playerManager.playEpisodeList(episodeList.episodes, this.episodeIndex)
      } catch (err) {
        this.playerManager.setStatus(PlayerStatus.ERROR);
        Logger.e('fail', `VideoDetailViewModel.playVideo 视频链接解析`, err);
      }
    }
  }

  // 保存历史记录
  private async saveHistoryInfo() {
    if (!this.historyInfo) return;

    if (this.videoID !== null) {
      this.historyInfo.id = this.videoID;
      this.historyInfo.accessTime = new Date().getTime();
      await videoHistoryInfoDB.update(this.historyInfo, this.videoID)
        .then((updateId) => {
          Logger.e('tips', `更新历史记录成功，ID: ${updateId}`);
        })
        .catch((error: BusinessError) => {
          Logger.e('tips', `更新历史记录失败: ${error}`);
        });
    } else {
      await videoHistoryInfoDB.insert(this.historyInfo)
        .then((insertId) => {
          Logger.e('tips', `插入历史记录成功，ID: ${insertId}`);
          this.videoID = insertId;
        })
        .catch((error: Error) => {
          Logger.e('tips', `插入历史记录失败: ${error}`);
        });
    }
  }

  // 检查视频历史信息
  private async checkVideoInfo() {
    const HistoryList = await videoHistoryInfoDB.query(this.title);
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
    const CollectionList = await videoCollectionInfoDB.query(this.title);
    if (CollectionList && CollectionList.length > 0) {
      const CollectionDetail = CollectionList[0];
      this.collectionInfo = CollectionDetail;
      if (this.collectionInfo !== undefined && this.videoID !== null) {
        this.isCollect = true;
      }
    }
  }

  // 收藏视频
  public async collect() {
    if (!this.videoDetailInfo.title || !this.videoDetailInfo.coverUrl) return;

    const theCollectionInfo: VideoCollectionInfo = {
      id: this.collectID,
      link: this.url,
      title: this.videoDetailInfo.title,
      coverUrl: this.videoDetailInfo.coverUrl,
      sourceKey: this.sourceKey,
      accessTime: Date.now()
    };

    if (this.collectID === null) {
      await videoCollectionInfoDB.insert(theCollectionInfo)
        .then(() => {
          this.isCollect = true;
          ToastUtil.showToast({ message: "收藏成功" });
        })
        .catch((error: Error) => {
          Logger.e('tips', `收藏失败: ${error}`);
        });
    } else {
      await videoCollectionInfoDB.update(theCollectionInfo)
        .then(() => {
          this.isCollect = true;
          ToastUtil.showToast({ message: "收藏成功" });
        })
        .catch((error: Error) => {
          Logger.e('tips', `更新收藏失败: ${error}`);
        });
    }
  }

  // 取消收藏
  public async removeCollect() {
    if (this.collectID !== null) {
      await videoCollectionInfoDB.delete(this.collectID);
      this.isCollect = false;
      ToastUtil.showToast({ message: "取消收藏" });
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
  public onPageHide() {
    this.saveHistoryInfo();
    ToastUtil.showToast({ message: '历史记录已保存' });
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
