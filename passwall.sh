#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
# --------------------------------------------------------------
#	使用说明：加在openwrt上系统--计划任务里添加定时运行，如：*/5 * * * * ash /etc/auto-ip/cf
#	*解释：每5分运行一次。
# --------------------------------------------------------------

# 定义目标文件夹
target_dir="/etc/auto-ip"

# 检查目标文件夹是否存在
if [ ! -d "$target_dir" ]; then
    # 如果不存在，创建文件夹
    mkdir -p "$target_dir"
fi

# 检查文件夹是否为空
if [ -z "$(ls -A "$target_dir")" ]; then
    # 如果为空，复制自身到目标文件夹
    cp "$0" "$target_dir"
    echo "已复制"
else
# 如果不为空，提示跳过
    echo "已有文件"
fi
    # 文件夹赋权
    chmod -R +x "$target_dir"

# cd到脚本所在位置
cd `dirname $0`

# 检查当前目录是否已经有CloudflareST文件
if [ -f "CloudflareST" ]; then
    echo "CloudflareST 已存在，跳过下载步骤。"
else
    # 获取系统的操作系统和架构信息
    OS=$(uname -s)
    ARCH=$(uname -m)

    # 设置下载链接前缀和后缀
    BASE_URL="https://github.com/XIU2/CloudflareSpeedTest/releases/latest/download"
    FILE_PREFIX="CloudflareST"
    FILE_SUFFIX=".tar.gz"

    # 根据操作系统和架构设置文件名
    case "$OS" in
        Linux)
            if [ "$ARCH" == "x86_64" ]; then
                FILE_NAME="${FILE_PREFIX}_linux_amd64${FILE_SUFFIX}"
            elif [ "$ARCH" == "aarch64" ]; then
                FILE_NAME="${FILE_PREFIX}_linux_arm64${FILE_SUFFIX}"
            else
                echo "不支持的架构: $ARCH"
                exit 1
            fi
            ;;
        Darwin)
            if [ "$ARCH" == "x86_64" ]; then
                FILE_NAME="${FILE_PREFIX}_darwin_amd64${FILE_SUFFIX}"
            elif [ "$ARCH" == "arm64" ]; then
                FILE_NAME="${FILE_PREFIX}_darwin_arm64${FILE_SUFFIX}"
            else
                echo "不支持的架构: $ARCH"
                exit 1
            fi
            ;;
        *)
            echo "不支持的操作系统: $OS"
            exit 1
            ;;
    esac

    # 生成完整的下载链接
    DOWNLOAD_URL="${BASE_URL}/${FILE_NAME}"

    # 下载文件
    echo "正在下载CloudflareST..."
    curl -sS -L -o "${FILE_NAME}" "${DOWNLOAD_URL}"
    
    # 检查下载是否成功
    if [ $? -ne 0 ]; then
        echo "下载失败，请检查网络连接或下载链接。"
        exit 1
    fi
    
# 检查是否已经安装了 tar
if command -v tar > /dev/null 2>&1; then
    echo "tar 已经安装，跳过安装步骤。"
else
    echo "tar 未安装，正在安装..."
    opkg update
    opkg install tar
fi

    # 解压文件
    echo "正在解压 ${FILE_NAME} ..."
    tar -xzf "${FILE_NAME}"

    # 删除压缩包
    rm "${FILE_NAME}"
    
# 检查并删除不需要的文件
    if [ -f "cfst_hosts.sh" ]; then
       rm -f "cfst_hosts.sh"
    fi
    if [ -f "使用+错误+反馈说明.txt" ]; then
       rm -f "使用+错误+反馈说明.txt"
    fi
    echo "下载并解压完成。"

    # 赋予执行权限（如果需要）
    chmod +x CloudflareST
fi

# 自动检测google是否连通，不连通则开始优选ip

# 尝试ping google.com 6次，并计算成功次数
success_count=$(ping -c 6 google.com | grep -c 'bytes from')

# 检查成功的次数，如果大于等于3次，则退出
if [ "$success_count" -ge 3 ]; then
    echo "Google连通，退出"
    exit 0
# 如果失败的次数大于等于3次，则继续运行下面的命令
elif [ "$success_count" -lt 2 ]; then
    echo "Google不连通，即将开始优选IP"
fi
# 继续执行下面的命令

echo -e "开始测速..."

# 检测是否有特定文件
NOWIP=$(head -1 nowip_hosts.txt)

# 停止passwall
/etc/init.d/passwall stop

# 这里可以自己添加、修改 CloudflareST 的运行参数
./CloudflareST -o "result_hosts.txt" 

# 检测测速结果文件，没有数据会重启passwall并退出脚本
[[ ! -e "result_hosts.txt" ]]
BESTIP=$(sed -n "2,1p" result_hosts.txt | awk -F, '{print $1}')
if [[ -z "${BESTIP}" ]]; then
	echo "CloudflareST 测速结果 IP 数量为 0，跳过下面步骤..."
	/etc/init.d/passwall start
	exit 0
fi
echo ${BESTIP} > nowip_hosts.txt
echo -e "\n旧 IP 为 ${NOWIP}\n新 IP 为 ${BESTIP}\n"
echo -e "开始替换..."

# 定义文件路径
nowip_file="nowip_hosts.txt"
passwall_file="/etc/config/passwall"

# 检查文件是否存在
if [ ! -f "$nowip_file" ]; then
    echo "Error: $nowip_file 文件不存在"
    exit 1
fi

if [ ! -f "$passwall_file" ]; then
    echo "Error: $passwall_file 文件不存在"
    exit 1
fi

# 读取nowip_hosts.txt文件中的内容并处理
while IFS= read -r line; do

# 替换/etc/config/passwall文件中的option address字段中的引号中的文本
sed -i "s/option address '.*'/option address '$line'/" "$passwall_file"
done < "$nowip_file"

echo "替换完成"

# 删除测速结果文件并启动passwall
rm -rf result_hosts.txt
/etc/init.d/passwall start
