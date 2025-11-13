import { Column } from '../db/decorator/Decorators';
import TaskInfo from './core/TaskInfo';

/**
 * 下载任务信息
 */
export default class DownloadTaskInfo extends TaskInfo {

    /**
     * 文件名
     * taskName作为用户创建的任务名，fileName则作为此任务保存的文件名
     */
    @Column({
        name: 'fileName',
        type: 'TEXT',
        notNull: true
    })
    fileName: string

    /**
     * 文件下载目录
     */
    @Column({
        name: 'downloadDir',
        type: 'TEXT',
        notNull: true
    })
    downloadDir: string

    /**
     * 原始下载链接
     */
    @Column({
        name: 'originalUrl',
        type: 'TEXT',
        notNull: true
    })
    originalUrl: string

    /**
     * 最新的下载链接，可能和originalUrl相同，也可能是originalUrl重定向的链接
     */
    @Column({
        name: 'url',
        type: 'TEXT',
        notNull: true
    })
    url: string

    /**
     * 下载内容偏移量，主要用于分片下载，默认为0无偏移量
     */
    @Column({
        name: 'offset',
        type: 'INTEGER',
        notNull: true
    })
    offset: number = 0

    /**
     * 文件内容大小
     */
    @Column({
        name: 'contentLength',
        type: 'INTEGER'
    })
    contentLength: number = -1

    /**
     * 是否支持分片下载
     */
    @Column({
        name: 'blockDownload',
        type: 'BOOLEAN',
        notNull: true
    })
    blockDownload: boolean = false

    /**
     * 缓冲大小
     */
    // 注意：这是运行时配置，不需要存储到数据库
    bufferSize: number = 512 * 1024

    constructor(taskId: number, parentTaskId: number, createTime: number = new Date().getTime()) {
        super(taskId, parentTaskId, createTime)
    }
}
