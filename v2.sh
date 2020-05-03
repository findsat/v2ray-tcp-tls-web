#!/bin/bash

if [[ $(/usr/bin/id -u) -ne 0 ]]; then
  sudoCmd="sudo"
else
  sudoCmd=""
fi

# copied from v2ray official script
# colour code
RED="31m"      # Error message
GREEN="32m"    # Success message
YELLOW="33m"   # Warning message
BLUE="36m"     # Info message
# colour function
colorEcho(){
  echo -e "\033[${1}${@:2}\033[0m" 1>& 2
}

#copied & modified from atrandys trojan scripts
#copy from 秋水逸冰 ss scripts
if [[ -f /etc/redhat-release ]]; then
  release="centos"
  systemPackage="yum"
  colorEcho ${RED} "unsupported OS"
  exit 0
elif cat /etc/issue | grep -Eqi "debian"; then
  release="debian"
  systemPackage="apt-get"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
  release="ubuntu"
  systemPackage="apt-get"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
  release="centos"
  systemPackage="yum"
  colorEcho ${RED} "unsupported OS"
  exit 0
elif cat /proc/version | grep -Eqi "debian"; then
  release="debian"
  systemPackage="apt-get"
elif cat /proc/version | grep -Eqi "ubuntu"; then
  release="ubuntu"
  systemPackage="apt-get"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
  release="centos"
  systemPackage="yum"
  colorEcho ${RED} "unsupported OS"
  exit 0
fi

