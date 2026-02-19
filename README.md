# Arch Linux 的 DE/WM 安装脚本

> [!WARNING]
>
> 使用该安装脚本需自备代理，否则无法正常工作。
>

仓库复刻自 [shorin-arch-setup](https://github.com/SHORiN-KiWATA/shorin-arch-setup)。

## 使用方法

安装系统，登录之后从 tty 运行以下命令

### 安装 git

```sh
sudo pacman -Syu git
```

### 克隆仓库

```sh
git clone https://github.com/Mugzx/arch-setup.git
```

### 进入目录并运行

```sh
cd arch-setup && sudo bash install.sh
```

## 目录结构

```sh
.
├── kde-dotfiles # KDE Plasma 配置
├── niri-dotfiles # Niri 配置
│   └── wallpapers # Waypaper 壁纸目录★
├── scripts # 安装脚本
│   ├── 00-btrfs-init.sh # Btrfs文件系统初始化
│   ├── 00-utils.sh # 工具函数和通用变量定义
│   ├── 01-base.sh # 基础系统安装
│   ├── 02a-dualboot-fix.sh # 系统引导
│   ├── 02-musthave.sh # 必备软件安装
│   ├── 03-user.sh # 用户账户和权限配置
│   ├── 04-niri-setup.sh # Niri 安装和配置
│   ├── 06-kdeplasma-setup.sh # KDE Plasma 安装和配置
│   ├── 99-apps.sh # 安装应用列表中的软件包
│   └── niri-undochange.sh # 快照回档 (Niri)
├── exclude-dotfiles.txt # 需要排除的配置★
├── install.sh # 主安装脚本，调用其他脚本完成系统安装
├── kde-applist.txt # KDE (KDE Plasma 桌面环境)
├── kde-common-applist.txt # KDE 常用软件应用列表★
├── niri-applist.txt # Niri (Niri 窗口管理器)
├── niri-common-applist.txt # Niri 常用软件应用列表★
└── undochange.sh # 快照回档
```

有特殊标记的目录/文件建议按个人习惯自行调整。

## 方法解决

部分依赖脚本的功能可能无法正常工作，需要前往以下路径设置脚本「作为程序运行」：
- `~/.config/niri/scripts/`
- `~/.config/waybar/scripts/`

```sh
chmod +x *.sh
```

## 一些说明

- 原作者的 Git 提交并不规范，所以我自己新开了一个仓库存放这些配置文件。
- 这个仓库更多按照个人习惯进行配置。
