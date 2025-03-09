import { IPlayer } from './IPlayer';
import Logger from '../utils/Logger';
/*
 * Copyright (C) 2022 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import { AudioInterrupt, InterruptEvent, OnPreparedListener } from "@ohos/ijkplayer";
import { OnCompletionListener } from "@ohos/ijkplayer";
import { OnVideoSizeChangedListener } from "@ohos/ijkplayer";
import { OnBufferingUpdateListener } from "@ohos/ijkplayer";
import { OnErrorListener } from "@ohos/ijkplayer";
import { OnInfoListener } from "@ohos/ijkplayer";
import { OnSeekCompleteListener } from "@ohos/ijkplayer";
import { OnTimedTextListener } from "@ohos/ijkplayer";
import { MessageType } from "@ohos/ijkplayer";
import { PropertiesType } from "@ohos/ijkplayer";
import { LogUtils } from "@ohos/ijkplayer";
import window from '@ohos.window';
import { BusinessError } from '@kit.BasicServicesKit';
import { IjkPlayerNapi } from '@ohos/ijkplayer/src/main/ets/ijkplayer/utils/IjkPlayerNapi';

/**
 * 将@ohos/ijkplayer中IjkMediaPlayer源码copy过来并去除原始代码中的单例及ijkplayer_audio_napi相关
 */
export class IjkMediaPlayer {
  private static instance: IjkMediaPlayer;
  public static OPT_CATEGORY_FORMAT: string = "1";
  public static OPT_CATEGORY_CODEC: string = "2";
  public static OPT_CATEGORY_SWS: string = "3";
  public static OPT_CATEGORY_PLAYER: string = "4";
  private mVideoWidth: number = 0;
  private mVideoHeight: number = 0;
  private mVideoSarNum: number = 0;
  private mVideoSarDen: number = 0;
  private mOnVideoSizeChangedListener: OnVideoSizeChangedListener | null = null;
  private mOnPreparedListener: OnPreparedListener | null = null;
  private mOnCompletionListener: OnCompletionListener | null = null;
  private mOnBufferingUpdateListener: OnBufferingUpdateListener | null = null;
  private mOnErrorListener: OnErrorListener | null = null;
  private mOnInfoListener: OnInfoListener | null = null;
  private mOnSeekCompleteListener: OnSeekCompleteListener | null = null;
  private mOnTimedTextListener: OnTimedTextListener | null = null;
  private ijkplayer_napi: IjkPlayerNapi | null = null;
  private id: string = '';
  private callback: Callback<InterruptEvent> | null = null;

  public constructor(id?: string) {
    if (id) {
      this.id = id;
    }
  };

  public static getInstance(): IjkMediaPlayer {
    if (!IjkMediaPlayer.instance) {
      IjkMediaPlayer.instance = new IjkMediaPlayer();
    }
    return IjkMediaPlayer.instance;
  }

  isInit(): boolean {
    return this.ijkplayer_napi ? true : false
  }

  setContext(context: IjkPlayerNapi, id?: string): void {
    this.ijkplayer_napi = context
    if(id) {
      this.id = id
    }
  }

  setAudioId(id: string) {
    // this.ijkplayer_audio_napi = new newIjkPlayerAudio(id, false)
    this.id = id
  }

  setDebug(open: boolean): void {
    LogUtils.getInstance().setLogSwitch(open);
    if (open && !!this.ijkplayer_napi) {
      this.ijkplayer_napi._nativeOpenlog(this.id);
    }
  }

  setDataSource(url: string): void {
    if (!!this.ijkplayer_napi) {
      this.ijkplayer_napi._setDataSource(this.id, url)
    }
  }

