/*
  * Copyright (c) 2022 Huawei Device Co., Ltd.
  *
  * Licensed under the Apache License, Version 2.0 (the "License");
  * you may not use this file except in compliance with the License.
  * You may obtain a copy of the License at
    *
  * http://www.apache.org/licenses/LICENSE-2.0
    *
  * Unless required by applicable law or agreed to in writing, software
  * distributed under the License is distributed on an "AS IS" BASIS,
  * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  * See the License for the specific language governing permissions and
  * limitations under the License.
  */

// THIS CODE IS GENERATED BY dataORM, DO NOT EDIT.
import { AbstractDao } from './AbstractDao';
import { Property, Constraint } from './Property';
import { DatabaseStatement } from './database/DatabaseStatement'
import { SQLiteStatement } from './database/SQLiteStatement'
import { Database } from './database/Database'
import { Query } from './query/Query';
import { SqlUtils } from './internal/SqlUtils'
import { StringBuilder } from './StringBuilder'
import { Entity } from './entity/Entity'
import { ToManyEntity } from './entity/ToManyEntity'
import { ToOneEntity } from './entity/ToOneEntity'
import { WhereCondition } from './query/WhereCondition';
/**
 * DAO for table "NOTE".
 */

export class BaseDao<T, K> extends AbstractDao<T, K> {
    public propertyArr: Property[];
    private toManyListQuery: Query<T> ;
    /** Creates the underlying database table. */
    public static createTable<T>(delegate: Database, ifNotExists: boolean, t: T): void {
        //todo 表创建示例
        //    const constraint = ifNotExists ? "IF NOT EXISTS " : "";
        //    let createSql = "CREATE TABLE " + constraint + "NOTE (" + //
        //    "ID INTEGER PRIMARY KEY AUTOINCREMENT," + // 0: id
        //    "TEXT TEXT NOT NULL," + // 1: text
        //    "COMMENT TEXT," + // 2: comment
        //    "DATE TEXT," + // 3: date
        //    "TYPE TEXT);";// 4: type

        let createSql = BaseDao.getCreateTableSql(ifNotExists, t);
        delegate.execSQL(createSql);

        //todo 索引创建示例
        //        const constraint = ifNotExists ? "IF NOT EXISTS " : "";
        //        delegate.execSQL("CREATE UNIQUE INDEX " + constraint + "IDX_NOTE_TEXT ON \"NOTE\"" +
        //        " (\"TEXT\" ASC);");

        let createIndexSqlArr: string[] = BaseDao.getCreateIndexSql(ifNotExists, t);
        if (createIndexSqlArr && createIndexSqlArr.length > 0) {
            for (let indexSql of createIndexSqlArr) {
                delegate.execSQL(indexSql);
            }
        }
    }

    /** Drops the underlying database table. */
    public static dropTable<T>(delegate: Database, ifExists: boolean, entityCls: T): void {
        const sql = "DROP TABLE " + (ifExists ? "IF EXISTS " : "") + BaseDao.TABLENAME(entityCls);
        delegate.execSQL(sql);
    }

    protected bindValues(stmt: DatabaseStatement | SQLiteStatement, entity: T): void {
        stmt.clearBindings();
        let properties = globalThis.entityCls[entity.constructor.name];
        if (properties) {
            for (let propertyName in properties) {
                let property = properties[propertyName];
                if (entity[property.name] != undefined) {
                    stmt.bindValue(property.columnName, entity[property.name])
                }
            }
        }
    }

    public readKey(cursor: any, offset: number): any {
        return cursor.isColumnNull(offset + 0) ? undefined : cursor.getLong(offset + 0);
    }

    public readEntity(cursor: any, offset: number): T {
        let entity = new this.entityCls();
        let properties = globalThis.entityCls[this.entityCls.name];
        let index = 0
        for (let key in properties) {
            let property = properties[key];
            let types = property.type;
            let columnIndex = offset + index
            switch (types) {
                case 'TEXT':
                    entity[property.name] = cursor.getString(columnIndex);
                    break;
                case 'INTEGER':
                    entity[property.name] = cursor.getLong(columnIndex);
                    break;
                case 'REAL':
                    entity[property.name] = cursor.getDouble(columnIndex);
                    break;
                case 'BLOB':
                    entity[property.name] = cursor.getBlob(columnIndex);
                    break;
            }
            index++
        }

        return entity;
    }
    /**
     * TODO readEntity 方法的无返回值
     */
    public readEntity2(cursor: any, entity: T, offset: number): void {
        let properties = globalThis.entityCls[entity.constructor.name];
        let index = 0
        for (let key in properties) {
            let property = properties[key];
            let types = property.type;
            let columnIndex = offset + index
            switch (types) {
                case 'TEXT':
                    entity[property.name] = cursor.getString(columnIndex);
                    break;
                case 'INTEGER':
                    entity[property.name] = cursor.getLong(columnIndex);
                    break;
                case 'REAL':
                    entity[property.name] = cursor.getDouble(columnIndex);
                    break;
                case 'BLOB':
                    entity[property.name] = cursor.getBlob(columnIndex);
                    break;
            }
            index++
        }
    }

