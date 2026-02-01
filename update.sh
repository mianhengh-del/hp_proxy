#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/config.sh"

update_module() {
  wget -qO /tmp/proxy_update.zip "$REMOTE_UPDATE_URL"
  if [ $? -eq 0 ]; then
    ksud module install /tmp/proxy_update.zip
    echo "更新包下载成功，已触发安装！重启设备生效"
  else
    echo "更新包下载失败，请检查网络或远程链接"
  fi
  rm -rf /tmp/proxy_update.zip
}

update_module
