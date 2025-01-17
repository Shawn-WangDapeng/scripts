#!/bin/bash
# v2ray centos系统一键安装教程
# Author: hijk<https://hijk.art>

RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

OS=`hostnamectl | grep -i system | cut -d: -f2`

V6_PROXY=""
IP=`curl -sL -4 ip.sb`
if [[ "$?" != "0" ]]; then
    IP=`curl -sL -6 ip.sb`
    V6_PROXY="https://gh.hijk.art/"
fi

CONFIG_FILE="/etc/v2ray/config.json"

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

checkSystem() {
    result=$(id | awk '{print $1}')
    if [ $result != "uid=0(root)" ]; then
        colorEcho $RED " 请以root身份执行该脚本"
        exit 1
    fi

    if [ ! -f /etc/centos-release ];then
        res=`which yum`
        if [ "$?" != "0" ]; then
            colorEcho $RED " 系统不是CentOS"
            exit 1
         fi
         res=`which systemctl`
         if [ "$?" != "0" ]; then
            colorEcho $RED " 系统版本过低，请重装系统到高版本后再使用本脚本！"
            exit 1
         fi
    else
        result=`cat /etc/centos-release|grep -oE "[0-9.]+"`
        main=${result%%.*}
        if [ $main -lt 7 ]; then
            colorEcho $RED " 不受支持的CentOS版本"
            exit 1
         fi
    fi
}

slogon() {
    clear
    echo "#############################################################"
    echo -e "#               ${RED}CentOS 7/8 V2ray一键安装脚本${PLAIN}                 #"
    echo -e "# ${GREEN}作者${PLAIN}: 网络跳越(hijk)                                      #"
    echo -e "# ${GREEN}网址${PLAIN}: https://hijk.art                                    #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://hijk.club                                   #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/hijkclub                               #"
    echo -e "# ${GREEN}Youtube频道${PLAIN}: https://youtube.com/channel/UCYTB--VsObzepVJtc9yvUxQ #"
    echo "#############################################################"
    echo ""
}

getData() {
    while true
    do
        read -p " 请输入v2ray的端口[1-65535]:" PORT
        [ -z "$PORT" ] && PORT="21568"
        if [ "${PORT:0:1}" = "0" ]; then
            echo -e " ${RED}端口不能以0开头${PLAIN}"
            exit 1
        fi
        expr $PORT + 0 &>/dev/null
        if [ $? -eq 0 ]; then
            if [ $PORT -ge 1 ] && [ $PORT -le 65535 ]; then
                echo ""
                colorEcho $BLUE " 端口号： $PORT"
                echo ""
                break
            else
                colorEcho $RED " 输入错误，端口号为1-65535的数字"
            fi
        else
            colorEcho $RED " 输入错误，端口号为1-65535的数字"
        fi
    done
}

preinstall() {
    colorEcho $BLUE " 更新系统..."
    yum clean all
    #yum update -y

    colorEcho $BLUE " 安装必要软件"
    yum install -y epel-release telnet wget vim net-tools ntpdate unzip
    res=`which wget`
    [ "$?" != "0" ] && yum install -y wget
    res=`which netstat`
    [ "$?" != "0" ] && yum install -y net-tools
    yum install -y nginx
    systemctl enable nginx && systemctl start nginx

    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        setenforce 0
    fi
}