    protected updateKeyAfterInsert(entity: any, rowId: number): K {

        if (entity != undefined) {
            let properties = globalThis.entityCls[this.entityCls.name]
            if (properties) {
                for (let key in properties) {
                    let property = properties[key];
                    if (property && property.primaryKey) {
                        entity[key] = rowId;
                    }
                }
            }
        }

        let n;
        n = rowId;

        return n;
    }

    protected getKey(entity: any): K {

        if (entity != undefined) {
            let properties = globalThis.entityCls[this.entityCls.name]
            if (properties) {
                for (let key in properties) {
                    let property = properties[key];
                    if (property && property.primaryKey) {
                        return entity[key];
                    }
                }
            }
            return null;

        } else {
            return null;
        }
    }

    public hasKey(entity: any): boolean {

        if (entity != undefined) {
            let properties = globalThis.entityCls[this.entityCls.name]
            if (properties) {
                for (let key in properties) {
                    let property = properties[key];
                    if (property && property.primaryKey) {
                        return entity[key] != undefined;
                    }
                }
            }
            return false;

        } else {
            return false;
        }
    }

    protected isEntityUpdateable(): boolean {
        return true;
    }

    private selectDeep: string;
    //toOne
    public getSelectDeep(): string {
        let entityCls = this.getEntityCls();
        let entity: Entity = globalThis.entityClsRelationship[entityCls.name]
        //if (this.selectDeep) {
        let builder = new StringBuilder("SELECT ");
        builder.append(SqlUtils.appendColumns("", "T", this.getAllColumns()));
        // entity.toOneRelations as toOne
        for (var i = 0; i < entity.toOneRelations.length; i++) {
            builder.append(',');
            let toOne: ToOneEntity = entity.toOneRelations[i];
            let targetClassName = toOne.targetEntityClsName;
            builder.append(SqlUtils.appendColumns("", "T" + i, this.session.getDao(targetClassName).getAllColumns()));
        }
        builder.append(" FROM " + entity.dbName + " T"); //含有ToOne当前dao 的数据表名，
        for (var i = 0; i < entity.toOneRelations.length; i++) {
            let toOne = entity.toOneRelations[i]

            let targetEntity: Entity = globalThis.entityClsRelationship[toOne.targetEntityClsName]
            builder.append(" LEFT JOIN " + targetEntity.dbName + " T" + i + " ON T." + toOne.fkProperties[0].columnName + "=T" + i + "." + targetEntity.pkProperty.columnName + "");

            builder.append(' ');
        }
        return builder.toString();
        //}
    }

    public async loadDeep(key: number): Promise<T> {
        this.assertSinglePk();
        if (key == null) {
            return null;
        }
        let entityCls = this.getEntityCls();
        let entity: Entity = globalThis.entityClsRelationship[entityCls.name]
        if (entity.toOneRelations == []) {
            console.info("Check @ToOne's annotations for creating tables")
            return undefined
        }
        let builder = new StringBuilder(this.getSelectDeep());
        builder.append("WHERE ");
        builder = new StringBuilder(SqlUtils.appendColumnsEqValue(builder.toString(), "T", this.getPkColumns()));
        let sql = builder.toString();
        let keyArray = new Array()
        keyArray.push(key.toString())
        let resultSet = await this.db.rawQuerys(sql, keyArray);
        try {
            let available = resultSet.goToFirstRow();
            if (!available) {
                return null;
            }
            return this.loadCurrentDeep(resultSet, true);
        } finally {
            resultSet.close();
        }
    }