  setDataSourceHeader(headers: Map<string, string>): void {
    if (headers) {
      let builder: string = '';
      headers.forEach((value, key) => {
        let param = key.trim() + ":";
        if (value)
          param += value.trim();
        param += "\r\n";
        builder += param;
      });
      if (!!this.ijkplayer_napi) {
        this.ijkplayer_napi._setOption(this.id, IjkMediaPlayer.OPT_CATEGORY_FORMAT, "headers", builder);
        this.ijkplayer_napi._setOption(this.id, IjkMediaPlayer.OPT_CATEGORY_FORMAT, "protocol_whitelist", "async,cache,crypto,file,http,https,ijkhttphook,ijkinject,ijklivehook,ijklongurl,ijksegment,ijktcphook,pipe,rtp,tcp,tls,udp,ijkurlhook,data");
      }
    }
  }

  setOption(category: string, key: string, value: string): void {
    if (!!this.ijkplayer_napi) {
      this.ijkplayer_napi._setOption(this.id, category, key, value);
    }
  }

  setOptionLong(category: string, key: string, value: string): void {
    if (!!this.ijkplayer_napi) {
      this.ijkplayer_napi._setOptionLong(this.id, category, key, value);
    }
  }

  prepareAsync(): void {
    if (!!this.ijkplayer_napi) {
      this.ijkplayer_napi._prepareAsync(this.id);
    }
  }

  start(): void {
    if (!!this.ijkplayer_napi) {
      this.ijkplayer_napi._start(this.id);
    }
  }

  stop(): void {
    if (!!this.ijkplayer_napi) {
      this.ijkplayer_napi._stop(this.id);
    }
  }

  pause(): void {
    if (!!this.ijkplayer_napi) {
      this.ijkplayer_napi._pause(this.id);
    }
  }

  reset(): void {
    if (!!this.ijkplayer_napi) {
      this.ijkplayer_napi._reset(this.id);
    }
  }

  release(): void {
    if (!!this.ijkplayer_napi) {
      this.ijkplayer_napi._release(this.id);
    }
  }

  seekTo(msec: string): void {
    if (!!this.ijkplayer_napi) {
      this.ijkplayer_napi._seekTo(this.id, msec);
    }
  }

  setScreenOnWhilePlaying(on: boolean): void {
    window.getLastWindow(getContext(this)).then((data: window.Window) => {
      if (data) {
        data.setWindowKeepScreenOn(on);
      }
    }).catch((err: BusinessError) => {
      LogUtils.getInstance().LOGI(`getLastWindow error: ${JSON.stringify(err)}`);
    });
  }

  setSpeed(speed: string): void {
    this._setPropertyFloat(PropertiesType.FFP_PROP_FLOAT_PLAYBACK_RATE, speed);
  }

  getSpeed(): number {
    return this._getPropertyFloat(PropertiesType.FFP_PROP_FLOAT_PLAYBACK_RATE, "0");
  }

  isPlaying(): boolean {
    if (!!this.ijkplayer_napi) {
      return this.ijkplayer_napi._isPlaying(this.id);
    }
    else {
      return false
    }
  }

  public on(type: AudioInterrupt,  callback: Callback<InterruptEvent>) : void {
    this.callback= callback;
  }

  public off(type: AudioInterrupt): void {
    this.callback = null;
  }

  setOnVideoSizeChangedListener(listener: OnVideoSizeChangedListener): void {
    this.mOnVideoSizeChangedListener = listener;
  }

  setOnPreparedListener(listener: OnPreparedListener): void {
    this.mOnPreparedListener = listener;
  }

  setOnCompletionListener(listener: OnCompletionListener): void {
    this.mOnCompletionListener = listener;
  }

  setOnInfoListener(listener: OnInfoListener): void {
    this.mOnInfoListener = listener;
  }

  setOnErrorListener(listener: OnErrorListener): void {
    this.mOnErrorListener = listener;
  }

  setOnBufferingUpdateListener(listener: OnBufferingUpdateListener): void {
    this.mOnBufferingUpdateListener = listener;
  }

  setOnSeekCompleteListener(listener: OnSeekCompleteListener): void {
    this.mOnSeekCompleteListener = listener;
  }

  setOnTimedTextListener(listener: OnTimedTextListener): void {
    this.mOnTimedTextListener = listener;
  }

