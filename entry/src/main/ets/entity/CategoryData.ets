import { BaseDataSource } from '../viewmodel/BaseDataSource'
import { DramaList } from './HomepageData'
import VideoInfo from './VideoInfo'

// 目录数据
export class CategoryDataSource extends BaseDataSource<VideoInfo> {
  private dataArray: VideoInfo[] = []

  public totalCount(): number {
    return this.dataArray.length
  }

  public getData(index: number): VideoInfo {
    return this.dataArray[index]
  }

  public getTotalData(): VideoInfo[] {
    return this.dataArray
  }

  public addData(index: number, data: VideoInfo): void {
    this.dataArray.splice(index, 0, data)
    this.notifyDataAdd(index)
  }

  public pushData(data: VideoInfo[]): void {
    this.dataArray = data
    // 整组替换语义：必须通知全量重载，仅通知末位新增会导致旧数据残留
    this.notifyDataReload()
  }

  // 删除全部数据
  public clear(): void {
    this.empty()
    this.refresh()
  }

  public empty(): void {
    this.dataArray = []
  }

  public refresh(): void {
    this.notifyDataReload()
  }

}

// 目录列表数据
export class CategoryListDataSource extends BaseDataSource<DramaList> {
  private dataArray: DramaList[] = []

  public totalCount(): number {
    return this.dataArray.length
  }

  public getData(index: number): DramaList {
    return this.dataArray[index]
  }

  public addData(index: number, data: DramaList): void {
    this.dataArray.splice(index, 0, data)
    this.notifyDataAdd(index)
  }

  public pushData(data: DramaList[]): void {
    this.dataArray = data
    // 整组替换语义：必须通知全量重载，仅通知末位新增会导致旧数据残留
    this.notifyDataReload()
  }

  // 删除全部数据
  public clear(): void {
    this.empty()
    this.refresh()
  }

  public empty(): void {
    this.dataArray = []
  }
  public refresh(): void {
    this.notifyDataReload()
  }
}