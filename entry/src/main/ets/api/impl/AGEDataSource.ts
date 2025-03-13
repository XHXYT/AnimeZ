import { DramaList } from '../../entity/HomepageData';
import HomepageData from '../../entity/HomepageData';
import Logger from '../../utils/Logger';
import EpisodeInfo from '../../entity/EpisodeInfo';
import VideoInfo from '../../entity/VideoInfo';
import EpisodeList from '../../entity/EpisodeList';
import VideoDetailInfo from '../../entity/VideoDetailInfo';
import HttpUtils from '../../utils/HttpUtils';
import DataSource from '../DataSource';
import { select, selectAttributeValue, selectFirst, selectTextContent, textContent } from '../../thirdpart/htmlsoup';

const BASE_URL = 'https://www.agedm.org/'

/**
 * AGE动漫 (https://www.agedm.org) 视频源
 */
export default class AGEDataSource implements DataSource {

    getKey(): string {
        return 'key_agedmvideo'
    }

    async search(keyword: string, page: number): Promise<VideoInfo[]> {
        let url = BASE_URL + "search?query=" + encodeURIComponent(keyword) // + "/?page=" + page TODO 处理更多页

        let videos: VideoInfo[] = []
        let doc = await HttpUtils.getHtml(url)
        const list = select(doc, 'div.row > div > div')
        list.forEach((div) => {
            let a = selectFirst(div, "a")
            let img = selectFirst(div, 'img')
            videos.push({
                sourceKey: this.getKey(),
                url: a.attr('href'),
                imgUrl: img.attr('data-original'),
                title: img.attr('alt'),
                episode: selectTextContent(div, ' div > div.video_cover > div > span')
            })
        })
        return videos
    }

    async getHomepageData(): Promise<HomepageData> {
        console.log('#getHomepageData 开始解析主页数据')
        let url = BASE_URL
        const doc = await HttpUtils.getHtml(url)
        const recommendList: VideoInfo[] = []
        const newList: VideoInfo[] = []
        const categoryList: DramaList[] = []

        // 最近更新
        const nlist = select(doc, 'div.video_list_box.recent_update > div.video_list_box--bd > div > div > div')
        nlist.forEach((div) => {
            const a = selectFirst(div, "a")
            const img = selectFirst(div, 'img')
            newList.push({
                sourceKey: this.getKey(),
                url: a.attr('href'),
                imgUrl: img.attr('data-original'),
                title: selectTextContent(div, 'a'),
                episode: selectTextContent(div, 'span')
            })
            // console.log('#getHomepageData 图片 = ', img.attr('data-original'))
        })
        // 今日推荐
        const rlist = select(doc, 'div.video_list_box.recommend_list > div.video_list_box--bd > div > div')
        rlist.forEach((div) => {
            const a = selectFirst(div, "a")
            const img = selectFirst(div, 'img')
            recommendList.push({
                sourceKey: this.getKey(),
                url: a.attr('href'),
                imgUrl: img.attr('data-original'),
                title: selectTextContent(div, 'a'),
                episode: selectTextContent(div, 'span')
            })
        })

        const titles = select(doc, 'div.video_list_box--hd') // div.col-8 > div >
        const videoList = select(doc, 'div.video_list_box--bd')
        console.log('#getHomepageData 列表标题数= ', titles.length)
        console.log('#getHomepageData 列表数= ', videoList.length)

        const count = Math.min(titles.length, videoList.length)
        console.log('#getHomepageData 视频数据列表数= ', count)
        for (let i = 0; i < count; i++) {
            // console.log('#getHomepageData 解析视频列表名')
            const title = titles[i]

            categoryList.push({
                title: selectTextContent(title, "h6").split("»")[1],
                moreUrl: selectAttributeValue(title, 'h6 > a', 'href'),
                videoList: i === 0 ? newList : recommendList  // 手动选择视频列表
            })
        }

        return {
            bannerList: recommendList, // 使用今日推荐作为轮播图
            categoryList: categoryList
        }
    }