installV2ray() {
    colorEcho $BLUE " 安装v2ray..."
    sh ./goV2.sh

    if [ ! -f $CONFIG_FILE ]; then
        colorEcho $RED " $OS 安装V2ray失败，请到 https://hijk.art 网站反馈"
        exit 1
    fi

    sed -i -e "s/port\":.*[0-9]*,/port\": ${PORT},/" $CONFIG_FILE
    alterid=`shuf -i50-80 -n1`
    sed -i -e "s/alterId\":.*[0-9]*/alterId\": ${alterid}/" $CONFIG_FILE
    uid=`grep id $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    ntpdate -u time.nist.gov
    
    systemctl enable v2ray
    systemctl restart v2ray
    sleep 3
    res=`ss -ntlp| grep ${PORT} | grep v2ray`
    if [ "${res}" = "" ]; then
        colorEcho $RED " 端口号：${PORT}， v2启动失败，请检查端口是否被占用！"
        exit 1
    fi
    colorEcho $GREEN " v2ray安装成功！"
}

setFirewall() {
    systemctl status firewalld > /dev/null 2>&1
    if [[ $? -eq 0 ]];then
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-port=${PORT}/tcp
        firewall-cmd --permanent --add-port=${PORT}/udp
        firewall-cmd --reload
    else
        nl=`iptables -nL | nl | grep FORWARD | awk '{print $1}'`
        if [[ "$nl" != "3" ]]; then
            iptables -I INPUT -p tcp --dport 80 -j ACCEPT
            iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
            iptables -I INPUT -p udp --dport ${PORT} -j ACCEPT
        fi
    fi
}

installBBR() {
    result=$(lsmod | grep bbr)
    if [ "$result" != "" ]; then
        colorEcho $YELLOW " BBR模块已安装"
        INSTALL_BBR=false
        return;
    fi

    res=`hostnamectl | grep -i openvz`
    if [ "$res" != "" ]; then
        colorEcho $YELLOW " openvz机器，跳过安装"
        INSTALL_BBR=false
        return
    fi

    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    result=$(lsmod | grep bbr)
    if [[ "$result" != "" ]]; then
        colorEcho $GREEN " BBR模块已启用"
        INSTALL_BBR=false
        return
    fi

    colorEcho $BLUE " 安装BBR模块..."
    if [[ "$V6_PROXY" = "" ]]; then
        rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
        rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-4.el7.elrepo.noarch.rpm
        yum --enablerepo=elrepo-kernel install kernel-ml -y
        grub2-set-default 0
        echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
        INSTALL_BBR=true
    fi
}

info() {
    if [ ! -f $CONFIG_FILE ]; then
        echo -e " ${RED}未安装v2ray!${PLAIN}"
        exit 1
    fi

    port=`grep port $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    res=`netstat -nltp | grep ${port} | grep v2ray`
    [ -z "$res" ] && status="${RED}已停止${PLAIN}" || status="${GREEN}正在运行${PLAIN}"
    uid=`grep id $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    alterid=`grep alterId $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    res=`grep network $CONFIG_FILE`
    [ -z "$res" ] && network="tcp" || network=`grep network $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    security="auto"
    
    raw="{
  \"v\":\"2\",
  \"ps\":\"\",
  \"add\":\"$IP\",
  \"port\":\"${port}\",
  \"id\":\"${uid}\",
  \"aid\":\"$alterid\",
  \"net\":\"tcp\",
  \"type\":\"none\",
  \"host\":\"\",
  \"path\":\"\",
  \"tls\":\"\"
}"
    link=`echo -n ${raw} | base64 -w 0`
    link="vmess://${link}"

    echo ============================================
    echo -e " ${BLUE}v2ray运行状态：${PLAIN} ${status}"
    echo -e " ${BLUE}v2ray配置文件：${PLAIN} ${RED}$CONFIG_FILE${PLAIN}"
    echo ""
    echo -e " ${RED}v2ray配置信息：${PLAIN}               "
    echo -e "   ${BLUE}IP(address):${PLAIN}   ${RED}${IP}${PLAIN}"
    echo -e "   ${BLUE}端口(port)：${PLAIN} ${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}id(uuid)：${PLAIN} ${RED}${uid}${PLAIN}"
    echo -e "   ${BLUE}额外id(alterid)：${PLAIN}  ${RED}${alterid}${PLAIN}"
    echo -e "   ${BLUE}加密方式(security)：${PLAIN}  ${RED}$security${PLAIN}"
    echo -e "   ${BLUE}传输协议(network)：${PLAIN}  ${RED}${network}${PLAIN}"
    echo
    echo -e " ${BLUE}vmess链接:${PLAIN}  $link"
}

bbrReboot() {
    if [ "$INSTALL_BBR" == "true" ]; then
        echo  
        colorEcho $BLUE " 为使BBR模块生效，系统将在30秒后重启"
        echo  
        echo -e " 您可以按 ctrl + c 取消重启，稍后输入 ${RED}reboot${PLAIN} 重启系统"
        sleep 30
        reboot
    fi
}

install() {
    echo -n "系统版本:  "
    cat /etc/centos-release

    checkSystem
    getData
    preinstall
    installBBR
    installV2ray
    setFirewall

    info
    
    bbrReboot
}

uninstall() {
    echo ""
    read -p " 确定卸载v2ray吗？(y/n)" answer
    [ -z ${answer} ] && answer="n"
    if [ "${answer}" == "y" ] || [ "${answer}" == "Y" ]; then
        systemctl stop v2ray
        systemctl disable v2ray
        rm -rf /etc/v2ray/*
        rm -rf /usr/bin/v2ray/*
        rm -rf /var/log/v2ray/*
        rm -rf /etc/systemd/system/v2ray.service
        rm -rf /etc/systemd/system/multi-user.target.wants/v2ray.service
        echo -e " ${RED}卸载成功${PLAIN}"
    fi
}

slogon

action=$1
[ -z $1 ] && action=install
case "$action" in
    install|uninstall|info)
        ${action}
        ;;
    *)
        echo " 参数错误"
        echo " 用法: `basename $0` [install|uninstall]"
        ;;
esac
