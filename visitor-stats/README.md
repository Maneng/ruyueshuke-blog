# 访客统计API服务

## 功能特性

- ✅ PV统计（总访问量）
- ✅ UV统计（独立访客数，基于IP哈希）
- ✅ 今日访问统计
- ✅ 防刷机制（同一IP 60秒内只计数一次）
- ✅ 隐私保护（IP经过SHA256哈希处理）
- ✅ 跨域支持（CORS）

## 技术栈

- Python 3.6+
- Flask 2.0
- SQLite 3
- Gunicorn
- Systemd

## 部署步骤

### 1. 上传文件到服务器

```bash
# 在本地执行
scp -r visitor-stats/* root@your-server:/tmp/visitor-stats/
```

### 2. 执行部署脚本

```bash
# 连接到服务器
ssh root@your-server

# 进入目录
cd /tmp/visitor-stats

# 赋予执行权限
chmod +x deploy.sh

# 执行部署
./deploy.sh
```

### 3. 配置Nginx反向代理

```bash
# 查看您的Nginx主配置文件位置
nginx -t

# 编辑配置文件（根据实际情况选择）
# 可能是以下之一：
# - /etc/nginx/nginx.conf
# - /etc/nginx/conf.d/default.conf
# - /etc/nginx/sites-available/default

# 在server块中添加以下内容（参考nginx-config.conf）
location /api/stats {
    proxy_pass http://127.0.0.1:5000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}

# 测试配置
nginx -t

# 重启Nginx
systemctl restart nginx
```

### 4. 测试API

```bash
# 健康检查
curl https://ruyueshuke.com/api/health

# 获取统计数据
curl https://ruyueshuke.com/api/stats

# 记录访问（POST请求）
curl -X POST https://ruyueshuke.com/api/stats/visit \
  -H "Content-Type: application/json" \
  -d '{"url": "https://ruyueshuke.com/blog/"}'
```

## API文档

### 1. 获取统计数据

**请求**:
```
GET /api/stats
```

**响应**:
```json
{
  "success": true,
  "data": {
    "total_pv": 1234,
    "total_uv": 567,
    "today_pv": 89,
    "today_uv": 45
  }
}
```

### 2. 记录访问

**请求**:
```
POST /api/stats/visit
Content-Type: application/json

{
  "url": "https://ruyueshuke.com/blog/"
}
```

**响应**:
```json
{
  "success": true,
  "message": "Visit recorded",
  "counted": true
}
```

### 3. 健康检查

**请求**:
```
GET /api/health
```

**响应**:
```json
{
  "status": "healthy",
  "timestamp": "2025-10-21T15:30:00"
}
```

## 服务管理

```bash
# 查看服务状态
systemctl status visitor-stats

# 启动服务
systemctl start visitor-stats

# 停止服务
systemctl stop visitor-stats

# 重启服务
systemctl restart visitor-stats

# 查看日志
journalctl -u visitor-stats -f

# 查看最近100行日志
journalctl -u visitor-stats -n 100
```

## 数据库位置

- 数据库文件: `/var/lib/visitor-stats/stats.db`
- 应用目录: `/opt/visitor-stats`

## 数据备份

```bash
# 备份数据库
cp /var/lib/visitor-stats/stats.db /backup/stats-$(date +%Y%m%d).db

# 设置定时备份（添加到crontab）
crontab -e
# 每天凌晨2点备份
0 2 * * * cp /var/lib/visitor-stats/stats.db /backup/stats-$(date +\%Y\%m\%d).db
```

## 故障排查

### 服务无法启动

```bash
# 查看详细日志
journalctl -u visitor-stats -xe

# 检查Python依赖
pip3 list | grep Flask

# 手动运行测试
cd /opt/visitor-stats
python3 app.py
```

### Nginx 502错误

```bash
# 检查API服务是否运行
systemctl status visitor-stats

# 检查端口是否监听
netstat -tulnp | grep 5000

# 测试本地连接
curl http://127.0.0.1:5000/api/health
```

## 性能优化

当前配置使用2个worker进程，适合中小流量网站。如需优化：

```bash
# 编辑systemd服务配置
vim /etc/systemd/system/visitor-stats.service

# 调整workers数量（通常设置为 CPU核心数 * 2 + 1）
ExecStart=/usr/bin/gunicorn --bind 127.0.0.1:5000 --workers 4 app:app

# 重载配置并重启
systemctl daemon-reload
systemctl restart visitor-stats
```

## 安全建议

1. ✅ IP已经过哈希处理，保护用户隐私
2. ✅ 已实现频率限制，防止恶意刷量
3. ⚠️ 建议配置防火墙，仅允许Nginx访问5000端口
4. ⚠️ 建议定期备份数据库

```bash
# 配置防火墙（如果使用firewalld）
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="127.0.0.1" port protocol="tcp" port="5000" accept'
firewall-cmd --reload
```