    // TODO 还不知道怎么用的
    async getVideoList(moreUrl: string, page: number): Promise<VideoInfo[]> {
        let url = "http://www.bimiacg4.net/type/riman-" + page
        let doc = await HttpUtils.getHtml(url)
        let drama = selectFirst(doc, 'ul.drama-module')
        return this.parseVideoList(drama)
    }
    private async parseVideoList(drama): Promise<VideoInfo[]> {
        Logger.e(this, 'parseHtml drama=' + drama)
        let elements = select(drama, 'li')
        Logger.e(this, 'parseHtml elements=' + elements)
        let videoList: VideoInfo[] = []

        // TODO 代码优化
        elements.forEach((el) => {
            Logger.e(this, "parseHtml el=" + el)
            let a = selectFirst(el, "div.info > a")
            videoList.push({
                sourceKey: this.getKey(),
                url: "http://www.bimiacg4.net" + a.attr('href'),
                imgUrl: selectAttributeValue(el, 'img', 'src'),
                title: textContent(a),
                episode: selectTextContent(el, "div.info > p > span.fl")
            })
        })
        return videoList
    }

    async getVideoDetailInfo(url: string): Promise<VideoDetailInfo> {
        let doc = await HttpUtils.getHtml(url);

        Logger.e(this, 'getVideoDetailInfo 1')

        let title = selectTextContent(doc, 'section > div > div.video_detail_right.ps-3.flex-grow-1 > h2')

        Logger.e(this, 'getVideoDetailInfo title=' + title)

        // 相关推荐
        let recommends: VideoInfo[] = []
        let list = select(doc, 'div.video_list_box.video_detail_recommend_wrapper.pt-4 > div.video_list_box--bd > div > div')
        list.forEach((div) => {
            let a = selectFirst(div, "a")
            let img = selectFirst(div, 'img')
            recommends.push({
                sourceKey: this.getKey(),
                url: a.attr('href'),
                imgUrl: img.attr('data-original'),
                title: textContent(a),
                episode: selectTextContent(div, 'span')
            })
        })

        let episodesList: EpisodeList[] = []
        // 路线标题[]
        const Listitle = select(doc, 'div.video_detail_playlist_wrapper.pt-4 > ul > li')
        // 路线剧集[]
        const lis = select(doc, 'div.video_detail_playlist_wrapper.pt-4 > div.tab-content > div')
        Logger.e(this, '#getVideoDetailInfo AGE 路线数=' + lis.length)

        const count = Math.min(Listitle.length, lis.length)
        for (let i = 0; i < count; i++) {
            const listitle = Listitle[i]
            const list = lis[i]
            const episodesInfo: EpisodeInfo[] = []
            const li = select(list, 'ul > li')
            li.forEach((li) => {
                const a = selectFirst(li, 'a')
                let info: EpisodeInfo = {
                    link: a.attr('href'),
                    title: textContent(a),
                    desc: title + ' ' + textContent(a)
                }
                episodesInfo.push(info)
            })
            episodesList.push({
                title: selectTextContent(listitle, 'button'),
                episodes: episodesInfo
            })
        }

        // TODO 扩展基本信息
        let videoDetailInfo: VideoDetailInfo = {
            sourceKey: this.getKey(),
            title: title,
            url: url,
            desc: selectTextContent(doc, "div.video_detail_right.ps-3.flex-grow-1 > div.video_detail_desc.py-2").trim(),
            coverUrl: selectAttributeValue(doc, "section > div > div.video_detail_left > div.video_detail_cover > img", 'data-original'),
            category: selectTextContent(doc, 'div.video_detail_box.detail_baseinfo.my-2 > div > div > div > ul > li:nth-child(9) > span:nth-child(2)'),
            director: '',
            updateTime: '',
            protagonist: '',
            episodes: episodesList,
            recommends: recommends
        }
        return videoDetailInfo
    }

    // 先返回播放器链接，后调用webview加载视频
    async parseVideoUrl(link: string): Promise<string> {
        Logger.e(this, 'parseVideoUrl 资源播放界面link = ' + link)
        const doc = await HttpUtils.getHtml(link)

        const iframeurl = selectAttributeValue(doc, "iframe#iframeForVideo", "src")
        Logger.e(this, 'parseVideoUrl 云播放器link = ' + iframeurl)
        return iframeurl
    }
}
