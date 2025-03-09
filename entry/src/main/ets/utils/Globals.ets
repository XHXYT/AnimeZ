// import HashMap from '@ohos.util.HashMap';
// import DataSource from '../api/DataSource';
//
// /**
//  * 全局存取对象
//  */
// export default class Globals {
//   /**
//    * 定义全局存储的键值类型约束
//    */
//   private static readonly GLOBAL_MAP_KEY = 'global_map';
//
//   private static instance: Map<string, DataSource> = new Map();
//
//   /**
//    * 类型安全的全局存储方法
//    * @param key 存储键(需唯一标识)
//    * @param builder 对象构造器
//    */
//   static get(key: string, builder: () => DataSource): DataSource {
//     const stored = Globals.instance.get(key);
//     if (!stored) {
//       const newInstance = builder();
//       Globals.instance.set(key, newInstance);
//       return newInstance;
//     }
//     return stored;
//   }
//
//   /**
//    * 获取强类型全局Map容器（使用泛型约束键值类型）
//    */
//   static getGlobalMap<K extends Object, V>(): HashMap<K, V> {
//     return Globals.getContainer<HashMap<K, V>>(
//       Globals.GLOBAL_MAP_KEY,
//       () => new HashMap<K, V>()
//     ).value
//   }
//
//   /**
//    * 类型安全的存取方法（带泛型约束）
//    */
//   static getOrCreate<K extends Object, T>(key: K, buildFunc: () => T): T {
//     const globalMap = Globals.getGlobalMap<K, T>();
//     let value = globalMap.get(key);
//
//     console.debug(`getOrCreate key=${JSON.stringify(key)} value=${JSON.stringify(value)}`);
//
//     if (!value) {
//       value = buildFunc();
//       globalMap.set(key, value);
//     }
//     return value;
//   }
//
//   /**
//    * 带类型声明的移除方法
//    */
//   static remove<K extends Object, T>(key: K): T | undefined {
//     return Globals.getGlobalMap<K, T>().remove(key);
//   }
// }
