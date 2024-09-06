import os

def install_tuic():
    print("Installing TUIC...")
    os.system("git clone https://github.com/tuic/tuic.git")
    os.system("cd tuic && ./install.sh")

def install_shadowsocks():
    print("Installing Shadowsocks...")
    os.system("apt install -y shadowsocks-libev")

def install_wireguard():
    print("Installing WireGuard...")
    os.system("apt install -y wireguard")

def install_l2tp_ipsec():
    print("Installing L2TP/IPSec...")
    os.system("apt install -y strongswan xl2tpd")

def install_ikev2_ipsec():
    print("Installing IKEv2/IPSec...")
    os.system("apt install -y strongswan")

def install_openvpn():
    print("Installing OpenVPN...")
    os.system("apt install -y openvpn")

def install_singbox():
    print("Installing Sing-box...")
    os.system("git clone https://github.com/SagerNet/sing-box.git")
    os.system("cd sing-box && ./install.sh")

def main():
    print("Select the protocol to install:")
    print("1. TUIC")
    print("2. Shadowsocks")
    print("3. WireGuard")
    print("4. L2TP/IPSec")
    print("5. IKEv2/IPSec")
    print("6. OpenVPN")
    print("7. Sing-box")
    
    choice = input("Enter the number of the protocol: ")

    if choice == "1":
        install_tuic()
    elif choice == "2":
        install_shadowsocks()
    elif choice == "3":
        install_wireguard()
    elif choice == "4":
        install_l2tp_ipsec()
    elif choice == "5":
        install_ikev2_ipsec()
    elif choice == "6":
        install_openvpn()
    elif choice == "7":
        install_singbox()
    else:
        print("Invalid selection")

if __name__ == "__main__":
    main()

def install_l2tp():
    print("Installing L2TP/IPSec...")
    os.system("sudo apt-get install -y strongswan xl2tpd")

    # پیکربندی فایل‌های لازم برای L2TP/IPSec
    configure_l2tp_ipsec()

def configure_l2tp_ipsec():
    # ایجاد فایل تنظیمات strongswan
    with open('/etc/ipsec.conf', 'w') as f:
        f.write("""
        config setup
            charondebug="ike 2, knl 2, cfg 2"
            uniqueids=no

        conn L2TP-PSK
            keyexchange=ikev1
            authby=secret
            ike=3des-sha1-modp1024!
            phase2alg=3des-sha1
            type=transport
            left=%defaultroute
            leftprotoport=17/1701
            right=%any
            rightprotoport=17/%any
            auto=add
        """)

    # ایجاد فایل تنظیمات ipsec.secrets
    with open('/etc/ipsec.secrets', 'w') as f:
        f.write("""
        : PSK "your_pre_shared_key"
        """)

    # راه‌اندازی مجدد سرویس strongswan
    os.system("sudo systemctl restart strongswan")

    # ایجاد فایل تنظیمات xl2tpd
    with open('/etc/xl2tpd/xl2tpd.conf', 'w') as f:
        f.write("""
        [global]
        port = 1701

        [lns default]
        ip range = 192.168.1.10-192.168.1.100
        local ip = 192.168.1.1
        require chap = yes
        refuse pap = yes
        require authentication = yes
        name = L2TP-VPN
        ppp debug = yes
        pppoptfile = /etc/ppp/options.xl2tpd
        length bit = yes
        """)

    # پیکربندی فایل options.xl2tpd
    with open('/etc/ppp/options.xl2tpd', 'w') as f:
        f.write("""
        ipcp-accept-local
        ipcp-accept-remote
        ms-dns 8.8.8.8
        ms-dns 8.8.4.4
        noccp
        auth
        crtscts
        idle 1800
        mtu 1410
        mru 1410
        lock
        connect-delay 5000
        """)

    # راه‌اندازی مجدد سرویس xl2tpd
    os.system("sudo systemctl restart xl2tpd")

    print("L2TP/IPSec installed and configured.")