  setMessageListener(): void {
    LogUtils.getInstance().LOGI("setMessageListener start");
    let that = this;
    let onVideoSizeChangedListener = this.mOnVideoSizeChangedListener;
    let onPreparedListener = this.mOnPreparedListener;
    let onCompletionListener = this.mOnCompletionListener;
    let onBufferingUpdateListener = this.mOnBufferingUpdateListener;
    let onErrorListener = this.mOnErrorListener;
    let onInfoListener = this.mOnInfoListener;
    let onSeekCompleteListener = this.mOnSeekCompleteListener;
    let onTimedTextListener = this.mOnTimedTextListener;
    let messageCallBack = (what: number, arg1: number, arg2: number, obj: string) => {
      LogUtils.getInstance()
        .LOGI("setMessageListener callback what:" + what + ", arg1:" + arg1 + ",arg2:" + arg2 + ",obj:" + obj);
      if (what == MessageType.MEDIA_PREPARED) {
        if (onPreparedListener !== null)
          onPreparedListener.onPrepared();
      }
      if (what == MessageType.MEDIA_SET_VIDEO_SAR) {
        if (arg1 != undefined && arg2 != undefined) {
          that.mVideoSarNum = arg1;
          that.mVideoSarDen = arg2;
        }
      }
      if (what == MessageType.MEDIA_SET_VIDEO_SIZE && onVideoSizeChangedListener != null) {
        onVideoSizeChangedListener.onVideoSizeChanged(arg1, arg2, that.mVideoSarNum, that.mVideoSarDen);
        if (arg1 != 0 && arg2 != 0) {
          that.mVideoWidth = arg1;
          that.mVideoHeight = arg2;
        }
      }

      if (what == MessageType.MEDIA_PLAYBACK_COMPLETE && onCompletionListener != null) {
        onCompletionListener.onCompletion();
      }

      if ((!!that.ijkplayer_napi && what == MessageType.MEDIA_BUFFERING_UPDATE && onBufferingUpdateListener != null) ||
        (what == MessageType.MEDIA_BUFFERING_UPDATE && onBufferingUpdateListener != null)) {
        let bufferPosition = arg1;
        if (bufferPosition < 0) {
          bufferPosition = 0;
        }
        let percent = 0;
        let duration: number | undefined = 0
        if (!!this.ijkplayer_napi) {
          duration = that.ijkplayer_napi?._getDuration(this.id);
        }
        if (typeof duration === 'number' && duration > 0) {
          percent = bufferPosition * 100 / duration;
        }
        if (percent >= 100) {
          percent = 100;
        }
        onBufferingUpdateListener.onBufferingUpdate(percent);
      }

      if (what == MessageType.MEDIA_ERROR && onErrorListener != null) {
        onErrorListener.onError(arg1, arg2);
      }
      if (what == MessageType.MEDIA_INFO && onInfoListener != null) {
        onInfoListener.onInfo(arg1, arg2);
      }
      if (what == MessageType.MEDIA_SEEK_COMPLETE && onSeekCompleteListener != null) {
        onSeekCompleteListener.onSeekComplete();
      }
      if (what == MessageType.MEDIA_TIMED_TEXT && onTimedTextListener != null) {
        onTimedTextListener.onTimedText(obj);
      }
      if (what == MessageType.MEDIA_AUDIO_INTERRUPT && onCompletionListener != null) {
        if (this.callback){
          let event: InterruptEvent = {
            forceType: arg1,
            hintType: arg2,
          }
          this.callback(event);
        }
      }
    };
    if (!!this.ijkplayer_napi) {
      this.ijkplayer_napi._setMessageListener(this.id, messageCallBack);
    }
  }

  getVideoWidth(): number {
    return this.mVideoWidth;
  }

  getVideoHeight(): number {
    return this.mVideoHeight;
  }

  getVideoSarNum(): number {
    return this.mVideoSarNum;
  }

  getVideoSarDen(): number {
    return this.mVideoSarDen;
  }

