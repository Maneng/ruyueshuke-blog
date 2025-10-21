#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
访客统计API服务
功能：统计网站PV和UV，防止刷量
"""

from flask import Flask, jsonify, request
from flask_cors import CORS
import sqlite3
import hashlib
import time
from datetime import datetime, timedelta
import os

app = Flask(__name__)
CORS(app)  # 允许跨域请求

# 配置
DB_PATH = '/var/lib/visitor-stats/stats.db'
RATE_LIMIT_SECONDS = 60  # 同一IP 60秒内只计数一次

# 确保数据库目录存在
os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)


def init_db():
    """初始化数据库"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # 创建访问记录表
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS visits (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ip_hash TEXT NOT NULL,
            visit_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            user_agent TEXT,
            page_url TEXT
        )
    ''')

    # 创建访客表（UV统计）
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS visitors (
            ip_hash TEXT PRIMARY KEY,
            first_visit TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_visit TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            visit_count INTEGER DEFAULT 1
        )
    ''')

    # 创建索引
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_visit_time ON visits(visit_time)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_ip_hash ON visits(ip_hash)')

    conn.commit()
    conn.close()


def get_ip_hash(ip):
    """对IP进行哈希处理，保护隐私"""
    return hashlib.sha256(ip.encode()).hexdigest()


def check_rate_limit(ip_hash):
    """检查访问频率限制"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # 查询最近一次访问时间
    cursor.execute('''
        SELECT visit_time FROM visits
        WHERE ip_hash = ?
        ORDER BY visit_time DESC
        LIMIT 1
    ''', (ip_hash,))

    result = cursor.fetchone()
    conn.close()

    if result:
        last_visit = datetime.strptime(result[0], '%Y-%m-%d %H:%M:%S')
        time_diff = (datetime.now() - last_visit).total_seconds()
        return time_diff >= RATE_LIMIT_SECONDS

    return True


@app.route('/api/stats/visit', methods=['POST'])
def record_visit():
    """记录访问"""
    try:
        # 获取真实IP（考虑反向代理）
        ip = request.headers.get('X-Real-IP') or \
             request.headers.get('X-Forwarded-For', '').split(',')[0] or \
             request.remote_addr

        ip_hash = get_ip_hash(ip)
        user_agent = request.headers.get('User-Agent', '')
        page_url = request.json.get('url', '') if request.json else ''

        # 检查频率限制
        if not check_rate_limit(ip_hash):
            return jsonify({
                'success': True,
                'message': 'Rate limited',
                'counted': False
            })

        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()

        # 记录访问
        cursor.execute('''
            INSERT INTO visits (ip_hash, user_agent, page_url)
            VALUES (?, ?, ?)
        ''', (ip_hash, user_agent, page_url))

        # 更新或创建访客记录
        cursor.execute('''
            INSERT INTO visitors (ip_hash, first_visit, last_visit, visit_count)
            VALUES (?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1)
            ON CONFLICT(ip_hash) DO UPDATE SET
                last_visit = CURRENT_TIMESTAMP,
                visit_count = visit_count + 1
        ''', (ip_hash,))

        conn.commit()
        conn.close()

        return jsonify({
            'success': True,
            'message': 'Visit recorded',
            'counted': True
        })

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/stats', methods=['GET'])
def get_stats():
    """获取统计数据"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()

        # 总访问量（PV）
        cursor.execute('SELECT COUNT(*) FROM visits')
        total_pv = cursor.fetchone()[0]

        # 独立访客数（UV）
        cursor.execute('SELECT COUNT(*) FROM visitors')
        total_uv = cursor.fetchone()[0]

        # 今日访问量
        today = datetime.now().strftime('%Y-%m-%d')
        cursor.execute('''
            SELECT COUNT(*) FROM visits
            WHERE DATE(visit_time) = ?
        ''', (today,))
        today_pv = cursor.fetchone()[0]

        # 今日访客数
        cursor.execute('''
            SELECT COUNT(DISTINCT ip_hash) FROM visits
            WHERE DATE(visit_time) = ?
        ''', (today,))
        today_uv = cursor.fetchone()[0]

        conn.close()

        return jsonify({
            'success': True,
            'data': {
                'total_pv': total_pv,
                'total_uv': total_uv,
                'today_pv': today_pv,
                'today_uv': today_uv
            }
        })

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/health', methods=['GET'])
def health_check():
    """健康检查"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat()
    })


if __name__ == '__main__':
    init_db()
    # 生产环境使用gunicorn或uwsgi，这里仅用于开发测试
    app.run(host='0.0.0.0', port=5000, debug=False)
