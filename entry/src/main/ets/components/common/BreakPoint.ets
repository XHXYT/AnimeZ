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
 * 首页底部偏移量
 */
export const MainEndOffset: BreakpointState<number> = BreakpointState.of({
  xs: 180,
  sm: 200,
  md: 260,
  lg: 30,
  xl: 60
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