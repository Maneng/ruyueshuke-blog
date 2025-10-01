#!/bin/bash
# Nginx配置脚本 - 在阿里云服务器上执行

echo "========================================"
echo "配置Nginx - Hugo博客"
echo "========================================"

# 创建Nginx配置文件
echo "创建Nginx配置文件..."

sudo tee /etc/nginx/sites-available/blog > /dev/null << 'NGINXCONF'
# HTTP服务器 - 重定向到HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name 47.93.8.184;

    # HTTP自动跳转HTTPS
    return 301 https://$server_name$request_uri;
}

# HTTPS服务器
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name 47.93.8.184;

    # SSL证书配置（请根据实际路径修改）
    # 如果你的SSL证书路径不同，请修改以下两行
    # ssl_certificate /etc/ssl/certs/your-cert.crt;
    # ssl_certificate_key /etc/ssl/private/your-key.key;

    # SSL安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # 网站根目录
    root /var/www/blog;
    index index.html index.htm;

    # 字符集
    charset utf-8;

    # 日志配置
    access_log /var/log/nginx/blog_access.log;
    error_log /var/log/nginx/blog_error.log warn;

    # 主路由配置
    location / {
        try_files $uri $uri/ /index.html =404;
    }

    # 静态资源缓存配置（图片、CSS、JS等）
    location ~* \.(jpg|jpeg|png|gif|ico|svg|webp)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    location ~* \.(css|js)$ {
        expires 7d;
        add_header Cache-Control "public";
        access_log off;
    }

    location ~* \.(woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public";
        access_log off;
    }

    # XML文件（RSS订阅等）
    location ~* \.(xml|rss|atom)$ {
        expires 1h;
        add_header Cache-Control "public";
    }

    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Gzip压缩配置
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/rss+xml
        application/atom+xml
        image/svg+xml;

    # 禁止访问隐藏文件
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    # 自定义404页面（可选）
    error_page 404 /404.html;
    location = /404.html {
        internal;
    }

    # 自定义50x错误页面（可选）
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        internal;
    }
}
NGINXCONF

echo "Nginx配置文件已创建：/etc/nginx/sites-available/blog"

# 启用站点
echo ""
echo "启用站点..."
sudo ln -sf /etc/nginx/sites-available/blog /etc/nginx/sites-enabled/

# 删除默认站点（可选）
if [ -f /etc/nginx/sites-enabled/default ]; then
    echo "删除默认站点配置..."
    sudo rm -f /etc/nginx/sites-enabled/default
fi

# 测试Nginx配置
echo ""
echo "测试Nginx配置..."
sudo nginx -t

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Nginx配置测试通过！"
    echo ""
    echo "重载Nginx..."
    sudo systemctl reload nginx

    if [ $? -eq 0 ]; then
        echo "✅ Nginx重载成功！"
    else
        echo "❌ Nginx重载失败，请检查日志"
        sudo systemctl status nginx
    fi
else
    echo "❌ Nginx配置测试失败，请检查配置文件"
    exit 1
fi

echo ""
echo "========================================"
echo "Nginx配置完成！"
echo "========================================"
echo ""
echo "访问测试："
echo "1. HTTP:  http://47.93.8.184"
echo "2. HTTPS: https://47.93.8.184"
echo ""
echo "注意："
echo "- 如果HTTPS无法访问，可能需要配置SSL证书路径"
echo "- 编辑 /etc/nginx/sites-available/blog"
echo "- 找到 ssl_certificate 和 ssl_certificate_key 行"
echo "- 修改为实际证书路径"
echo ""
