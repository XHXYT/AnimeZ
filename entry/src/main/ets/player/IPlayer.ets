import { media } from "@kit.MediaKit";

export  interface IPlayer {

    setDataSource(url: string): Promise<void>;

    prepare(): Promise<void>;

    start(): Promise<void>;

    stop(): Promise<void>;

    pause(): Promise<void>;

    reset(): Promise<void>;

    release(): Promise<void>;

    seekTo(msec: string): Promise<void>;

    setSpeed(speed: media.PlaybackSpeed): Promise<void>;

}

export class nullIPlayer implements IPlayer {
    async setDataSource(url: string): Promise<void> {
        // 不执行任何操作
    }

    async prepare(): Promise<void> {
        // 不执行任何操作
    }

    async start(): Promise<void> {
        // 不执行任何操作
    }

    async stop(): Promise<void> {
        // 不执行任何操作
    }

    async pause(): Promise<void> {
        // 不执行任何操作
    }

    async reset(): Promise<void> {
        // 不执行任何操作
    }

    async release(): Promise<void> {
        // 不执行任何操作
    }

    async seekTo(msec: string): Promise<void> {
        // 不执行任何操作
    }

    async setSpeed(speed: media.PlaybackSpeed): Promise<void> {
        // 不执行任何操作
    }
}







