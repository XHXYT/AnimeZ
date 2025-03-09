import { relationalStore, ValuesBucket } from '@kit.ArkData'

// 视频历史记录的类型
// ValuesBucket 数据库类型约束
export interface VideoCollectionInfo extends ValuesBucket {
  id: number | null // 新增时 id 设置为 null ，可实现 id 自增
  // 视频页面链接
  link: string
  title: string
  coverUrl: string
  // 视频源
  sourceKey: string
  // 添加时间
  accessTime: number
}

export const CollectionInfo: VideoCollectionInfo = {
  id: null,
  link: '',
  title: '',
  coverUrl: '',
  sourceKey: '',
  accessTime: Date.now()
}

// 视频收藏数据库封装
class VideoCollectionInfoDB {
  // public        公开的(外部可访问)
  // private       私有的(外部不可访问)
  // constructor() 构造器(new 时候自动运行)

  // 操作数据库的实例(数据库文件)
  private store: relationalStore.RdbStore | null = null
  // 数据库表名
  private tableName = 'video_collection'
  // 创建数据库的语句
  private sqlCreate = `CREATE TABLE IF NOT EXISTS ${this.tableName} (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    link TEXT NOT NULL,
    title TEXT NOT NULL UNIQUE,
    coverUrl TEXT,
    sourceKey TEXT,
    accessTime INTEGER
  )`

  // 获取数据库操作的实例(创建/打开数据库文件)
  private async getStoreInstance() {
    // 如果 store 已保存，直接返回即可（性能优化）
    if (this.store) {
      return this.store
    }
    // 创建/打开数据库文件
    this.store = await relationalStore.getRdbStore(getContext(), {
      name: 'anime.db', // 数据库文件名
      securityLevel: relationalStore.SecurityLevel.S1 // 安全等级(跨设备共享等级)
    })
    // return 操作数据库的实例
    return this.store
  }

  // 类的构造器，new 的时候会自动触发
  constructor() {
    // 创建/打开数据库文件
    this.getStoreInstance()
      .then(store => {
        // 执行 sql 语句，用于创建数据库的表
        store.executeSql(this.sqlCreate)
      })
  }

  // 新增数据
  async insert(value: VideoCollectionInfo) {
    // 创建/打开数据库文件
    const store = await this.getStoreInstance()
    // 新增数据(表名, 数据)
    return store.insert(this.tableName, value)
  }

  // 查询数据
  async query(title?: string) {
    // 创建/打开数据库文件
    const store = await this.getStoreInstance()
    // 谓词(条件)
    const predicates = new relationalStore.RdbPredicates(this.tableName)
     if (title) {
      // 如果有 title，就根据 title 查找
      predicates.equalTo('title', title)
    } else  {
       console.log('VideoCollectionTest 查询全部收藏数据')
       predicates.orderByDesc('accessTime') // 时间倒序：由大到小
    }
    // 根据谓词排序
    const resultSet = await store.query(predicates)
    // 准备对象数组
    const list: VideoCollectionInfo[] = []
    // 指针移动到下一行
    while (resultSet.goToNextRow()) {
      // 获取当前行的数据
      const item = resultSet.getRow() as VideoCollectionInfo
      // 数据追加
      list.push(item)
    }
    // 释放结果集，释放资源（性能优化）
    resultSet.close()
    // 循环结束后，返回数组
    return list
  }

  // 查询数据总数
  async querySum() {
    const store = await this.getStoreInstance()
    // 谓词(条件)
    const predicates = new relationalStore.RdbPredicates(this.tableName)
    predicates.orderByDesc('id') // 倒序：由大到小
    const resultSet = await store.query(predicates)
    // 返回表中的数据总数
    return resultSet.rowCount as number
  }

  // 删除
  async delete(id: number | null) {
    // 创建/打开数据库文件
    const store = await this.getStoreInstance()
    // 谓词条件
    const predicates = new relationalStore.RdbPredicates(this.tableName)
    // 匹配 id 用于删除
    predicates.equalTo('id', id)
    // 删除
    return store.delete(predicates)
  }

  // 修改
  async update(value: VideoCollectionInfo) {
    if (!value.id) {
      return Promise.reject()
    }
    // 创建/打开数据库文件
    const store = await this.getStoreInstance()
    // 谓词条件
    const predicates = new relationalStore.RdbPredicates(this.tableName)
    // 匹配 id 用于更新
    predicates.equalTo('id', value.id)
    // 更新
    return store.update(value, predicates)
  }

}

// 通过小写 v 开头的类实例操作数据库，创建数据库，建表，增、删、查、改
export const videoCollectionInfoDB = new VideoCollectionInfoDB()