  getDuration(): number {
    if (!!this.ijkplayer_napi) {
      return this.ijkplayer_napi._getDuration(this.id);
    }
    else {
      return 0
    }
  }

  getCurrentPosition(): number {
    if (!!this.ijkplayer_napi) {
      return this.ijkplayer_napi._getCurrentPosition(this.id);
    }
    else {
      return 0
    }
  }

  getAudioSessionId(): number {
    if (!!this.ijkplayer_napi) {
      return this.ijkplayer_napi._getAudioSessionId(this.id);
    }
    else {
      return 0
    }
  }

  private _setPropertyFloat(property: string, value: string): void {
    if (!!this.ijkplayer_napi) {
      this.ijkplayer_napi._setPropertyFloat(this.id, property, value);
    }
  }

  private _getPropertyFloat(property: string, value: string): number {
    if (!!this.ijkplayer_napi) {
      return this.ijkplayer_napi._getPropertyFloat(this.id, property, value);
    }
    else {
      return 0
    }
  }

  private _setPropertyLong(property: string, value: string): void {
    if (!!this.ijkplayer_napi) {
      this.ijkplayer_napi._setPropertyLong(this.id, property, value);
    }
  }

  private _getPropertyLong(property: string, value: string): number {
    if (!!this.ijkplayer_napi) {
      return this.ijkplayer_napi._getPropertyLong(this.id, property, value);
    }
    else {
      return 0
    }
  }

  setVolume(leftVolume: string, rightVolume: string): void {
    if (!!this.ijkplayer_napi) {
      this.ijkplayer_napi._setVolume(this.id, leftVolume, rightVolume);
    }
  }

