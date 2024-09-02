#!/bin/bash
# hostname ShahanPanel.link
echo "#shahanDNS
nameserver 8.8.8.8" > /etc/resolv.conf

printshahan() {
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

# این قسمت برای پیدا کردن پورت لایت اسپید و حذف تنظیمات مرتبط با آپاچی تغییر کرده است
panelporttmp=$(sudo lsof -i -P -n | grep -i LISTEN | grep litespeed | awk '{if(!seen[$9]++)print $9;exit}')
panelportt=$(echo $panelporttmp | sed 's/[^0-9]*//g')

sed -i 's/#Port 22/Port 22/' /etc/ssh/sshd_config
po=$(cat /etc/ssh/sshd_config | grep "^Port")
port=$(echo "$po" | sed "s/Port //g")
adminuser=$(mysql -N -e "use ShaHaN; select adminuser from setting where id='1';")
adminpass=$(mysql -N -e "use ShaHaN; select adminpassword from setting where id='1';")

# نصب لایت اسپید به جای آپاچی
sudo wget -4 -O /usr/local/bin/shahan https://raw.githubusercontent.com/HamedAp/Ssh-User-management/main/screenshot/shahan &
wait
sudo chmod a+rx /usr/local/bin/shahan

sudo wget -4 -O /usr/local/bin/shahancheck https://raw.githubusercontent.com/HamedAp/Ssh-User-management/main/screenshot/shahancheck &
wait
sudo chmod a+rx /usr/local/bin/shahancheck

sudo wget -4 -O /root/tls.sh.x https://github.com/HamedAp/Ssh-User-management/raw/main/tls.sh.x &
wait
sudo chmod a+rx /root/tls.sh.x
sudo wget -4 -O /root/shadow.sh.x https://github.com/HamedAp/Ssh-User-management/raw/main/shadow.sh.x &
wait
sudo chmod a+rx /root/shadow.sh.x
sudo wget -4 -O /root/signbox.sh.x https://github.com/HamedAp/Ssh-User-management/raw/main/signbox.sh.x &
wait
sudo chmod a+rx /root/signbox.sh.x
sudo wget -4 -O /root/updatesignbox.sh.x https://github.com/HamedAp/Ssh-User-management/raw/main/updatesignbox.sh.x &
wait
sudo chmod a+rx /root/updatesignbox.sh.x

if grep -q -E '^shahansources$' /etc/apt/sources.list; then
    echo "all good, do nothing";
else
sudo sed -i '/shahansources/d' /etc/apt/sources.list 
sudo sed -i '/ubuntu focal main restricted universe/d' /etc/apt/sources.list 
sudo sed -i '/ubuntu focal-updates main restricted universe/d' /etc/apt/sources.list 
sudo sed -i '/ubuntu focal-security main restricted universe multiverse/d' /etc/apt/sources.list 
sudo sed -i '/ubuntu focal partner/d' /etc/apt/sources.list 
echo "#shahansources
deb http://archive.ubuntu.com/ubuntu focal main restricted universe
deb http://archive.ubuntu.com/ubuntu focal-updates main restricted universe
deb http://security.ubuntu.com/ubuntu focal-security main restricted universe multiverse
deb http://archive.canonical.com/ubuntu focal partner" >> /etc/apt/sources.list
fi

clear
echo ""
printshahan "ShaHaN Panel Installation :) By HamedAp" 0.1
echo ""
echo ""
printshahan "Please Wait . . ." 0.1
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
sudo sed -i '/apache/d' /etc/sudoers & 
wait

sed -i 's@#Banner none@Banner /var/www/html/p/banner.txt@' /etc/ssh/sshd_config
sed -i 's@#PrintMotd yes@PrintMotd yes@' /etc/ssh/sshd_config
sed -i 's@#PrintMotd no@PrintMotd yes@' /etc/ssh/sshd_config

if command -v apt-get >/dev/null; then

apt update -y
apt upgrade -y
rm -fr /etc/php/7.4/apache2/conf.d/00-ioncube.ini
sudo apt -y install software-properties-common
apt install shc gcc -y

sudo add-apt-repository ppa:ondrej/php -y
apt install lsphp8.1 lsphp8.1-sqlite3 lsphp8.1-mysql lsphp8.1-xml lsphp8.1-curl mariadb-server iptables-persistent vnstat -y

string=$(lsphp -v)
if [[ $string == *"8.1"* ]]; then
apt autoremove -y
  echo "PHP Is Installed :)"
else
apt remove lsphp7* -y &
wait
apt remove lsphp* -y
apt remove lsphp -y
apt autoremove -y
apt install lsphp8.1 lsphp8.1-mbstring cron -y
fi

# تنظیمات و نصب لایت اسپید به جای آپاچی
sudo apt install openlitespeed -y
sudo /usr/local/lsws/bin/lswsctrl start

if [ $# == 0 ]; then
link=$(sudo curl -Ls "https://api.github.com/repos/HamedAp/Ssh-User-management/releases/latest" | grep '"browser_download_url":' | sed -E 's/.*"([^"]+)".*/\1/')
sudo wget -O /usr/local/lsws/DEFAULT/html/update.zip $link
sudo unzip -o /usr/local/lsws/DEFAULT/html/update.zip -d /usr/local/lsws/DEFAULT/html/ &
wait
else
last_version=$1
lastzip=$(echo $last_version | sed -e 's/\.//g')
link="https://github.com/HamedAp/Ssh-User-management/releases/download/$last_version/$lastzip.zip"
sudo wget -O /usr/local/lsws/DEFAULT/html/update.zip $link
sudo unzip -o /usr/local/lsws/DEFAULT/html/update.zip -d /usr/local/lsws/DEFAULT/html/ &
wait
fi

# تنظیمات visudo برای وب سرور لایت اسپید
echo 'nobody ALL=(ALL:ALL) NOPASSWD:/bin/systemctl restart s-box.service' | sudo EDITOR='tee -a' visudo &
wait
echo 'nobody ALL=(ALL:ALL) NOPASSWD:/usr/bin/php-cgi' | sudo EDITOR='tee -a' visudo &
wait
# و بقیه دستورات مشابه برای nobody که کاربر پیش‌فرض لایت اسپید است
echo 'nobody ALL=(ALL:ALL) NOPASSWD:/usr/sbin/sshd' | sudo EDITOR='tee -a' visudo &
wait

# تغییرات مرتبط با فایل‌های پیکربندی
sudo sed -i "s/22/$port/g" /usr/local/lsws/DEFAULT/html/p/config.php &
wait 
sudo sed -i "s/adminuser/$adminusername/g" /usr/local/lsws/DEFAULT/html/p/config.php &
wait 
sudo sed -i "s/adminpass/$adminpassword/g" /usr/local/lsws/DEFAULT/html/p/config.php &
wait 

sudo iptables -I INPUT -p udp --dport 7300 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport $panelportt -j ACCEPT

systemctl start mariadb &
wait 
systemctl enable mariadb &
wait 
sudo mysql -e "SET PASSWORD FOR root@localhost = PASSWORD('');" 2>/dev/null

else
yum install sudo wget curl mariadb-server vnstat nano -y
systemctl enable mariadb &
wait 
systemctl start mariadb &
wait 
systemctl start crond &
wait 

# دستور نصب لایت اسپید روی توزیع‌های RHEL/CentOS
sudo yum install openlitespeed -y
sudo /usr/local/lsws/bin/lswsctrl start

if [ $# == 0 ]; then
link=$(sudo curl -Ls "https://api.github.com/repos/HamedAp/Ssh-User-management/releases/latest" | grep '"browser_download_url":' | sed -E 's/.*"([^"]+)".*/\1/')
sudo wget -O /usr/local/lsws/DEFAULT/html/update.zip $link
sudo unzip -o /usr/local/lsws/DEFAULT/html/update.zip -d /usr/local/lsws/DEFAULT/html/ &
wait
else
last_version=$1
lastzip=$(echo $last_version | sed -e 's/\.//g')
link="https://github.com/HamedAp/Ssh-User-management/releases/download/$last_version/$lastzip.zip"
sudo wget -O /usr/local/lsws/DEFAULT/html/update.zip $link
sudo unzip -o /usr/local/lsws/DEFAULT/html/update.zip -d /usr/local/lsws/DEFAULT/html/ &
wait
fi

# پیکربندی‌های visudo برای لایت اسپید
echo 'nobody ALL=(ALL:ALL) NOPASSWD:/bin/systemctl restart s-box.service' | sudo EDITOR='tee -a' visudo &
wait
echo 'nobody ALL=(ALL:ALL) NOPASSWD:/usr/bin/php-cgi' | sudo EDITOR='tee -a' visudo &
wait
# و دستورات مشابه برای nobody
echo 'nobody ALL=(ALL:ALL) NOPASSWD:/usr/sbin/sshd' | sudo EDITOR='tee -a' visudo &
wait

sudo sed -i "s/22/$port/g" /usr/local/lsws/DEFAULT/html/p/config.php &
wait 
sudo sed -i "s/adminuser/$adminusername/g" /usr/local/lsws/DEFAULT/html/p/config.php &
wait 
sudo sed -i "s/adminpass/$adminpassword/g" /usr/local/lsws/DEFAULT/html/p/config.php &
wait 

iptables -I INPUT -p udp --dport 7300 -j ACCEPT
iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -p tcp --dport 443 -j ACCEPT
iptables -I INPUT -p tcp --dport $panelportt -j ACCEPT

fi
