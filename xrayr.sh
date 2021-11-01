#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# Current folder
cur_dir=$(pwd)
# Color
red='\033[0;31m'
green='\033[0;32m'
#yellow='\033[0;33m'
plain='\033[0m'
operation=(全新安装 更新配置 更新镜像 查看日志 重启后端 删除后端)
# Make sure only root can run our script
[[ $EUID -ne 0 ]] && echo -e "[${red}Error${plain}] 你没权没势 请先获取ROOT权限!" && exit 1

#Check system
check_sys() {
  local checkType=$1
  local value=$2
  local release=''
  local systemPackage=''

  if [[ -f /etc/redhat-release ]]; then
    release="centos"
    systemPackage="yum"
  elif grep -Eqi "debian|raspbian" /etc/issue; then
    release="debian"
    systemPackage="apt"
  elif grep -Eqi "ubuntu" /etc/issue; then
    release="ubuntu"
    systemPackage="apt"
  elif grep -Eqi "centos|red hat|redhat" /etc/issue; then
    release="centos"
    systemPackage="yum"
  elif grep -Eqi "debian|raspbian" /proc/version; then
    release="debian"
    systemPackage="apt"
  elif grep -Eqi "ubuntu" /proc/version; then
    release="ubuntu"
    systemPackage="apt"
  elif grep -Eqi "centos|red hat|redhat" /proc/version; then
    release="centos"
    systemPackage="yum"
  fi

  if [[ "${checkType}" == "sysRelease" ]]; then
    if [ "${value}" == "${release}" ]; then
      return 0
    else
      return 1
    fi
  elif [[ "${checkType}" == "packageManager" ]]; then
    if [ "${value}" == "${systemPackage}" ]; then
      return 0
    else
      return 1
    fi
  fi
}

# Get version
getversion() {
  if [[ -s /etc/redhat-release ]]; then
    grep -oE "[0-9.]+" /etc/redhat-release
  else
    grep -oE "[0-9.]+" /etc/issue
  fi
}

# CentOS version
centosversion() {
  if check_sys sysRelease centos; then
    local code=$1
    local version="$(getversion)"
    local main_ver=${version%%.*}
    if [ "$main_ver" == "$code" ]; then
      return 0
    else
      return 1
    fi
  else
    return 1
  fi
}

get_char() {
  SAVEDSTTY=$(stty -g)
  stty -echo
  stty cbreak
  dd if=/dev/tty bs=1 count=1 2>/dev/null
  stty -raw
  stty echo
  stty $SAVEDSTTY
}
error_detect_depends() {
  local command=$1
  local depend=$(echo "${command}" | awk '{print $4}')
  echo -e "[${green}Info${plain}] 开始安装软件包 ${depend}"
  ${command} >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo -e "[${red}Error${plain}] 软件包安装失败 ${red}${depend}${plain}"
    exit 1
  fi
}

# Pre-installation settings
pre_install_docker_compose() {
  read -p "前端节点信息里面的节点ID:" node_id
  [ -z "${node_id}" ] && node_id=0
  read -p "前端面板域名(包括https://):" api_host
  [ -z "${api_host}" ] && api_host="http://8.8.8.8"
  read -p "前端面板的apikey:" api_key
  [ -z "${api_key}" ] && api_key="123"
  echo -e "[1] SSpanel"
  echo -e "[2] V2board"
  read -p "前端面板类型:" panel_num
  if [ "$panel_num" == "1" ]; then
    panel_type="SSpanel"
  elif [ "$panel_num" == "2" ]; then
    panel_type="V2board"
  else
    echo "type error, please try again"
    exit
  fi
  echo -e "[1] V2ray"
  echo -e "[2] Shadowsocks"
  echo -e "[3] Trojan"
  echo -e "[4] Shadowsocks-Plugin"
  read -p "节点类型:" node_num
  if [ "$node_num" == "1" ]; then
    node_type="V2ray"
  elif [ "$node_num" == "2" ]; then
    node_type="Shadowsocks"
  elif [ "$node_num" == "3" ]; then
    node_type="Trojan"
  elif [ "$node_num" == "4" ]; then
    node_type="Shadowsocks-Plugin"
  else
    echo "type error, please try again"
    exit
  fi
  echo -e "[1] 是"
  echo -e "[2] 否"
  read -p "是否开启tls/xtls（默认否）:" is_tls
  if [ "$is_tls" == "1" ]; then
    read -p "请输入解析到本机的域名:" cert_domain
    echo -e "[1] 是"
    echo -e "[2] 否"
    read -p "是否开启xtls（默认否）:" is_xtls
    echo -e "[1] 是"
    echo -e "[2] 否"
    read -p "是否开启vless（默认否）:" is_vless
  fi
}

