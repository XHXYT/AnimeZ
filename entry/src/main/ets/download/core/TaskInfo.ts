import { Column } from '../../db/decorator/Decorators';
import { TaskStatus } from './Task';


/**
 * 任务信息
 */
export default class TaskInfo {

    /**
     * 任务id
     */
    @Column({
        name: 'taskId',
        type: 'INTEGER',
        isPrimaryKey: true,
        autoIncrement: true,
        notNull: true
    })
    readonly taskId: number;

    /**
     * 父任务id
     */
    @Column({
        name: 'parentTaskId',
        type: 'INTEGER',
        notNull: true
    })
    readonly parentTaskId: number

    /**
     * 任务名
     */
    @Column({
        name: 'taskName',
        type: 'TEXT',
        notNull: true
    })
    taskName: string

    /**
     * 任务状态
     */
    @Column({
        name: 'status',
        type: 'INTEGER',
        notNull: true
    })
    status: number = TaskStatus.CREATED

    /**
     * 总任务量
     */
    @Column({
        name: 'totalSize',  // 映射到数据库的 totalSize
        type: 'INTEGER',
        notNull: true
    })
    totalWorkload: number = 0;

    /**
     * 已完成(已接收)任务量
     */
    @Column({
        name: 'receivedSize',  // 映射到数据库的 receivedSize
        type: 'INTEGER',
        notNull: true
    })
    completeWorkload: number = 0;

    /**
     * 任务进度
     */
    @Column({
        name: 'taskProgress',
        type: 'INTEGER',
        notNull: true
    })
    taskProgress: number = 0;

    /**
     * 任务创建时间
     */
    @Column({
        name: 'createTime',
        type: 'INTEGER',
        notNull: true
    })
    createTime: number = 0

    /**
     * 任务完成时间
     */
    @Column({
        name: 'finishedTime',
        type: 'INTEGER'
    })
    finishedTime: number = 0

    /**
     * 任务是否准备完成
     */
    @Column({
        name: 'prepared',
        type: 'BOOLEAN',
        notNull: true
    })
    prepared: boolean = false;

    /**
     * 任务信息，一般用于保存错误信息
     */
    // TODO 这个属性可能不需要存储到数据库，暂时不加 @Column
    message: string = null;

    /**
     * 任务请求头信息，可用于自定义任务信息
     */
    // TODO 这个属性是Object类型，可能需要特殊处理或序列化存储，暂时不加 @Column
    header: Object = null

    constructor(taskId: number, parentTaskId: number, createTime: number = new Date().getTime()) {
        this.taskId = taskId
        this.parentTaskId = parentTaskId
        this.createTime = createTime
    }
}
