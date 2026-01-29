# ============================================
# 访客统计服务 - Dockerfile
# ============================================
#
# 构建说明:
#   docker build -f visitor-stats.Dockerfile -t visitor-stats:latest .
#
# 镜像大小: ~150MB (使用python:3.11-slim)
# ============================================

FROM python:3.11-slim

# 维护者信息
LABEL maintainer="service@ruyueshuke.com"
LABEL description="Visitor Statistics API Service"
LABEL version="1.0"

# 设置工作目录
WORKDIR /app

# 安装系统依赖
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        sqlite3 && \
    rm -rf /var/lib/apt/lists/*

# 复制依赖文件
COPY visitor-stats/requirements.txt .

# 安装Python依赖
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir gunicorn

# 复制应用代码
COPY visitor-stats/app.py .

# 创建数据目录
RUN mkdir -p /data && \
    chmod 755 /data

# 创建非root用户
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app /data

# 切换到非root用户
USER appuser

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:5000/api/health || exit 1

# 暴露端口
EXPOSE 5000

# 环境变量
ENV DB_PATH=/data/stats.db
ENV PYTHONUNBUFFERED=1

# 启动命令
# 使用Gunicorn运行Flask应用
# --bind 0.0.0.0:5000: 监听所有网络接口
# --workers 2: 2个工作进程
# --threads 2: 每个进程2个线程
# --timeout 30: 请求超时30秒
# --access-logfile -: 访问日志输出到stdout
# --error-logfile -: 错误日志输出到stderr
CMD ["gunicorn", \
     "--bind", "0.0.0.0:5000", \
     "--workers", "2", \
     "--threads", "2", \
     "--timeout", "30", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "--log-level", "info", \
     "app:app"]
