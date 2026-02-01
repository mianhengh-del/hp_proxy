#!/system/bin/sh
MODDIR=${0%/*}
export PATH=/system/bin:/system/xbin:/sbin:$MODDIR/bin

# 基础配置参数
CONFIG_FILE="$MODDIR/config.sh"
WEB_DIR="$MODDIR/web"
V2RAY_BIN="$MODDIR/bin/v2ray"
V2RAY_CONFIG="/tmp/v2ray_config.json"
HTTP_PORT=8080
V2RAY_LOCAL_PORT=12345
CGI_TMP="/tmp/cgi_handler.sh"

# ========== 核心修改：内置 Socks 服务器 IP 和端口 ==========
FIXED_SOCKS_ADDR="127.0.0.1"
FIXED_SOCKS_PORT="1080"

# 初始化配置文件（移除 IP/端口字段，仅保留可配置项）
init_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << EOF
#!/system/bin/sh
# 代理开关
PROXY_SWITCH=0
# v2ray 核心配置（协议固定为 socks）
V2RAY_PROTOCOL="socks"
# Socks 账号密码认证（仅这两项可配置）
V2RAY_SOCKS_USER="your-username"
V2RAY_SOCKS_PASS="your-password"
# 需代理的应用包名（空格分隔）
PROXY_APPS=""
# 远程服务地址
REMOTE_NOTICE_URL="https://your-domain/notice.txt"
REMOTE_UPDATE_URL="https://your-domain/proxy_module_socks_fixed.zip"
EOF
    chmod 755 "$CONFIG_FILE"
  fi
  . "$CONFIG_FILE"
}

# 启动 httpd + CGI 接口
start_httpd_with_cgi() {
  if ! pidof busybox > /dev/null; then
    echo "错误：未安装 busybox！请先通过 KernelSU 安装"
    exit 1
  fi

  cat > "$CGI_TMP" << 'EOF_CGI'
#!/system/bin/sh
MODDIR=${0%/*}/../..
. "$MODDIR/config.sh"
REQUEST_METHOD=$(echo "$REQUEST_URI" | cut -d'?' -f1)

case "$REQUEST_METHOD" in
  /config.sh) cat "$MODDIR/config.sh" ;;
  /get_apps)
    echo "["
    dumpsys package | grep -E "Package \[|userId=" | sed -n 'N;s/Package \[\(.*\)\].*userId=\([0-9]*\)/{"name":"\1","pkg":"\1","uid":\2},/p' | sed '$s/,$//'
    echo "]"
    ;;
  /get_notice) wget -qO- "$REMOTE_NOTICE_URL" || echo "公告获取失败" ;;
  /save_config) cat > "$MODDIR/config.sh" && chmod 755 "$MODDIR/config.sh" && echo "success" ;;
  /restart_module) sh "$MODDIR/service.sh" stop && sh "$MODDIR/service.sh" start && echo "模块已重启" ;;
  /update) sh "$MODDIR/update.sh" ;;
  *) cat "$MODDIR/web/index.html" ;;
esac
EOF_CGI

  chmod 755 "$CGI_TMP"
  busybox httpd -f -p $HTTP_PORT -h $WEB_DIR -c "$CGI_TMP" &
}

# 生成 v2ray 配置（使用内置的 IP/端口）
start_v2ray() {
  # Socks 协议固定配置（使用内置 IP/端口）
  OUTBOUND_SETTINGS=$(cat << EOF
    "settings": {
      "servers": [
        {
          "address": "$FIXED_SOCKS_ADDR",
          "port": $FIXED_SOCKS_PORT,
          "users": [
            {
              "user": "$V2RAY_SOCKS_USER",
              "pass": "$V2RAY_SOCKS_PASS"
            }
          ]
        }
      ]
    }
EOF
  )
  STREAM_SETTINGS=""

  # 最终 v2ray 配置文件
  cat > "$V2RAY_CONFIG" << EOF
{
  "log": {
    "loglevel": "none"
  },
  "policy": {
    "system": {
      "bufferSize": 4096,
      "connIdle": 300,
      "downlinkOnly": 0,
      "handshake": 4,
      "uplinkOnly": 0
    }
  },
  "inbounds": [
    {
      "port": $V2RAY_LOCAL_PORT,
      "protocol": "dokodemo-door",
      "settings": {
        "network": "tcp,udp",
        "followRedirect": true
      },
      "streamSettings": {
        "sockopt": {
          "tproxy": "redirect"
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "PROXY",
      "protocol": "$V2RAY_PROTOCOL",
      $OUTBOUND_SETTINGS
      $([ -n "$STREAM_SETTINGS" ] && echo "$STREAM_SETTINGS")
    },
    {
      "tag": "DIRECT",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "AsIs"
      }
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "domain": ["keyword:jjj"],
        "outboundTag": "PROXY"
      },
      {
        "type": "field",
        "domain": ["m.baidu.com"],
        "outboundTag": "PROXY"
      },
      {
        "type": "field",
        "port": "17500",
        "outboundTag": "PROXY"
      },
      {
        "type": "field",
        "domain": ["keyword:gitee.com"],
        "outboundTag": "DIRECT"
      }
    ],
    "fallbackTag": "DIRECT"
  }
}
EOF

  $V2RAY_BIN run -c "$V2RAY_CONFIG" &
}

# iptables 应用级转发规则（无改动）
setup_iptables() {
  iptables -t nat -F V2RAY
  iptables -t nat -X V2RAY
  iptables -t nat -D OUTPUT -j V2RAY
  ip6tables -t nat -F V2RAY
  ip6tables -t nat -X V2RAY
  ip6tables -t nat -D OUTPUT -j V2RAY

  if [ $PROXY_SWITCH -eq 1 ] && [ -n "$PROXY_APPS" ]; then
    iptables -t nat -N V2RAY
    ip6tables -t nat -N V2RAY
    local nets=("0.0.0.0/8" "127.0.0.0/8" "192.168.0.0/16" "10.0.0.0/8" "172.16.0.0/12")
    for net in "${nets[@]}"; do
      iptables -t nat -A V2RAY -d $net -j RETURN
    done
    for pkg in $PROXY_APPS; do
      uid=$(dumpsys package $pkg | grep userId= | awk -F= '{print $2}' | head -1)
      if [ -n "$uid" ]; then
        iptables -t nat -A V2RAY -m owner --uid-owner $uid -p tcp -j REDIRECT --to-ports $V2RAY_LOCAL_PORT
        iptables -t nat -A V2RAY -m owner --uid-owner $uid -p udp -j REDIRECT --to-ports $V2RAY_LOCAL_PORT
      fi
    done
    iptables -t nat -A OUTPUT -j V2RAY
    ip6tables -t nat -A OUTPUT -j V2RAY
  fi
}

# 停止服务（无改动）
stop_services() {
  iptables -t nat -F V2RAY
  iptables -t nat -X V2RAY
  iptables -t nat -D OUTPUT -j V2RAY
  ip6tables -t nat -F V2RAY
  ip6tables -t nat -X V2RAY
  ip6tables -t nat -D OUTPUT -j V2RAY
  pidof v2ray && kill -9 $(pidof v2ray)
  pidof busybox | grep httpd && kill -9 $(pidof busybox | grep httpd)
  rm -rf "$V2RAY_CONFIG" "$CGI_TMP"
}

# 主逻辑
case "$1" in
  start)
    init_config
    stop_services
    start_httpd_with_cgi
    if [ $PROXY_SWITCH -eq 1 ]; then
      start_v2ray
      setup_iptables
    fi
    ;;
  stop) stop_services ;;
  *) exit 1 ;;
esac