    protected loadCurrentDeep(resultSet: any, lock: boolean): T {
        let entity: T = this.loadCurrent(resultSet, 0, lock);
        let offset: number = this.getAllColumns().length;
        let entityCls = this.getEntityCls();
        let entities: Entity = globalThis.entityClsRelationship[entityCls.name]
        for (let i = 0;i < entities.toOneRelations.length; i++) {
            let toOne = entities.toOneRelations[i]
            let customer = this.loadCurrentOther(this.getSession().getDao(toOne.targetEntityClsName), resultSet, offset);
            if (customer != null || customer != undefined) {
                entity[toOne.name] = customer;
            }
        }
        return entity;
    }

    public async queryToManyListByColumnName(toManyColumnName: string, arr: string[]): Promise<Array<T>> {

        let entityCls = this.getEntityCls();
        let entity: Entity = globalThis.entityClsRelationship[entityCls.name]
        let toManyEntities = entity.incomingToManyRelations;
        if (toManyEntities.length > 0) {
            let toMany: ToManyEntity
            toManyEntities.forEach(element => {
                if (element.name == toManyColumnName) {
                    toMany = element
                }
            });
            return await this._queryToManyList(toMany, arr);
        } else {
            return null
        }


    }


    /**
     *
     * let index =0;
     * let entityCls=this.getEntityCls();
     * let entity:Entity=globalThis.entityClsRelationship[entityCls.name]
     * let toMany= entity.incomingToManyRelations[index]
     * let arr:string[]
     * let columnValue="1233"
     * arr.push(columnKey)
     * BaseDao._queryToManyList(toMany,columnKey): Promise<Array<T>>
     *
     * */
    private async _queryToManyList(toMany: ToManyEntity, arr: string[]): Promise<Array<T>> {

        let queryBuilder = this.queryBuilder(); //target
        // @ts-ignore
        if (toMany.joinEntity == undefined) {
            for (let index = 0; index < toMany.targetProperties.length; index++) {
                let property = <Property> toMany.targetProperties[index]
                let cond = <WhereCondition> property.eqSql(null)
                queryBuilder.whereSql(cond);
            }
        } else {
            let joinEntityName = toMany.targetEntityClsName
            queryBuilder.join(joinEntityName, toMany.targetProperties[0])
                .whereSql(toMany.sourceProperties[0].eqSql(arr[0]));
        }
        let orderByStr = ""
        if (toMany.orderBy != undefined) {
            if (toMany.orderBy.includes(",")) {
                let orderByList = toMany.orderBy.split(',');
                for (var i = 0; i < orderByList.length; i++) {
                    orderByStr = "T." + orderByList[i]
                    if (i != orderByList.length - 1) {
                        orderByStr.concat(",")
                    }
                }
            } else {
                orderByStr = "T." + toMany.orderBy
            }
            queryBuilder.orderRaw(orderByStr);
        }
        this.toManyListQuery = queryBuilder.buildSql();
        //        }
        let query = this.toManyListQuery.forCurrentThread();
        for (let i = 0; i < arr.length; i++) {
            query.setParameter(i, arr[i]);
        }

        return await query.listSql();
    }

    /** Reads all available rows from the given cursor and returns a list of new ImageTO objects. */
    public loadAllDeepFromCursor(resultSet: any): Array<T> {
        let count = resultSet.rowCount;
        let list = new Array<T>();
        if (resultSet.goToFirstRow()) {
            if (this.identityScope != null) {
                this.identityScope.lock();
                this.identityScope.reserveRoom(count);
            }
            try {
                do {
                    list.push(this.loadCurrentDeep(resultSet, false));
                } while (resultSet.goToNextRow());
            } finally {
                if (this.identityScope != null) {
                    this.identityScope.unlock();
                }
            }
        }
        return list;
    }

    protected loadDeepAllAndCloseCursor(resultSet: any): Array<T> {
        try {
            return this.loadAllDeepFromCursor(resultSet);
        } finally {
            resultSet.close();
        }
    }

    /** A raw-style query where you can pass any WHERE clause and arguments. */
    public async queryDeep(where: string, selectionArg: string[]): Promise<Array<T>> {
        let entityCls = this.getEntityCls();
        let entity: Entity = globalThis.entityClsRelationship[entityCls.name]
        if (entity.toOneRelations == []) {
            console.info("Check @ToOne's annotations for creating tables")
            return undefined
        }
        let cursor = await  this.db.rawQuerys(this.getSelectDeep() + where, selectionArg);
        return this.loadDeepAllAndCloseCursor(cursor);
    }
}
