// 断点
import { BreakpointState } from "../../utils/BreakPointManager"
import { deviceInfo } from "@kit.BasicServicesKit"


/**
 * 断点名称
 */
export const CompStr: BreakpointState<string> = BreakpointState.of({
  xs: "xs",
  sm: "sm",
  md: "md",
  lg: "lg",
  xl: "xl"
})

/**
 * 入口页tab栏模式  F F F T
 */
export const TabVertical: BreakpointState<boolean> = BreakpointState.of({
  xs: false,
  sm: false,
  md: false,
  lg: false,
  xl: true
})

/**
 * 入口页Tab栏高度
 */
export const TabBarHeight: BreakpointState<string> = BreakpointState.of({
  xs: '45vp',
  sm: '48vp',
  md: '54vp',
  lg: '100%',
  xl: '100%'
})

/**
 * 入口页Tab栏宽度
 */
export const TabBarWidth: BreakpointState<string> = BreakpointState.of({
  xs: '100%',
  sm: '100%',
  md: '100%',
  lg: '54vp',
  xl: '60vp'
})

/**
 * 入口页Tab栏位置
 */
export const TabBarPosition: BreakpointState<BarPosition> = BreakpointState.of({
  xs: BarPosition.End,
  sm: BarPosition.End,
  md: BarPosition.End,
  lg: BarPosition.Start,
  xl: BarPosition.Start
})

/**
 * 视频列表Grid列数
 */
export const VideoListColumnsTemplate: BreakpointState<string> = BreakpointState.of({
  xs: "1fr 1fr ",
  sm: "1fr 1fr 1fr",
  md: "1fr 1fr 1fr 1fr",
  lg: "1fr 1fr 1fr 1fr 1fr",
  xl: "1fr 1fr 1fr 1fr 1fr 1fr"
})

/**
 * 首页轮播图显示数量
 */
export const HomeBannerDisplayCount: BreakpointState<number> = BreakpointState.of({
  xs: 1,
  sm: 1,
  md: 2,
  lg: 3,
  xl: 3
})

/**
 * 首页轮播图前&后边距（前后露出的部分）
 */
export const HomeBannerBannerMargin: BreakpointState<number> = BreakpointState.of({
  xs: 0,
  sm: 0,
  md: 12,
  lg: 64,
  xl: 64
})

/**
 * 视频详情页初始栅格高度(视频 + 详情)
 */
export const VideoDetailGridColHeight: BreakpointState<Length> = BreakpointState.of({
  xs: '',
  sm: '',
  md: deviceInfo.deviceType === 'tablet' ? '' : '100%',
  lg: '100%',
  xl: '100%'
})

/**
 * 播放器初始栅格断点 两分栏
 */
export const VideoPlayerGridColSpan: GridColColumnOption = {xs: 12, sm: 12, md: deviceInfo.deviceType === 'tablet' ? 12 : 9, lg: 8}

/**
 * 播放器新栅格断点 12
 */
export const VideoPlayerNewGridColSpan: GridColColumnOption | number = 12

/**
 * 视频详情初始栅格断点 两分栏
 */
export const VideoDetailGridColSpan: GridColColumnOption = {xs: 12, sm: 12, md: deviceInfo.deviceType === 'tablet' ? 12 : 3, lg: 4}

/**
 * 视频详情 新栅格断点 0
 */
export const VideoDetailNewGridColSpan: GridColColumnOption | number = 0