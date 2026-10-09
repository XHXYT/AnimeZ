
import IPlayerManager, { PlayerListener, PlayerStatus, VideoFit } from '../player/model/IPlayerManager';
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
import { _AnimeState, AnimeState } from '../entryability/AnimeState';
import { window } from '@kit.ArkUI';
import VideoCollectionInfo from '../entity/VideoCollectionInfo';
import { PiPManager, PiPNavigationInfo } from '../player/PiPManager';
import { VideoCollectionTable } from '../db/impl/VideoCollectionDao';
import VideoHistoryInfo, { HistoryInfo } from '../entity/VideoHistoryInfo';
import { VideoHistoryTable } from '../db/impl/VideoHistoryDao';
import { WebVideoResolver } from '../utils/WebVideoResolver';
import M3u8AdFilter from '../utils/m3u8/M3u8AdFilter';


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
  /** 当前画面尺寸（供播放设置面板回显选中项） */
  @Trace public videoFit: number = VideoFit.Contain;
  /** 视频宽高（用于布局判断视频横竖方向） */
  @Trace public videoWidth: number = 0;
  @Trace public videoHeight: number = 0;
  public isFirstPlay: boolean = true;
  public isFreeWindow: boolean = false;

  // 视频信息
  public videoID: number | null = -1;
  public collectID: number | null = 0;
  @Trace public sourceKey: string = '';
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
  /** 手动小窗按钮委托（注册到 PiPManager，onDestroy 按身份清理） */
  private pipRequestHandler: (() => void) | null = null;
  /** onPageShow 时的路由栈深度（onPageHide 对比判断是 push 导航还是退后台） */
  private stackSizeOnShown: number = 0;

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
    this.registerPiPDelegates()
  }

  /** 注册 PiP 委托到管理器单例（onPageShow 时刷新，保证指向当前显示页） */
  private registerPiPDelegates(): void {
    this.pipRequestHandler = () => {
      this.enterPiPMode(true)
    }
    PiPManager.requestHandler = this.pipRequestHandler
    PiPManager.mainPositionProvider = () => this.playerManager.getCurrentPosition()
    PiPManager.mainPlayerPauser = () => {
      this.playerManager.pause().catch(() => {
      })
    }
    PiPManager.onPipError = (message: string) => {
      ToastUtil.showToast({ message: message })
    }
  }

  /** 播放状态与 PiP 后台自动拉起开关同步：仅"正在播放"允许自动拉起，其余状态一律关闭 */
  private syncPiPAutoStart(status: number): void {
    if (status === PlayerStatus.PLAY) {
      if (this.appSettings.auto_pip_on_exit && PiPManager.isPlayerSupported(this.appSettings.default_player)) {
        PiPManager.prepare()
      }
    } else {
      PiPManager.setAutoStartEnabledSafe(false)
    }
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
        if (status == PlayerStatus.PAUSE) {
          // 暂停即保存：锁屏/退后台触发的自动暂停也能立即落库，避免进度丢失
          this.saveHistoryInfo(true)
        }
        if (status == PlayerStatus.DONE && this.appSettings.auto_play_next_episode && this.videoDetailInfo.episodes) {
          const episodeList = this.videoDetailInfo.episodes[this.episodeListIndex];
          if (this.episodeIndex < episodeList.episodes.length - 1) {
            this.playVideo(this.episodeListIndex, this.episodeIndex + 1);
          }
        }
        if (status == PlayerStatus.IDLE) {
          // 新一轮加载开始（换集/换线路/手动重试重置都会广播 IDLE）：递增尝试序号
          this.playAttemptSeq++
        }
        if (status == PlayerStatus.ERROR) {
          this.invalidateCurrentEpisodeLink();
          this.tryNextRouteOnFailure();
        }
        this.syncPiPAutoStart(status)
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
    onVideoFitChanged: (videoFit: VideoFit): void => {
      this.videoFit = videoFit;
    },
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

  /** 播放尝试序号：playVideo 新尝试 / IDLE 广播（手动重试等新加载）时递增 */
  private playAttemptSeq: number = 0
  /** 已消费过自动换线路的尝试序号：同一尝试的重复 ERROR 只处理一次 */
  private failoverAttemptSeq: number = -1
  /** 本次播放尝试的续播起点（毫秒，-1 表示从头）：解析阶段失败时播放器位置不可信，用它代替 */
  private playAttemptStartPos: number = -1
  /** 本次播放尝试是否已到达播放器（playEpisodeList 已调用）：决定换线路时取哪个位置 */
  private attemptReachedPlayer: boolean = false
  /** 页面已销毁：拦截退出详情页后仍在途的解析回调/换线路重试，防止后台继续请求 */
  private destroyed: boolean = false

  /**
   * 播放出错时失效当前集的解析结果（episode 直链 + 历史记录 + WebVideoResolver 缓存）：
   * 直链多为带时效的签名地址，播放失败大概率已过期；
   * 清空后重试会重新走 playVideo 解析分支（缓存条目已删，resolve 必然重新解析）
   */
  private invalidateCurrentEpisodeLink(): void {
    const episodeList = this.videoDetailInfo.episodes[this.episodeListIndex];
    if (episodeList) {
      const episode = episodeList.episodes[this.episodeIndex];
      if (episode && episode.videoUrl) {
        Logger.e('tips', `播放出错，失效当前集解析结果: ${episode.videoUrl}`);
        WebVideoResolver.invalidateResolved(episode.videoUrl);
        episode.videoUrl = undefined;
      }
    }
    if (this.historyInfo) {
      this.historyInfo.videoUrl = '';
    }
  }

  /**
   * 播放/解析失败自动换线路：ERROR 可能重复上报（后端多次回调、解析失败也经 setStatus(ERROR)），
   * 用尝试序号保证同一播放尝试只处理一次（换集/换线路/手动重试都会开启新尝试）；
   * 从当前线路向后寻找存在当前集的第一条线路，以合适的进度续播；
   * 无可用线路时提示切换数据源
   */
  private tryNextRouteOnFailure(): void {
    if (this.destroyed) {
      return
    }
    if (this.failoverAttemptSeq >= this.playAttemptSeq) {
      return
    }
    this.failoverAttemptSeq = this.playAttemptSeq
    const episodeLists = this.videoDetailInfo.episodes
    const episodeIndex = this.episodeIndex
    for (let listIndex = this.episodeListIndex + 1; listIndex < episodeLists.length; listIndex++) {
      const list = episodeLists[listIndex]
      if (list && list.episodes && episodeIndex < list.episodes.length) {
        // 已到播放器的失败用实时位置续播；解析阶段失败用本次尝试的续播起点（播放器位置还是上一集的，不可信）
        const pos = this.attemptReachedPlayer ? this.playerManager.getCurrentPosition() : this.playAttemptStartPos
        this.resumePosition = pos > 0 ? pos : -1
        const routeName = list.title ? list.title : `线路${listIndex + 1}`
        ToastUtil.showToast({ message: `当前线路播放失败，已切换至「${routeName}」` })
        Logger.e('tips', `播放失败自动换线路: ${this.episodeListIndex} -> ${listIndex} episodeIndex=${episodeIndex} pos=${pos}`)
        this.playVideo(listIndex, episodeIndex)
        return
      }
    }
    ToastUtil.showToast({ message: '播放失败，请尝试切换数据源' })
    this.playerManager.setErrorMessage('播放失败，请尝试切换数据源')
  }

  // 初始化数据
  public async initialize(params: VideoNavigateInfo) {
    // 进入详情页立即应用详情页系统栏样式（浅色下中性灰图标）：
    // 播放区背景为黑色，若等详情加载完成才设置，期间黑色图标在黑底上不可见
    SystemBarUtils.setWindowSystemBarTransparent(true);
    this.url = params.url as string;
    this.videoID = params.id;
    this.title = params.title;
    this.sourceKey = params.sourceKey as string;

    if (this.videoID !== null) {
      this.isFirstPlay = false;
    }

    await this.checkVideoInfo();
    // 画中画恢复进入：以小窗实时进度覆盖历史进度续播
    if (params.isPiPRestore && params.pipPosition && params.pipPosition > 0) {
      this.historyInfo.currentTime = params.pipPosition;
    }
    this.getDetailInfo();
    this.checkCollectionInfo();
  }

  /**
   * 换源：原地切换到同名的其他源播放。
   * 以当前集索引与播放进度作为新源的续播对齐提示（新源有自己的历史记录时以历史为准），
   * 并清空跨源残留的历史/收藏/视频ID（initialize 未命中时不会覆盖这些字段）。
   */
  public async switchSource(params: VideoNavigateInfo) {
    const hint: VideoHistoryInfo = {
      id: null,
      link: '',
      title: '',
      totalTime: this.historyInfo.totalTime,
      currentTime: this.historyInfo.currentTime,
      coverUrl: '',
      episodeListIndex: this.historyInfo.episodeListIndex,
      episodeIndex: this.historyInfo.episodeIndex,
      episodeName: this.historyInfo.episodeName,
      videoUrl: '',
      videoProgress: 0,
      sourceKey: '',
      accessTime: Date.now()
    };
    this.historyInfo = hint;
    this.videoID = null;
    this.collectID = 0;
    this.isCollect = false;
    this.collectionInfo = {
      id: null,
      link: '',
      title: '',
      coverUrl: '',
      sourceKey: '',
      accessTime: 0
    };
    this.resumePosition = -1;
    this.errorMessage = '';
    await this.initialize(params);
  }

  // 获取视频详情
  public async getDetailInfo() {
    this.state = ViewState.LOADING
    // 从进入详情页即进入解析态：控制面板显示加载圈，覆盖详情加载→链接解析→播放器就绪全程
    this.playerManager.notifyParseState(true);
    try {
      // 获取视频详情
      console.log(`VideoDetailViewModel.playVideo 等待获取视频详情的链接，url：${this.url}`)
      const info = await dataSourceManager.getVideoDetailInfo(this.url, this.appSettings.episodes_order, this.sourceKey)
      this.videoDetailInfo = info;
      // 同步当前播放媒体信息到全局状态，供投播元数据展示
      AnimeState.playingTitle = this.videoDetailInfo.title
      AnimeState.playingCoverUrl = this.videoDetailInfo.coverUrl
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
      this.playerManager.notifyParseState(false);
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
    if (this.destroyed) {
      return
    }
    Logger.e('tips', `playVideo episodeListIndex = ${episodeListIndex} episodeIndex=${episodeIndex}`);
    // 源级广告拦截开关：优先于全局设置，null=该源未配置、跟随全局
    M3u8AdFilter.setSourceAdFilter(dataSourceManager.getSourceAdFilter(this.sourceKey));
    // 新播放接管：关闭仍在活跃的小窗，防止双音频
    if (PiPManager.isActive) {
      PiPManager.stopPiP()
    }
    this.episodeListIndex = episodeListIndex;
    this.episodeIndex = episodeIndex;
    // 读取并复位续播位置（仅首次进入详情页时为有效值）
    const startPos = this.resumePosition;
    this.resumePosition = -1;
    // 记录本次尝试的续播起点与阶段标记：解析阶段失败时换线路用它续播（不用播放器实时位置）
    this.playAttemptStartPos = startPos
    this.attemptReachedPlayer = false
    this.playAttemptSeq++

    const episodeList = this.videoDetailInfo.episodes[this.episodeListIndex];
    const episode = episodeList.episodes[this.episodeIndex];

    this.historyInfo.episodeListIndex = episodeListIndex;
    this.historyInfo.episodeIndex = episodeIndex;
    this.historyInfo.episodeName = episode.title;
    this.historyInfo.videoUrl = episode.videoUrl as string;

    if (episode.videoUrl) {
      // 链接已就绪：立即预热广告过滤（播放列表抓取与后续准备工作重叠）。
      // 解析态不再在此收口，改由 setPlayerUrl 置 IDLE 后收口，
      // 避免解析结束→播放器接管之间（历史保存/记录查询期间）加载圈熄灭
      M3u8AdFilter.prewarm(episode.videoUrl as string);
      await this.saveHistoryInfo(true);
      await this.checkVideoInfo();
      if (this.destroyed) {
        return
      }
      this.syncPiPSnapshot(episodeListIndex, episodeIndex, episode, startPos);
      this.attemptReachedPlayer = true
      this.playerManager.playEpisodeList(episodeList.episodes, this.episodeIndex, startPos);
    } else {
      // 解析期间通知控制面板显示加载圈（与播放状态解耦，切集解析时也能看到反馈）
      this.playerManager.notifyParseState(true);
      try {
        console.log(`VideoDetailViewModel.playVideo 视频剧集链接，link：${episode.link}`)
        let url = await dataSourceManager.parseVideoUrl(episode.link, this.sourceKey)
        // 解析期间退出页面：丢弃结果，不再喂给已销毁的播放器
        if (this.destroyed) {
          return
        }
        console.log(`VideoDetailViewModel.playVideo 视频播放链接解析成功，url：${url}`)
        // 检查链接是否需要js
        const finalUrl = await this.checkParesVideoLink(url)
        episode.videoUrl = finalUrl
        this.historyInfo.videoUrl = finalUrl
        // 解析完成即预热广告过滤：播放列表抓取与历史保存/记录查询重叠
        M3u8AdFilter.prewarm(finalUrl);
        await this.saveHistoryInfo(true);
        await this.checkVideoInfo();
        if (this.destroyed) {
          return
        }
        this.syncPiPSnapshot(episodeListIndex, episodeIndex, episode, startPos);
        this.attemptReachedPlayer = true
        this.playerManager.playEpisodeList(episodeList.episodes, this.episodeIndex, startPos)
      } catch (err) {
        // 解析期间退出页面：静默终止，不再提示/换线路
        if (this.destroyed) {
          return
        }
        // 用户取消手动模态等均视为本线路解析失败：正常走换线路逻辑
        this.playerManager.notifyParseState(false);
        this.playerManager.setErrorMessage('播放地址解析失败，请重试或换线路');
        this.playerManager.setStatus(PlayerStatus.ERROR);
        // 解析失败时上个尝试可能残留 ERROR 态导致 setStatus 被同状态去重、广播不会到达监听器，
        // 这里直调换线路（监听器路径再触发时会被尝试序号去重）
        this.tryNextRouteOnFailure();
        Logger.e('fail', `VideoDetailViewModel.playVideo 视频链接解析`, err);
      }
    }
  }

  /** 同步 PiP 播放现场快照（退后台系统自动拉起小窗时接管播放用） */
  private syncPiPSnapshot(listIndex: number, epIndex: number, episode: EpisodeInfo, startPos: number): void {
    PiPManager.playbackSnapshot = {
      url: (episode.videoUrl as string) ?? '',
      detailUrl: this.url,
      videoId: this.videoID,
      position: startPos > 0 ? startPos : 0,
      speed: this.playerManager.getSpeed(),
      episodeListIndex: listIndex,
      episodeIndex: epIndex,
      episodeName: episode.title,
      title: this.videoDetailInfo.title,
      coverUrl: this.videoDetailInfo.coverUrl,
      sourceKey: this.sourceKey,
    }
  }

  /**
   * 检查并解析视频链接
   * 含 _|_ 的网页解析源统一委托全局 WebVideoResolver（串行队列 + 内存缓存 + 自动/手动兜底），
   * 与离线缓存下载共用同一条解析通道，播放解析过一次后下载可直接复用缓存；
   * 普通链接原样返回
   * @param url 输入的URL，格式可能为 'rawLink_|_js' 或直接的URL
   * @returns Promise<string> 返回解析后的视频链接
   */
  private async checkParesVideoLink(url: string): Promise<string> {
    return WebVideoResolver.resolve(url)
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
  public async onPageShow() {
    // 进播放页保持屏幕常亮（暂停时由状态联动关闭）
    this.playerManager.setKeepScreenOn(true)
    // 从叠放页面返回时恢复详情页系统栏样式（onPageHide 已还原为默认样式）
    SystemBarUtils.setWindowSystemBarTransparent(true);
    // 刷新 PiP 委托指向（叠放页面返回后保证指向当前显示页）
    this.registerPiPDelegates()
    this.stackSizeOnShown = AnimeState.pageStack.size()
    // 关闭"自动旋屏"时在视频页锁定竖屏，旋转手机不再改变窗口方向
    this.applyOrientationLock();
    // 后台自动小窗场景回到前台：收回播放权，以小窗进度续播
    if (PiPManager.isActive) {
      const pos = PiPManager.getPlaybackPosition()
      await PiPManager.stopPiP()
      await this.recoverFromPiP(pos)
      return
    }
    if (this.pausedOnHide) {
      if (!this.playerManager.isPlaying()) {
        await this.playerManager.start();
      }
      this.pausedOnHide = false;
    }
  }

  /** 从 PiP 收回播放：以小窗最新进度恢复主播放器 */
  private async recoverFromPiP(pos: number): Promise<void> {
    try {
      if (!this.playerManager.isPlaying()) {
        await this.playerManager.start()
      }
      if (pos > 0) {
        await this.playerManager.seekTo(pos)
      }
    } catch (err) {
      Logger.e('fail', 'recoverFromPiP 恢复播放', err)
    }
    this.pausedOnHide = false
  }

  // 处理页面隐藏
  public async onPageHide() {
    // 离开播放页恢复系统默认息屏策略
    this.playerManager.setKeepScreenOn(false)
    this.restoreOrientation();
    // 任何路径离开详情页（返回键/页面内返回/手势）都恢复默认系统栏样式
    SystemBarUtils.setWindowSystemBarTransparent(false);
    await this.saveHistoryInfo(true);
    ToastUtil.showToast({ message: '历史记录已保存' });
    // 触发历史记录更新事件
    HISTORY_CHANGED_EVENT.emit();

    if (this.playerManager.isPlaying()) {
      // 页面内导航离开（push 新页）按设置自动进小窗；退后台由 setAutoStartEnabled 系统自动拉起
      if (this.appSettings.auto_pip_on_exit
        && PiPManager.isPlayerSupported(this.appSettings.default_player)
        && !PiPManager.isActive
        && AnimeState.pageStack.size() > this.stackSizeOnShown) {
        await this.enterPiPMode(false)
      }
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
    this.destroyed = true;
    // 取消仍在途的 WebView 解析（退出页面后不再弹手动模态、不再继续轮询）
    WebVideoResolver.cancelActive();
    this.restoreOrientation();
    PLAYER_SWITCH_EVENT.off()
    this.playerManager.destroy();
    // 清理 PiP 委托与快照（页面重新显示时由 onPageShow 重新注册）
    if (this.pipRequestHandler && PiPManager.requestHandler === this.pipRequestHandler) {
      PiPManager.requestHandler = null
    }
    PiPManager.mainPositionProvider = null
    PiPManager.mainPlayerPauser = null
    PiPManager.onPipError = null
    PiPManager.playbackSnapshot = null
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

    // 退出播放页自动小窗（仅支持的播放器后端）
    if (this.appSettings.auto_pip_on_exit
      && PiPManager.isPlayerSupported(this.appSettings.default_player)
      && this.playerManager.isPlaying()) {
      this.enterPiPMode(true)
      return true
    }

    return false;
  }

  /**
   * 进入画中画小窗
   * @param pop true=返回键/手动按钮（成功后弹出当前页）；false=页面内导航离开（页面保留在栈内）
   */
  private async enterPiPMode(pop: boolean): Promise<void> {
    // 小窗触发基本条件：视频正在播放
    if (!this.playerManager.isPlaying()) {
      if (pop) {
        ToastUtil.showToast({ message: '播放视频后才能使用小窗' })
      }
      return
    }
    const episodeList = this.videoDetailInfo.episodes[this.episodeListIndex]
    const episode = episodeList?.episodes[this.episodeIndex]
    if (!episode || !episode.videoUrl) {
      if (pop) {
        ToastUtil.showToast({ message: '暂无法获取小窗播放内容' })
      }
      return
    }
    const pos = this.playerManager.getCurrentPosition()
    const info: PiPNavigationInfo = {
      url: episode.videoUrl as string,
      detailUrl: this.url,
      videoId: this.videoID,
      position: pos > 0 ? pos : 0,
      speed: this.playerManager.getSpeed(),
      episodeListIndex: this.episodeListIndex,
      episodeIndex: this.episodeIndex,
      episodeName: episode.title,
      title: this.videoDetailInfo.title,
      coverUrl: this.videoDetailInfo.coverUrl,
      sourceKey: this.sourceKey,
    }
    const success = await PiPManager.startPiP(info)
    if (success) {
      // 主播放器立即让位，避免与小窗短暂双声
      await this.playerManager.pause()
      if (pop) {
        ToastUtil.showToast({ message: '已进入小窗播放' })
        AnimeState.popPage(true)
      }
    } else if (pop) {
      ToastUtil.showToast({ message: '小窗启动失败' })
    }
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
