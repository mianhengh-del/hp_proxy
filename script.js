// 加载配置到页面（仅解析可配置项）
async function loadConfig() {
  try {
    const res = await fetch('/config.sh');
    const config = await res.text();
    // 仅解析开关、账号密码、应用列表
    const proxySwitch = config.match(/PROXY_SWITCH=(\d)/)[1] === "1";
    const v2raySocksUser = config.match(/V2RAY_SOCKS_USER="(.*)"/)[1];
    const v2raySocksPass = config.match(/V2RAY_SOCKS_PASS="(.*)"/)[1];
    const proxyApps = config.match(/PROXY_APPS="(.*)"/)[1].split(" ");

    // 填充页面
    document.getElementById("proxy-switch").checked = proxySwitch;
    document.getElementById("v2ray-socks-user").value = v2raySocksUser;
    document.getElementById("v2ray-socks-pass").value = v2raySocksPass;

    loadAppList(proxyApps);
  } catch (e) {
    alert("配置加载失败：" + e.message);
  }
}

// 加载应用列表（无改动）
async function loadAppList(selectedApps) {
  try {
    const res = await fetch('/get_apps');
    const apps = await res.json();
    const appList = document.getElementById("app-list");
    appList.innerHTML = "";
    apps.forEach(app => {
      const checked = selectedApps.includes(app.pkg) ? "checked" : "";
      appList.innerHTML += `<label><input type="checkbox" class="app-checkbox" value="${app.pkg}" ${checked}>${app.name} (${app.pkg})</label><br>`;
    });
  } catch (e) {
    document.getElementById("app-list").innerHTML = "应用列表加载失败";
  }
}

// 获取远程公告（无改动）
async function fetchNotice() {
  try {
    const res = await fetch('/get_notice');
    document.getElementById("notice-content").textContent = await res.text();
  } catch (e) {
    document.getElementById("notice-content").textContent = "公告获取失败";
  }
}

// 保存配置（仅保存可配置项，无 IP/端口）
async function saveConfig() {
  try {
    const proxySwitch = document.getElementById("proxy-switch").checked ? 1 : 0;
    const v2raySocksUser = document.getElementById("v2ray-socks-user").value;
    const v2raySocksPass = document.getElementById("v2ray-socks-pass").value;
    const selectedApps = Array.from(document.querySelectorAll(".app-checkbox:checked")).map(e => e.value).join(" ");

    // 构造配置文件（无 IP/端口字段）
    const config = `#!/system/bin/sh
PROXY_SWITCH=${proxySwitch}
V2RAY_PROTOCOL="socks"
V2RAY_SOCKS_USER="${v2raySocksUser}"
V2RAY_SOCKS_PASS="${v2raySocksPass}"
PROXY_APPS="${selectedApps}"
REMOTE_NOTICE_URL="https://your-domain/notice.txt"
REMOTE_UPDATE_URL="https://your-domain/proxy_module_socks_fixed.zip"
  `;

    await fetch('/save_config', { method: 'POST', body: config });
    await fetch('/restart_module');
    alert("配置保存成功！模块已重启");
  } catch (e) {
    alert("配置保存失败：" + e.message);
  }
}

// 检查更新（无改动）
async function checkUpdate() {
  try {
    const res = await fetch('/update');
    alert(await res.text());
  } catch (e) {
    alert("更新检查失败：" + e.message);
  }
}

window.onload = () => {
  loadConfig();
  fetchNotice();
};
