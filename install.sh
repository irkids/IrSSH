#!/bin/bash
# hostname IrSSHPanel.link
echo "#irsshDNS
nameserver 8.8.8.8" > /etc/resolv.conf
printirssh() {
    text="$1"
    delay="$2"
    for ((i=0; i<${#text}; i++)); do
        echo -n "${text:$i:1}"
        sleep $delay
    done
    echo
}
function isRoot() {
	if [ "$EUID" -ne 0 ]; then
		return 1
	fi
}
if ! isRoot; then
	echo "Sorry, you need to run this as root"
	exit 1
fi
export PATH=$PATH:/usr/local/bin
panelporttmp=$(sudo lsof -i -P -n | grep -i LISTEN | grep litespeed | awk '{if(!seen[$9]++)print $9;exit}')
panelportt=$(echo $panelporttmp | sed 's/[^0-9]*//g' )
sed -i 's/#Port 22/Port 22/' /etc/ssh/sshd_config
po=$(cat /etc/ssh/sshd_config | grep "^Port")
port=$(echo "$po" | sed "s/Port //g")
adminuser=$(mysql -N -e "use IrSSH; select adminuser from setting where id='1';")
adminpass=$(mysql -N -e "use IrSSH; select adminpassword from setting where id='1';")

sudo wget -4 -O /usr/local/bin/irssh https://raw.githubusercontent.com/irkids/IrSSH/main/screenshot/irssh &
wait
sudo chmod a+rx /usr/local/bin/irssh

sudo wget -4 -O /usr/local/bin/irsshcheck https://raw.githubusercontent.com/irkids/IrSSH/main/screenshot/irsshcheck &
wait
sudo chmod a+rx /usr/local/bin/irsshcheck

sudo wget -4 -O /root/tls.sh.x https://github.com/irkids/IrSSH/raw/main/tls.sh.x &
wait
sudo chmod a+rx /root/tls.sh.x
sudo wget -4 -O /root/shadow.sh.x https://github.com/irkids/IrSSH/raw/main/shadow.sh.x &
wait
sudo chmod a+rx /root/shadow.sh.x
sudo wget -4 -O /root/signbox.sh.x https://github.com/irkids/IrSSH/raw/main/signbox.sh.x &
wait
sudo chmod a+rx /root/signbox.sh.x
sudo wget -4 -O /root/updatesignbox.sh.x https://github.com/irkids/IrSSH/raw/main/updatesignbox.sh.x &
wait
sudo chmod a+rx /root/updatesignbox.sh.x

if grep -q -E '^irsshsources$' /etc/apt/sources.list; then
    echo "all good, do nothing";
else
sudo sed -i '/irsshsources/d' /etc/apt/sources.list 
sudo sed -i '/ubuntu focal main restricted universe/d' /etc/apt/sources.list 
sudo sed -i '/ubuntu focal-updates main restricted universe/d' /etc/apt/sources.list 
sudo sed -i '/ubuntu focal-security main restricted universe multiverse/d' /etc/apt/sources.list 
sudo sed -i '/ubuntu focal partner/d' /etc/apt/sources.list 
echo "#irsshsources
deb http://archive.ubuntu.com/ubuntu focal main restricted universe
deb http://archive.ubuntu.com/ubuntu focal-updates main restricted universe
deb http://security.ubuntu.com/ubuntu focal-security main restricted universe multiverse
deb http://archive.canonical.com/ubuntu focal partner" >> /etc/apt/sources.list
fi

clear
echo ""
printirssh "IrSSH Panel Installation :) By MehrSam" 0.1
echo ""
echo ""
printirssh "Please Wait . . ." 0.1
echo ""
echo ""

if [ "$adminuser" != "" ]; then
adminusername=$adminuser
adminpassword=$adminpass
else
adminusername=admin
echo -e "\nPlease input Panel admin user."
printf "Default user name is \e[33m${adminusername}\e[0m, let it blank to use this user name: "
read usernametmp
if [[ -n "${usernametmp}" ]]; then
    adminusername=${usernametmp}
fi
adminpassword=123456
echo -e "\nPlease input Panel admin password."
printf "Default password is \e[33m${adminpassword}\e[0m, let it blank to use this password : "
read passwordtmp
if [[ -n "${passwordtmp}" ]]; then
    adminpassword=${passwordtmp}
fi
fi
file=/etc/systemd/system/videocall.service
if [ -e "$file" ]; then
    echo ""
else
udpport=7300
echo -e "\nPlease input UDPGW Port ."
printf "Default Port is \e[33m${udpport}\e[0m, let it blank to use this Port: "
read udpport
fi

ipv4=$(curl -s ipv4.icanhazip.com)
sudo sed -i '/www-data/d' /etc/sudoers &
wait
sudo sed -i '/litespeed/d' /etc/sudoers & 
wait

sed -i 's@#Banner none@Banner /usr/local/lsws/DEFAULT/banner.txt@' /etc/ssh/sshd_config
sed -i 's@#PrintMotd yes@PrintMotd yes@' /etc/ssh/sshd_config
sed -i 's@#PrintMotd no@PrintMotd yes@' /etc/ssh/sshd_config

if command -v apt-get >/dev/null; then
apt update -y
apt upgrade -y
rm -fr /etc/php/7.4/apache2/conf.d/00-ioncube.ini
sudo apt -y install software-properties-common
apt install shc gcc -y

sudo add-apt-repository ppa:ondrej/php -y

# نصب LiteSpeed و LSAPI
wget https://litespeedtech.com/packages/lsphp80/install.sh
bash install.sh
apt install lsphp81 lsphp81-mysql lsphp81-xml lsphp81-curl lsphp81-imagick lsphp81-zip lsphp81-intl lsphp81-mbstring lsphp81-soap lsphp81-gmp lsphp81-bcmath lsphp81-ldap lsphp81-apcu lsphp81-opcache lsphp81-redis -y
# راه‌اندازی و فعال‌سازی LiteSpeed
sudo /usr/local/lsws/bin/lswsctrl start
sudo /usr/local/lsws/bin/lswsctrl enable

# تنظیم LiteSpeed برای استفاده از PHP 8.1
# Check if PHP is correctly installed and available in the path
if ! command -v php > /dev/null 2>&1; then
    echo "PHP is not installed or not in the PATH"
    exit 1
fi

sudo ln -s /usr/local/lsws/lsphp81/bin/lsphp /usr/local/lsws/fcgi-bin/lsphp5

if [ $# == 0 ]; then
link=$(sudo curl -Ls "https://api.github.com/repos/irkids/IrSSH/releases/latest" | grep '"browser_download_url":' | sed -E 's/.*"([^"]+)".*/\1/')
sudo wget -O /usr/local/lsws/DEFAULT/update.zip $link
sudo unzip -o /usr/local/lsws/DEFAULT/update.zip -d /usr/local/lsws/DEFAULT/ &
wait
else
last_version=$1

lastzip=$(echo $last_version | sed -e 's/\.//g')
link="https://github.com/irkids/IrSSH/releases/download/$last_version/$lastzip.zip"

sudo wget -O /usr/local/lsws/DEFAULT/update.zip $link
sudo unzip -o /usr/local/lsws/DEFAULT/update.zip -d /usr/local/lsws/DEFAULT/ &
wait
fi
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/bin/systemctl restart s-box.service' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/php-cgi' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/etc/init.d/shadowsocks' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/sbin/sshd' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/sbin/adduser' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/sbin/useradd' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/sbin/userdel' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/sed' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/cat' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/passwd' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/curl' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/kill' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/killall' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/pkill' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/lsof' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/sbin/lsof' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/sed' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/rm' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/crontab' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/mysqldump' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/pgrep' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/sbin/nethogs' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/nethogs' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/local/sbin/nethogs' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/netstat' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/bin/systemctl restart sshd' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/bin/systemctl restart videocall' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/bin/systemctl restart dropbear' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/bin/systemctl daemon-reload' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/bin/systemctl restart syslog' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/local/bin/ocpasswd' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/local/bin/occtl' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/sbin/iptables' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/sbin/iptables-save' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/bin/systemctl restart tuic' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/uuidgen' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/who' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/vnstat' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/ovpm' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/bin/ovpm' | sudo EDITOR='tee -a' visudo &
wait

sudo sed -i '/%sudo/s/^/#/' /etc/sudoers &
wait

echo "application/json      json" >> /etc/mime.types

sudo /usr/local/lsws/bin/lswsctrl restart
# Check if Litespeed is running
if ! sudo /usr/local/lsws/bin/lswsctrl status | grep -q running; then
    echo "Litespeed is NOT running"
    exit 1
fi

touch /usr/local/lsws/DEFAULT/banner.txt
chown -R www-data:www-data /usr/local/lsws/DEFAULT/* &
wait

mkdir /usr/local/lsws/config/
chown www-data:www-data /usr/local/lsws/config &
wait
# Restart MariaDB to ensure it's running
sudo systemctl restart mariadb
sudo systemctl enable mariadb

wait
systemctl enable mariadb &
wait
sudo phpenmod curl
PHP_INI=$(php -i | grep /.+/php.ini -oE)
sed -i 's/extension=intl/;extension=intl/' ${PHP_INI}

IonCube=$(php -v)
if [[ $IonCube == *"PHP Loader v13"* ]]; then
  echo "IonCube Is Installed :)"
else
sed -i 's@zend_extension = /usr/local/ioncube/ioncube_loader_lin_8.1.so@@' /usr/local/lsws/lsphp81/etc/php/8.1/cli/php.ini
bash <(curl -Ls https://raw.githubusercontent.com/irkids/ioncube-loader/main/install.sh --ipv4)
fi

Nethogs=$(nethogs -V)
if [[ $Nethogs == *"version 0.8.7"* ]]; then
  echo "Nethogs Is Installed :)"
else
bash <(curl -Ls https://raw.githubusercontent.com/irkids/Nethogs-Json/main/install.sh --ipv4)
fi
file=/etc/systemd/system/videocall.service
if [ -e "$file" ]; then
    echo "SSH-CALLS exists"
else
apt install git cmake -y
git clone https://github.com/ambrop72/badvpn.git /root/badvpn
mkdir /root/badvpn/badvpn-build
cd  /root/badvpn/badvpn-build
cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 &
wait
make &
wait
cp udpgw/badvpn-udpgw /usr/local/bin
cat >  /etc/systemd/system/videocall.service << ENDOFFILE
[Unit]
Description=UDP forwarding for badvpn-tun2socks
After=nss-lookup.target

[Service]
ExecStart=/usr/local/bin/badvpn-udpgw --loglevel none --listen-addr 127.0.0.1:$udpport --max-clients 999
User=videocall

[Install]
WantedBy=multi-user.target
ENDOFFILE
useradd -m videocall
systemctl enable videocall
systemctl start videocall
fi
mysql -e "drop USER '${adminusername}'@'localhost'" &
wait

mysql -e "create database IrSSH;" &
wait
mysql -e "CREATE USER '${adminusername}'@'localhost' IDENTIFIED BY '${adminpassword}';" &
wait
mysql -e "GRANT ALL ON *.* TO '${adminusername}'@'localhost';" &
wait
sudo sed -i "s/22/$port/g" /usr/local/lsws/DEFAULT/config.php &
wait 
sudo sed -i "s/adminuser/$adminusername/g" /usr/local/lsws/DEFAULT/config.php &
wait 
sudo sed -i "s/adminpass/$adminpassword/g" /usr/local/lsws/DEFAULT/config.php &
wait 
sed -i '/panelport/d' /usr/local/lsws/DEFAULT/config.php
cat >>  /usr/local/lsws/DEFAULT/config.php << ENDOFFILE
\$panelport = "$panelportt";
ENDOFFILE

mysql -e "use IrSSH;update users set userport='' where userport like '39%';" &
wait

php /usr/local/lsws/DEFAULT/restoretarikh.php
rm -fr /usr/local/lsws/DEFAULT/update.zip

nowdate=$(date +"%Y-%m-%d-%H-%M-%S")
mysqldump -u root IrSSH > /usr/local/lsws/DEFAULT/backup/${nowdate}-update.sql

rnd=$(shuf -i 1-59 -n 1)

crontab -l | grep -v '/DEFAULT/expire.php'  | crontab  -
crontab -l | grep -v '/DEFAULT/posttraffic.php'  | crontab  -
crontab -l | grep -v '/DEFAULT/synctraffic.php'  | crontab  -
crontab -l | grep -v '/DEFAULT/tgexpire.php'  | crontab  -
crontab -l | grep -v 'DEFAULT/killusers.sh'  | crontab  -
crontab -l | grep -v '/DEFAULT/log/log.sh'  | crontab  -
crontab -l | grep -v 'DEFAULT/versioncheck.php'  | crontab  -
crontab -l | grep -v 'DEFAULT/plugins/check.php'  | crontab  -
crontab -l | grep -v 'DEFAULT/autoupdate.php'  | crontab  -
crontab -l | grep -v 'DEFAULT/checkipauto.php'  | crontab  -
crontab -l | grep -v 'ocserv'  | crontab  -
crontab -l | grep -v 'tuic'  | crontab  -
crontab -l | grep -v 'irkids/IrSSH/master/install.sh'  | crontab  -
crontab -l | grep -v '/DEFAULT/checkipauto.php'  | crontab  -
crontab -l | grep -v '/DEFAULT/log/clear.sh'  | crontab  -
(crontab -l ; echo "5 * * * * php /usr/local/lsws/DEFAULT/versioncheck.php >/dev/null 2>&1
* * * * * php /usr/local/lsws/DEFAULT/expire.php >/dev/null 2>&1
0 0 * * * php /usr/local/lsws/DEFAULT/tgexpire.php >/dev/null 2>&1
* * * * * php /usr/local/lsws/DEFAULT/posttraffic.php >/dev/null 2>&1
* * * * * bash /usr/local/lsws/DEFAULT/killusers.sh >/dev/null 2>&1
* * * * * bash /usr/local/lsws/DEFAULT/log/log.sh >/dev/null 2>&1
*/5 * * * * bash /usr/local/lsws/DEFAULT/log/clear.sh >/dev/null 2>&1" ) | crontab - &
wait
sudo timedatectl set-timezone Asia/Tehran
chmod 0646 /var/log/auth.log

sudo wget -4 -O /root/updateirssh.sh https://github.com/irkids/IrSSH/raw/main/install.sh

if  grep -q "LiteSpeed WebAdmin Console" "/usr/local/lsws/DEFAULT/index.html" ; then
cat >  /usr/local/lsws/DEFAULT/index.html << ENDOFFILE
<meta http-equiv="refresh" content="0;url=https://zula.ir/" />
ENDOFFILE
fi

if [ -e "/usr/local/lsws/DEFAULT/n.apk" ]; then
    echo "napster file"
else
echo "1"
#sudo wget -4 -O /usr/local/lsws/DEFAULT/n.apk https://my.uupload.ir/dl/4e5nRE6G &
#wait
fi
inje='/usr/local/lsws/DEFAULT/h.apk'
if [ -e "$inje" ]; then
    echo "inje file"
else
sudo wget -4 -O /usr/local/lsws/DEFAULT/h.apk https://github.com/irkids/IrSSH/raw/main/h.apk &
wait
fi

elif command -v yum >/dev/null; then
echo "Only Ubuntu Supported"
fi

cat >  /usr/local/bin/listen << ENDOFFILE
sudo lsof -i -P -n | grep LISTEN
ENDOFFILE
sudo chmod a+rx /usr/local/bin/listen
touch /usr/local/lsws/irsshak.txt
touch /usr/local/lsws/dropport.txt
touch /usr/local/lsws/cisco.txt
touch /usr/local/lsws/userlog.txt
sudo chmod 646 /usr/local/lsws/irsshak.txt
sudo chmod 646 /usr/local/lsws/dropport.txt
sudo chmod 646 /usr/local/lsws/cisco.txt
sudo chmod 646 /usr/local/lsws/userlog.txt
sudo chmod 646 /etc/default/dropbear

touch /etc/ocserv/ocpasswd

echo "
Include "/usr/local/lsws/banner.conf"
" >> /etc/ssh/sshd_config
sed -i '/Match User/d' /etc/ssh/sshd_config
sed -i '/Banner /d' /etc/ssh/sshd_config

JAILPATH='/jailed'
mkdir -p $JAILPATH
if ! getent group jailed > /dev/null 2>&1
then
  echo "creating jailed group"
  groupadd -r jailed
fi
if ! grep -q "Match group jailed" /etc/ssh/sshd_config
then
  echo "Users Limited From SSH Login"
  echo "
Match group jailed
ForceCommand /bin/false
" >> /etc/ssh/sshd_config
fi

sudo sed -i '/AllowTCPForwarding no/d' /etc/ssh/sshd_config &
wait
sudo sed -i 's@ChrootDirectory /jailed@ForceCommand /bin/false@' /etc/ssh/sshd_config &
wait
sudo sed -i '/X11Forwarding no/d' /etc/ssh/sshd_config &
wait

systemctl restart sshd

rm -fr /usr/local/lsws/DEFAULT/favicon.ico
rm -fr /usr/local/lsws/DEFAULT/favicon.svg

apt install lsphp81-cgi -y
apt install lsphp81-sqlite3 -y

rm -fr /var/log/shadowsocks.log
sudo /etc/init.d/shadowsocks restart

clear
printf "%s" "$(</usr/local/lsws/DEFAULT/irssh.txt)"

Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Font_color_suffix="\033[0m"
IonCube=$(php -v)
if [[ $IonCube == *"PHP Loader v13"* ]]; then
  echo -e "\n${Green_font_prefix}IonCube Is Installed${Font_color_suffix}"
else
echo -e "\n${Red_font_prefix}IonCube Is NOT Installed${Font_color_suffix}"
fi
Nethogs=$(nethogs -V)
if [[ $Nethogs == *"version 0.8.7"* ]]; then
  echo -e "\n${Green_font_prefix}Nethogs Is Installed${Font_color_suffix}"
else
echo -e "\n${Red_font_prefix}Nethogs Is NOT Installed${Font_color_suffix}"
fi
string=$(php -v)
if [[ $string == *"8.1"* ]]; then
  echo -e "\n${Green_font_prefix}PHP8.1 Is Installed${Font_color_suffix}"
else
echo -e "\n${Red_font_prefix}PHP8.1 Is NOT Installed${Font_color_suffix}"
fi
if [ -e "$file" ]; then
echo -e "\n${Green_font_prefix}SSH-Calls Is Installed${Font_color_suffix}"
else
echo -e "\n${Red_font_prefix}SSH-Calls Is NOT Installed${Font_color_suffix}"
fi

printf "\n\n\nPanel Link : http://${ipv4}/p"
printf "\nUserName : \e[31m${adminusername}\e[0m "
printf "\nPassword : \e[31m${adminpassword}\e[0m "
printf "\nPort : \e[31m${port}\e[0m \n"
printf "\nNOW You Can Use ${Green_font_prefix}irssh${Font_color_suffix} and ${Green_font_prefix}irsshcheck${Font_color_suffix} Command To See Menu Of IrSSH Panel \n"
