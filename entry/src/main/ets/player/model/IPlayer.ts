import { media } from "@kit.MediaKit";

export  interface IPlayer {

    setDataSource: (url: string) => Promise<void>

    prepare: () => Promise<void>

    start: () => Promise<void>

    stop: () => Promise<void>

    pause:() => Promise<void>

    reset: () => Promise<void>

    release: () => Promise<void>

    seekTo: (msec: number) => Promise<void>

    /** 设置播放倍速（实际倍率数值，如 0.75 / 1.0 / 2.0 / 3.0） */
    setSpeed: (speed: number) => Promise<void>

}









