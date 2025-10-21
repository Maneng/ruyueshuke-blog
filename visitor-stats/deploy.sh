#!/bin/bash
# 访客统计API部署脚本

set -e

echo "========================================="
echo "访客统计API部署脚本"
echo "========================================="

# 配置变量
APP_DIR="/opt/visitor-stats"
SERVICE_NAME="visitor-stats"
USER="www-data"

# 创建应用目录
echo "1. 创建应用目录..."
mkdir -p $APP_DIR
mkdir -p /var/lib/visitor-stats
chmod 755 /var/lib/visitor-stats

# 复制文件
echo "2. 复制应用文件..."
cp app.py $APP_DIR/
cp requirements.txt $APP_DIR/

# 安装Python依赖
echo "3. 安装Python依赖..."
cd $APP_DIR
pip3 install -r requirements.txt

# 创建systemd服务
echo "4. 创建systemd服务..."
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Visitor Statistics API Service
After=network.target

[Service]
Type=exec
User=root
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/gunicorn --bind 127.0.0.1:5000 --workers 2 app:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 重载systemd配置
echo "5. 重载systemd配置..."
systemctl daemon-reload

# 启动服务
echo "6. 启动服务..."
systemctl enable ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME}

# 检查服务状态
echo "7. 检查服务状态..."
sleep 2
systemctl status ${SERVICE_NAME} --no-pager

echo "========================================="
echo "部署完成！"
echo "服务运行在: http://127.0.0.1:5000"
echo "========================================="
echo ""
echo "后续操作："
echo "1. 配置Nginx反向代理"
echo "2. 重启Nginx: systemctl restart nginx"
echo ""
