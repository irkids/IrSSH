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