# Config docker
config_docker() {
  cd ${cur_dir} || exit
  echo "开始安装软件包"
  install_dependencies
  echo "加载DOCKER配置文件"
  cat >docker-compose.yml <<EOF
version: '3'
services: 
  xrayr: 
    image: crackair/xrayr:latest
    volumes:
      - ./config.yml:/etc/XrayR/config.yml # 映射配置文件夹
      - ./dns.json:/etc/XrayR/dns.json 
    restart: always
    network_mode: host
EOF
  cat >dns.json <<EOF
{
    "servers": [
        "1.1.1.1",
        "8.8.8.8",
        "localhost"
    ],
    "tag": "dns_inbound"
}
EOF
  cat >config.yml <<EOF
Log:
  Level: none # Log level: none, error, warning, info, debug 
  AccessPath: # /etc/XrayR/access.Log
  ErrorPath: # /etc/XrayR/error.log
DnsConfigPath: # /etc/XrayR/dns.json # Path to dns config, check https://xtls.github.io/config/base/dns/ for help
RouteConfigPath: # /etc/XrayR/route.json # Path to route config, check https://xtls.github.io/config/base/route/ for help
OutboundConfigPath: # /etc/XrayR/custom_outbound.json # Path to custom outbound config, check https://xtls.github.io/config/base/outbound/ for help
ConnetionConfig:
  Handshake: 4 # Handshake time limit, Second
  ConnIdle: 30 # Connection idle time limit, Second
  UplinkOnly: 2 # Time limit when the connection downstream is closed, Second
  DownlinkOnly: 4 # Time limit when the connection is closed after the uplink is closed, Second
  BufferSize: 64 # The internal cache size of each connection, kB 
Nodes:
  -
    PanelType: "SSpanel" # Panel type: SSpanel, V2board, PMpanel, , Proxypanel
    ApiConfig:
      ApiHost: "http://8.8.8.8"
      ApiKey: "123"
      NodeID: 41
      NodeType: V2ray # Node type: V2ray, Shadowsocks, Trojan, Shadowsocks-Plugin
      Timeout: 30 # Timeout for the api request
      EnableVless: false # Enable Vless for V2ray Type
      EnableXTLS: false # Enable XTLS for V2ray and Trojan
      SpeedLimit: 0 # Mbps, Local settings will replace remote settings, 0 means disable
      DeviceLimit: 0 # Local settings will replace remote settings, 0 means disable
      RuleListPath: # ./rulelist Path to local rulelist file
    ControllerConfig:
      ListenIP: 0.0.0.0 # IP address you want to listen
      SendIP: 0.0.0.0 # IP address you want to send pacakage
      UpdatePeriodic: 60 # Time to update the nodeinfo, how many sec.
      EnableDNS: false # Use custom DNS config, Please ensure that you set the dns.json well
      DNSType: AsIs # AsIs, UseIP, UseIPv4, UseIPv6, DNS strategy
      EnableProxyProtocol: false # Only works for WebSocket and TCP
      EnableFallback: false # Only support for Trojan and Vless
      FallBackConfigs:  # Support multiple fallbacks
        -
          SNI: # TLS SNI(Server Name Indication), Empty for any
          Path: # HTTP PATH, Empty for any
          Dest: 80 # Required, Destination of fallback, check https://xtls.github.io/config/fallback/ for details.
          ProxyProtocolVer: 0 # Send PROXY protocol version, 0 for dsable
      CertConfig:
        CertMode: dns # Option about how to get certificate: none, file, http, dns. Choose "none" will forcedly disable the tls config.
        CertDomain: "node1.test.com" # Domain to cert
        CertFile: ./cert/node1.test.com.cert # Provided if the CertMode is file
        KeyFile: ./cert/node1.test.com.key
        Provider: alidns # DNS cert provider, Get the full support list here: https://go-acme.github.io/lego/dns/
        Email: test@me.com
        DNSEnv: # DNS ENV option used by DNS provider
          ALICLOUD_ACCESS_KEY: aaa
          ALICLOUD_SECRET_KEY: bbb
EOF
  sed -i "s|NodeID:.*|NodeID: ${node_id}|" ./config.yml
  sed -i "s|ApiHost:.*|ApiHost: \"${api_host}\"|" ./config.yml
  sed -i "s|ApiKey:.*|ApiKey: \"${api_key}\"|" ./config.yml
  sed -i "s|PanelType:.*|PanelType: \"${panel_type}\"|" ./config.yml
  sed -i "s|NodeType:.*|NodeType: ${node_type}|" ./config.yml
  if [ "$is_tls" == "1" ]; then
    sed -i "s|CertMode:.*|CertMode: http|" ./config.yml
    sed -i "s|CertDomain:.*|CertDomain: \"${cert_domain}\"|" ./config.yml
  fi
  if [ "$is_xtls" == "1" ]; then
    sed -i "s|EnableXTLS:.*|EnableXTLS: true|" ./config.yml
  fi
  if [ "$is_vless" == "1" ]; then
    sed -i "s|EnableVless:.*|EnableVless: true|" ./config.yml
  fi
}

