
import { Column } from '../db/decorator/Decorators';


export default class VideoCollectionInfo {

  @Column({
    name: 'id',
    type: 'INTEGER',
    isPrimaryKey: true,
    autoIncrement: true
  })
  id: number | null = null

  // 视频页面链接
  @Column({ name: 'link', type: 'TEXT', notNull: true })
  link: string = ''

  @Column({ name: 'title', type: 'TEXT', notNull: true })
  title: string = ''

  @Column({ name: 'coverUrl', type: 'TEXT', notNull: true })
  coverUrl: string = ''

  @Column({ name: 'sourceKey', type: 'TEXT', notNull: true })
  sourceKey: string = ''

  @Column({ name: 'accessTime', type: 'INTEGER', notNull: true })
  accessTime: number = 0

  constructor(link: string, title: string = '', coverUrl: string = '', sourceKey: string = '', accessTime: number = Date.now()) {
    this.link = link;
    this.title = title;
    this.coverUrl = coverUrl;
    this.sourceKey = sourceKey;
    this.accessTime = accessTime;
  }

}
