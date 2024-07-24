#!/bin/bash

# 下载并执行 Hysteria 安装脚本
echo "开始下载并执行 Hysteria 安装脚本..."
bash <(curl -fsSL https://get.hy2.sh/)

# 检查 Hysteria 是否成功安装
if [ ! -f /usr/local/bin/hysteria ]; then
    echo "Hysteria 安装失败，请检查网络连接或 https://get.hy2.sh 是否有效。"
    exit 1
fi

# 提示用户输入服务器端口，默认使用 443
read -p "请输入服务器端口（默认: 443）: " SERVER_PORT
SERVER_PORT=${SERVER_PORT:-443}

# 生成随机认证密码，长度为 12 位
AUTH_PASSWORD=$(openssl rand -base64 12 | cut -c1-12)

# 提示用户选择配置方式
echo "请选择配置方式:"
echo "1) 使用 acme"
echo "2) 使用 tls"
read -p "请输入选择的配置方式 (1 或 2): " CONFIG_OPTION

# 根据选择生成证书和配置文件
if [ "$CONFIG_OPTION" -eq 1 ]; then
    # 如果选择 acme，则需要输入域名和邮箱
    read -p "请输入域名（例如: cn2.bozai.us）: " DOMAIN
    DOMAIN=${DOMAIN:-cn2.bozai.us}
    
    # 获取当前服务器的公网 IP
    SERVER_IP=$(curl -s https://api.ipify.org)
    
    # 检查域名是否解析到当前服务器 IP
    echo "正在检查域名解析..."
    DNS_IP=$(dig +short "$DOMAIN" | head -n 1)
    
    if [ "$DNS_IP" != "$SERVER_IP" ]; then
        echo "域名 $DOMAIN 解析的 IP 地址 ($DNS_IP) 与当前服务器的公网 IP ($SERVER_IP) 不匹配。"
        echo "请确认域名解析设置正确。"
        exit 1
    fi
    
    read -p "请输入邮箱（例如: your@email.com）: " EMAIL
    EMAIL=${EMAIL:-your@email.com}
    ACME_CONFIG="acme:
  domains:
    - $DOMAIN        # 域名
  email: $EMAIL   # 邮箱，格式正确即可"
    TLS_CONFIG="#tls:
#  cert: /etc/hysteria/server.crt
#  key: /etc/hysteria/server.key"
elif [ "$CONFIG_OPTION" -eq 2 ]; then
    # 如果选择 tls，则生成证书和私钥
    echo "生成 TLS 证书和私钥..."
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
        -subj "/CN=bing.com" -days 36500
    sudo chown hysteria /etc/hysteria/server.key
    sudo chown hysteria /etc/hysteria/server.crt

    TLS_CONFIG="tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key"
    ACME_CONFIG="#acme:
#  domains:
#    - cn2.bozai.us        # 域名
#  email: your@email.com   # 邮箱，格式正确即可"
else
    echo "无效的选择，请选择 1 或 2。"
    exit 1
fi

# 创建 /etc/hysteria 目录（如果不存在）
mkdir -p /etc/hysteria

# 生成新的配置文件内容
cat <<EOF >/etc/hysteria/config.yaml
listen: :$SERVER_PORT

# 以下 acme 和 tls 字段，二选一
$ACME_CONFIG

$TLS_CONFIG

auth:
  type: password
  password: $AUTH_PASSWORD   # 自动生成的密码

masquerade:
  type: proxy
  proxy:
    url: https://bing.com # 伪装网站
    rewriteHost: true
EOF

# 打印配置信息
echo "Hysteria 配置文件内容："
cat /etc/hysteria/config.yaml

# 重启 Hysteria 服务
echo "重新启动 Hysteria 服务..."
sudo systemctl restart hysteria-server.service

echo "配置文件已成功更新并重启服务！"
