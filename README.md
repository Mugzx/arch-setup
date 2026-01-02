
此 Arch Setup 复刻自[SHORiN-KiWATA/shorin-arch-setup](https://github.com/SHORiN-KiWATA/shorin-arch-setup)。

## 使用方法

1. 安装一个 ArchLinux 系统

2. 登录之后从 tty 运行以下命令
    
    ```
    # 1. 安装 git
    sudo pacman -Syu git

    # 2. 克隆仓库
    git clone https://github.com/Mugzx/arch-setup.git

    # 3. 进入目录并运行
    cd arch-setup
    sudo bash install.sh
    ```
    - 一条命令版

        ```
        sudo pacman -Syu git && git clone https://github.com/Mugzx/arch-setup.git && cd arch-setup && sudo bash install.sh
        ```

## 一些说明

- 原作者的 Git 提交并不规范，所以我自己新开了一个仓库存放这些配置文件🫠。