# Install docker and docker compose
install_docker() {
  echo -e "开始安装 DOCKER "
  docker version >/dev/null || curl -fsSL get.docker.com | bash
  service docker restart
  systemctl enable docker
  service postfix stop
  systemctl disable postfix
  echo -e "开始安装 Docker Compose "
  curl -L https://github.com/docker/compose/releases/download/1.17.1/docker-compose-$(uname -s)-$(uname -m) >/usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  curl -L https://raw.githubusercontent.com/docker/compose/1.8.0/contrib/completion/bash/docker-compose >/etc/bash_completion.d/docker-compose
  clear
  echo "启动 Docker "
  service docker start
  echo "启动 Docker-Compose "
  docker-compose up -d
  echo
  echo -e "后端安装完成！"
  echo -e "0 0 */3 * *  cd /root/${cur_dir} && /usr/local/bin/docker-compose pull && /usr/local/bin/docker-compose up -d" >>/etc/crontab
  echo -e "后端定时更新设置完成！(3天一次)"
}

install_check() {
  if check_sys packageManager yum || check_sys packageManager apt; then
    if centosversion 5; then
      return 1
    fi
    return 0
  else
    return 1
  fi
}

install_dependencies() {
  if check_sys packageManager yum; then
    echo -e "[${green}Info${plain}] 检查EPEL存储库..."
    if [ ! -f /etc/yum.repos.d/epel.repo ]; then
      yum install -y epel-release >/dev/null 2>&1
    fi
    [ ! -f /etc/yum.repos.d/epel.repo ] && echo -e "[${red}Error${plain}] 安装EPEL储存库失败，请检查一下." && exit 1
    [ ! "$(command -v yum-config-manager)" ] && yum install -y yum-utils >/dev/null 2>&1
    [ x"$(yum-config-manager epel | grep -w enabled | awk '{print $3}')" != x"True" ] && yum-config-manager --enable epel >/dev/null 2>&1
    echo -e "[${green}Info${plain}] 检查EPEL储存库是否完整..."

    yum_depends=(
      curl
    )
    for depend in ${yum_depends[@]}; do
      error_detect_depends "yum -y install ${depend}"
    done
  elif check_sys packageManager apt; then
    apt_depends=(
      curl
    )
    apt-get -y update
    for depend in ${apt_depends[@]}; do
      error_detect_depends "apt-get -y install ${depend}"
    done
  fi
  echo -e "[${green}Info${plain}] 将时区设置为上海"
  ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
  date -s "$(curl -sI g.cn | grep Date | cut -d' ' -f3-6)Z"

}

#update_image
更新镜像_xrayr() {
  cd ${cur_dir}
  echo "关闭当前服务"
  docker-compose down
  echo "加载DOCKER镜像"
  docker-compose pull
  echo "开始运行DOKCER服务"
  docker-compose up -d
}

#show last 100 line log

查看日志_xrayr() {
  echo "将要显示100行的运行日志"
  docker-compose logs --tail 100
}

# Update config
更新配置_xrayr() {
  cd ${cur_dir}
  echo "关闭当前服务"
  docker-compose down
  pre_install_docker_compose
  config_docker
  echo "开始运行DOKCER服务"
  docker-compose up -d
}
重启后端_xrayr() {
  cd ${cur_dir}
  docker-compose down
  docker-compose up -d
  echo "重启成功！"
}
删除后端_xrayr() {
  cd ${cur_dir}
  docker-compose down
  cd ~
  rm -Rf ${cur_dir}
  echo "删除成功！"
}
# Install xrayr
全新安装_xrayr() {
  pre_install_docker_compose
  config_docker
  install_docker
}

# Initialization step
clear
while true; do
  echo "-----XrayR onekey-----"
  echo "项目地址及帮助文档:  https://github.com/KANIKIG/XrayR_onekey"
  echo "请输入数字选择你要进行的操作："
  for ((i = 1; i <= ${#operation[@]}; i++)); do
    hint="${operation[$i - 1]}"
    echo -e "${green}${i}${plain}) ${hint}"
  done
  read -p "请选择数字后回车 (回车默认 ${operation[0]}):" selected
  [ -z "${selected}" ] && selected="1"
  case "${selected}" in
  1 | 2 | 3 | 4 | 5 | 6 | 7)
    echo
    echo "你的想法 = ${operation[${selected} - 1]}"
    echo
    ${operation[${selected} - 1]}_xrayr
    break
    ;;
  *)
    echo -e "[${red}Error${plain}] 请输入正确数字 [1-4]"
    ;;
  esac
done
