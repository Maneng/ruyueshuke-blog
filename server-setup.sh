#!/bin/bash
# 服务器配置脚本 - 在阿里云服务器上执行

echo "========================================"
echo "Hugo博客服务器配置脚本"
echo "========================================"

# 步骤1：创建部署目录
echo ""
echo "步骤1：创建部署目录..."
sudo mkdir -p /var/www/blog
sudo chown -R $USER:$USER /var/www/blog
sudo chmod -R 755 /var/www/blog

# 验证目录
echo "验证目录权限："
ls -la /var/www/ | grep blog

# 步骤2：创建测试页面
echo ""
echo "步骤2：创建测试页面..."
cat > /var/www/blog/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>如月书客博客</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 100px auto;
            padding: 20px;
            text-align: center;
        }
        h1 { color: #333; }
        p { color: #666; }
        .status {
            background: #4CAF50;
            color: white;
            padding: 10px 20px;
            border-radius: 5px;
            display: inline-block;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <h1>🎉 如月书客的博客</h1>
    <p class="status">服务器配置成功！</p>
    <p>部署目录：/var/www/blog</p>
    <p>等待GitHub Actions自动部署...</p>
</body>
</html>
EOF

echo "测试页面已创建"

# 步骤3：检查Nginx状态
echo ""
echo "步骤3：检查Nginx状态..."
sudo systemctl status nginx --no-pager | head -10

# 步骤4：备份现有Nginx配置
echo ""
echo "步骤4：备份Nginx配置..."
if [ -f /etc/nginx/sites-available/blog ]; then
    sudo cp /etc/nginx/sites-available/blog /etc/nginx/sites-available/blog.backup
    echo "已备份现有配置"
else
    echo "未找到现有配置，将创建新配置"
fi

echo ""
echo "========================================"
echo "基础配置完成！"
echo "========================================"
echo ""
echo "下一步："
echo "1. 访问 https://47.93.8.184 测试是否显示测试页面"
echo "2. 如果能访问，说明Nginx配置正确"
echo "3. 继续配置GitHub Actions自动部署"
echo ""
echo "当前用户: $USER"
echo "部署目录: /var/www/blog"
echo ""
