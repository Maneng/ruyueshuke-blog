# ============================================
# Hugo博客 - 多阶段构建Dockerfile
# ============================================
#
# 构建说明:
#   docker build -f hugo-blog.Dockerfile -t hugo-blog:latest .
#
# 镜像大小: ~25MB (使用nginx:alpine)
# ============================================

# ============================================
# 阶段1: 构建Hugo静态文件
# ============================================
FROM klakegg/hugo:0.121.0-ext-alpine AS builder

# 设置工作目录
WORKDIR /src

# 复制源代码
COPY . /src

# 构建静态网站
# --minify: 压缩HTML/CSS/JS
# --gc: 清理未使用的缓存
RUN hugo --minify --gc

# 验证构建结果
RUN ls -lah /src/public/ && \
    echo "Hugo build completed successfully"

# ============================================
# 阶段2: 生产运行环境
# ============================================
FROM nginx:1.25-alpine

# 维护者信息
LABEL maintainer="service@ruyueshuke.com"
LABEL description="Hugo Blog - Static Site"
LABEL version="1.0"

# 安装必要工具(用于健康检查)
RUN apk add --no-cache curl

# 从构建阶段复制静态文件
COPY --from=builder /src/public /usr/share/nginx/html/blog

# 复制Nginx配置文件
COPY k8s-deployment/dockerfiles/nginx.conf /etc/nginx/nginx.conf
COPY k8s-deployment/dockerfiles/default.conf /etc/nginx/conf.d/default.conf

# 创建Nginx运行所需的目录
RUN mkdir -p /var/cache/nginx/client_temp && \
    mkdir -p /var/cache/nginx/proxy_temp && \
    mkdir -p /var/cache/nginx/fastcgi_temp && \
    mkdir -p /var/cache/nginx/uwsgi_temp && \
    mkdir -p /var/cache/nginx/scgi_temp && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/blog/ || exit 1

# 暴露端口
EXPOSE 80

# 使用非root用户运行(安全最佳实践)
USER nginx

# 启动Nginx
CMD ["nginx", "-g", "daemon off;"]