get_v2ray() {
  ${sudoCmd} ${systemPackage} install curl -y
  # install v2ray
  ${sudoCmd} bash <(curl -L -s https://install.direct/go.sh)
}

install_v2ray() {
  read -p "解析到本VPS的域名: " V2_DOMAIN

  # install requirements
  # coreutils: for base64 command
  # nginx: for redirecting http to https to make dummy site look more real
  # ntp: time syncronise service
  ${sudoCmd} ${systemPackage} install curl git coreutils wget nginx ntp -y

  # install v2ray-core
  if [ ! -d "/usr/bin/v2ray"]; then
    get_v2ray
  fi

  # install tls-shunt-proxy
  if [ ! -f "/usr/local/bin/tls-shunt-proxy"]; then
    ${sudoCmd} bash <(curl -L -s https://raw.githubusercontent.com/liberal-boy/tls-shunt-proxy/master/dist/install.sh)
  fi

  cd $(mktemp -d)
  git clone https://github.com/phlinhng/v2ray-tcp-tls-web.git
  cd v2ray-tcp-tls-web

  # create config files
  uuid=$(${sudoCmd} cat /etc/v2ray/config.json | jq --raw-output '.inbounds[0].settings.clients[0].id')
  sed -i "s/FAKEUUID/${uuid}/g" config.json
  sed -i "s/FAKEDOMAIN/${V2_DOMAIN}/g" config.yaml
  sed -i "s/FAKEDOMAIN/${V2_DOMAIN}/g" default

  # copy cofig files to respective path
  ${sudoCmd} /bin/cp -f config.json /etc/v2ray
  ${sudoCmd} /bin/cp -f config.yaml /etc/tls-shunt-proxy
  ${sudoCmd} /bin/cp -f default /etc/nginx/sites-available

  # copy template for dummy web pages
  ${sudoCmd} mkdir -p /var/www/html
  ${sudoCmd} /bin/cp -rf templated-industrious/. /var/www/html

  # set crontab to auto update geoip.dat and geosite.dat
  (crontab -l 2>/dev/null; echo "0 7 * * * wget -q https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geoip.dat -O /usr/bin/v2ray/geoip.dat >/dev/null >/dev/null") | ${sudoCmd} crontab -
  (crontab -l 2>/dev/null; echo "0 7 * * * wget -q https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geosite.dat -O /usr/bin/v2ray/geosite.dat >/dev/null >/dev/null") | ${sudoCmd} crontab -

  # activate services
  ${sudoCmd} systemctl daemon-reload
  ${sudoCmd} systemctl enable ntp
  ${sudoCmd} systemctl start ntp
  ${sudoCmd} systemctl enable v2ray
  ${sudoCmd} systemctl start v2ray
  ${sudoCmd} systemctl enable tls-shunt-proxy
  ${sudoCmd} systemctl start tls-shunt-proxy
  ${sudoCmd} systemctl enable nginx
  ${sudoCmd} systemctl restart nginx

  # remove installation files
  cd ..
  rm -rf v2ray-tcp-tls-web

  colorEcho ${GREEN} "安装TCP+TLS+WEB成功!\n"
  display_vmess
}

rm_v2ray() {
  ${sudoCmd} ${systemPackage} install curl -y

  # remove v2ray
  curl -sL https://install.direct/go.sh | ${sudoCmd} bash --remove

  # remove tls-shunt-server
  ${sudoCmd} systemctl stop tls-shunt-proxy
  ${sudoCmd} systemctl disable tls-shunt-proxy.service
  ${sudoCmd} rm /etc/systemd/system/tls-shunt-proxy.service
  ${sudoCmd} rm /etc/systemd/system/tls-shunt-proxy.service # and symlinks that might be related
  ${sudoCmd} systemctl daemon-reload
  ${sudoCmd} systemctl reset-failed
  ${sudoCmd} rm -rf /usr/local/bin/tls-shunt-proxy
  ${sudoCmd} rm -rf /etc/ssl/tls-shunt-proxy
  ${sudoCmd} deluser tls-shunt-proxy

  # remove nginx
  ${sudoCmd} ${systemPackage} install purge nginx -y
  ${sudoCmd} rm -rf /etc/nginx
  colorEcho ${GREEN} "卸载TCP+TLS+WEB成功!\n"
  exit 0
}

display_vmess() {
  if [ ! -d "/usr/bin/v2ray"]; then
    colorEcho ${RED} "尚末安装v2Ray"
    break
  fi
  ${sudoCmd} ${systemPackage} install coreutils jq -y
  uuid=$(${sudoCmd} cat /etc/v2ray/config.json | jq --raw-output '.inbounds[0].settings.clients[0].id')
  V2_DOMAIN=$(${sudoCmd} cat /etc/nginx/sites-available/default | grep -e 'server_name' | sed -e 's/^[[:blank:]]server_name[[:blank:]]//g' -e 's/;//g' | tr -d '\n')

  echo "${V2_DOMAIN}:443"
  echo "${uuid} (aid: 0)\n"

  json="{\"add\":\"${V2_DOMAIN}\",\"aid\":\"0\",\"host\":\"\",\"id\":\"${uuid}\",\"net\":\"\",\"path\":\"\",\"port\":\"443\",\"ps\":\"${V2_DOMAIN}:443\",\"tls\":\"tls\",\"type\":\"none\",\"v\":\"2\"}"

  uri="$(printf "${json}" | base64)"
  echo "vmess://${uri}" | tr -d '\n'
}

generate_link() {
  if [ ! -d "/usr/bin/v2ray"]; then
    colorEcho ${RED} "尚末安装v2Ray"
    break
  fi

  if [ -f "/etc/v2ray/subscription" ]; then
    ${sudoCmd} rm -f /var/www/html/$(${sudoCmd} cat /etc/v2ray/subscription)
  fi

  ${sudoCmd} ${systemPackage} install uuid-runtime coreutils jq -y
  uuid=$(${sudoCmd} cat /etc/v2ray/config.json | jq --raw-output '.inbounds[0].settings.clients[0].id')
  V2_DOMAIN=$(${sudoCmd} cat /etc/nginx/sites-available/default | grep -e 'server_name' | sed -e 's/^[[:blank:]]server_name[[:blank:]]//g' -e 's/;//g' | tr -d '\n')

  json="{\"add\":\"${V2_DOMAIN}\",\"aid\":\"0\",\"host\":\"\",\"id\":\"${uuid}\",\"net\":\"\",\"path\":\"\",\"port\":\"443\",\"ps\":\"${V2_DOMAIN}:443\",\"tls\":\"tls\",\"type\":\"none\",\"v\":\"2\"}"

  uri="$(printf "${json}" | base64)"
  vmess="vmess://${uri}"
  sub="$(printf "vmess://${uri}" | tr -d '\n' | base64)"

  randomName= $(uuidgen | sed -e 's/-//g' | tr '[:upper:]' '[:lower:]' | head -c 16) #random file name for subscription
  printf "${randomName}" | ${sudoCmd} tee /etc/v2ray/subscription >/dev/null
  printf "${sub}" | tr -d '\n' | ${sudoCmd} tee -a /var/www/html/${randomName} >/dev/null
  echo "https://${V2_DOMAIN}/${randomName}" | tr -d '\n'
}

menu() {
  clear
  colorEcho ${YELLOW} "v2Ray TCP+TLS+WEB automated script v0.1"
  colorEcho ${YELLOW} "author: phlinhng"
  echo ""

  PS3="选择操作[输入任意值退出]: "
  options=("安装TCP+TLS+WEB" "更新v2Ray-core" "卸载TCP+TLS+WEB" "显示vmess链接" "生成订阅" "退出")
  select opt in "${options[@]}"
  do
    case $opt in
      "安装TCP+TLS+WEB")
        install_v2ray
        ;;
      "更新v2Ray-core")
        get_v2ray
        ;;
      "卸载TCP+TLS+WEB")
        rm_v2ray
        ;;
      "显示vmess链接")
        display_vmess
        ;;
      "生成订阅")
        generate_link
        ;;
      "退出")
        break
        ;;
      *) break;;
    esac
  done

}

menu
