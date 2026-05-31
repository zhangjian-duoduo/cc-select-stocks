#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
共享数据库连接池模块
所有模块通过此模块获取数据库连接
"""
import os
import pymysql
from dbutils.pooled_db import PooledDB

DB_CONFIG = {
    'host': os.environ.get('DB_HOST', 'localhost'),
    'user': os.environ.get('DB_USER', 'root'),
    'password': os.environ.get('DB_PASSWORD', ''),
    'database': os.environ.get('DB_NAME', 'select_stocks'),
    'charset': 'utf8mb4',
    'connect_timeout': 10,
    'autocommit': True
}

pool = PooledDB(
    pymysql,
    mincached=2,
    maxcached=10,
    maxconnections=20,
    blocking=True,
    **DB_CONFIG
)

def get_db():
    """从连接池获取一个数据库连接"""
    return pool.connection()