  setLoopCount(looping: boolean): void {
    let loopCount = looping ? "0" : "1";
    this.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "loop", loopCount);
    if (!!this.ijkplayer_napi) {
      this.ijkplayer_napi._setLoopCount(this.id, loopCount);
    }
  }

  isLooping(): boolean {
    let loopCount: number = 0
    if (!!this.ijkplayer_napi) {
      loopCount = this.ijkplayer_napi._getLoopCount(this.id);
    }
    return loopCount != 1;
  }

  selectTrack(track: string): void {
    this._setStreamSelected(track, "true");
  }

  deselectTrack(track: string): void {
    this._setStreamSelected(track, "false");
  }

  private _setStreamSelected(stream: string, select: string): void {
    if (!!this.ijkplayer_napi) {
      this.ijkplayer_napi._setStreamSelected(this.id, stream, select);
    }
  }

  getVideoDecoder(): number {
    return this._getPropertyLong(PropertiesType.FFP_PROP_INT64_VIDEO_DECODER, PropertiesType.FFP_PROPV_DECODER_UNKNOWN);
  }

  getVideoOutputFramesPerSecond(): number {
    return this._getPropertyFloat(PropertiesType.PROP_FLOAT_VIDEO_OUTPUT_FRAMES_PER_SECOND, "0");
  }

  getVideoDecodeFramesPerSecond(): number {
    return this._getPropertyFloat(PropertiesType.PROP_FLOAT_VIDEO_DECODE_FRAMES_PER_SECOND, "0");
  }

  getVideoCachedDuration(): number {
    return this._getPropertyLong(PropertiesType.FFP_PROP_INT64_VIDEO_CACHED_DURATION, "0");
  }

  getAudioCachedDuration(): number {
    return this._getPropertyLong(PropertiesType.FFP_PROP_INT64_AUDIO_CACHED_DURATION, "0");
  }

  getVideoCachedBytes(): number {
    return this._getPropertyLong(PropertiesType.FFP_PROP_INT64_VIDEO_CACHED_BYTES, "0");
  }

  getAudioCachedBytes(): number {
    return this._getPropertyLong(PropertiesType.FFP_PROP_INT64_AUDIO_CACHED_BYTES, "0");
  }

  getVideoCachedPackets(): number {
    return this._getPropertyLong(PropertiesType.FFP_PROP_INT64_VIDEO_CACHED_PACKETS, "0");
  }

  getAudioCachedPackets(): number {
    return this._getPropertyLong(PropertiesType.FFP_PROP_INT64_AUDIO_CACHED_PACKETS, "0");
  }

  getAsyncStatisticBufBackwards(): number {
    return this._getPropertyLong(PropertiesType.FFP_PROP_INT64_ASYNC_STATISTIC_BUF_BACKWARDS, "0");
  }

  getAsyncStatisticBufForwards(): number {
    return this._getPropertyLong(PropertiesType.FFP_PROP_INT64_ASYNC_STATISTIC_BUF_FORWARDS, "0");
  }

  getAsyncStatisticBufCapacity(): number {
    return this._getPropertyLong(PropertiesType.FFP_PROP_INT64_ASYNC_STATISTIC_BUF_CAPACITY, "0");
  }

  getTrafficStatisticByteCount(): number {
    return this._getPropertyLong(PropertiesType.FFP_PROP_INT64_TRAFFIC_STATISTIC_BYTE_COUNT, "0");
  }

  getCacheStatisticPhysicalPos(): number {
    return this._getPropertyLong(PropertiesType.FFP_PROP_INT64_CACHE_STATISTIC_PHYSICAL_POS, "0");
  }

  getCacheStatisticFileForwards(): number {
    return this._getPropertyLong(PropertiesType.FFP_PROP_INT64_CACHE_STATISTIC_FILE_FORWARDS, "0");
  }

  getCacheStatisticFilePos(): number {
    return this._getPropertyLong(PropertiesType.FFP_PROP_INT64_CACHE_STATISTIC_FILE_POS, "0");
  }

  getCacheStatisticCountBytes(): number {
    return this._getPropertyLong(PropertiesType.FFP_PROP_INT64_CACHE_STATISTIC_COUNT_BYTES, "0");
  }

  getFileSize(): number {
    return this._getPropertyLong(PropertiesType.FFP_PROP_INT64_LOGICAL_FILE_SIZE, "0");
  }

  getBitRate(): number {
    return this._getPropertyLong(PropertiesType.FFP_PROP_INT64_BIT_RATE, "0");
  }

  getTcpSpeed(): number {
    return this._getPropertyLong(PropertiesType.FFP_PROP_INT64_TCP_SPEED, "0");
  }

  getSeekLoadDuration(): number {
    return this._getPropertyLong(PropertiesType.FFP_PROP_INT64_LATEST_SEEK_LOAD_DURATION, "0");
  }

  getDropFrameRate(): number {
    return this._getPropertyFloat(PropertiesType.FFP_PROP_FLOAT_DROP_FRAME_RATE, "0");
  }

  setCacheShare(share: string) {
    this._setPropertyLong(PropertiesType.FFP_PROP_INT64_SHARE_CACHE_DATA, share);
  }

  private _getVideoCodecInfo(): string {
    if (!!this.ijkplayer_napi) {
      return this.ijkplayer_napi._getVideoCodecInfo(this.id);
    }
    else {
      return ''
    }
  }

  private _getAudioCodecInfo(): string {
    if (!!this.ijkplayer_napi) {
      return this.ijkplayer_napi._getAudioCodecInfo(this.id);
    }else {
      return ''
    }
  }

  private _getMediaMeta(): string {
    if (!!this.ijkplayer_napi) {
      return this.ijkplayer_napi._getMediaMeta(this.id);
    } else {
      return ''
    }
  }

  getMediaInfo(): object {
    interface mediaInfoType {
      audioDecoder: string
      videoDecoder: string
      meta: string
    }

    let mAudioDecoder = this._getAudioCodecInfo();
    let mVideoDecoder = this._getVideoCodecInfo();
    let mMeta = this._getMediaMeta();
    let mediaInfo: mediaInfoType = { audioDecoder: mAudioDecoder, videoDecoder: mVideoDecoder, meta: mMeta };
    return mediaInfo;
  }

  native_setup(): void {
    if (!!this.ijkplayer_napi) {
      this.ijkplayer_napi._native_setup(this.id);
    }
  }
}

