#!/bin/sh
random() {
	tr </dev/urandom -dc A-Za-z0-9 | head -c5
	echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
prefix=`echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"`
echo "" > /root/ipv6_list.txt
gen64() {
	ip64() {
		echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
	}
	GEN_IP=`echo "$1:6800:$prefix:$(ip64):$(ip64)"`
	echo $GEN_IP >> /root/ipv6_list.txt
	echo $GEN_IP
}

install_3proxy() {
    echo "Installing 3proxy"
    URL="https://raw.githubusercontent.com/hautph/vinahost/main/3proxy-0.9.4.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    mv 3proxy-0.9.4 3proxy
    cd 3proxy
    make -f Makefile.Linux
    mkdir -p /etc/3proxy/{bin,logs,stat}
    cp ./bin/3proxy /bin/3proxy
    cp ./scripts/init.d/3proxy.sh /etc/init.d/3proxy
    chmod +x /etc/init.d/3proxy
    chkconfig 3proxy on
    cd $WORKDIR
}

gen_3proxy() {
    cat <<EOF
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong

users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})

$(awk -F "/" '{print "auth iponly\n" \
"#allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 }' ${WORKDATA})
EOF
}

upload_proxy() {
    local PASS=$(random)
    zip --password $PASS proxy.zip proxy.txt
    URL=$(curl -s --upload-file proxy.zip https://upload.vina-host.com/proxy.zip)

    echo "Proxy is ready! Format IP:PORT:LOGIN:PASS"
    echo "Download zip archive from: ${URL}"
    echo "Password: ${PASS}"

}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

#gen_iptables() {
#    cat <<EOF
#    $(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA}) 
#EOF
#}

DEVICE=`ip -6 route ls | grep default | grep -Po '(?<=dev )(\S+)'`
gen_ifconfig() {
	while read line
	do
		ip=`echo $line | cut -f5 -d"/"`
		echo "ifconfig $DEVICE inet6 add $ip/69"
	done < ${WORKDATA}
}
echo "Installing apps"
yum -y install gcc net-tools bsdtar zip psmisc >/dev/null

install_3proxy

echo "Working folder = /home/vinahost"
WORKDIR="/home/vinahost"
WORKDATA="${WORKDIR}/data.txt"
mkdir $WORKDIR && cd $_

#service network restart

echo "Checking ipv4 & ipv6"

IP4=$(curl -4 -s icanhazip.com)

IP6=$(curl -6 -s icanhazip.com | cut -f 1-4 -d":")

echo "Internal ip = ${IP4}. External sub for ip6 = ${IP6}"

#echo "How many proxy do you want to create? Example 100"
#read COUNT

COUNT=500

FIRST_PORT=30000
LAST_PORT=$(($FIRST_PORT + $COUNT))

gen_data >$WORKDIR/data.txt
#gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
#chmod +x boot_*.sh /etc/rc.local

gen_3proxy >/etc/3proxy/3proxy.cfg

cat >>/etc/rc.local <<EOF
#bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 10048
service 3proxy start
EOF

bash /etc/rc.local

gen_proxy_file_for_user

upload_proxy
