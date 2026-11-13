#!/bin/sh

# ====== 请修改为你的 Cloudflare Worker 域名 ======
BOARD_URL="https://board.kidboard2026.dpdns.org/board.png"
SLEEP_SEC=900  # 刷新间隔：900秒 = 15分钟（可按需改为 600 或 1800）
# ===============================================

export PATH="/mnt/us/koreader:/mnt/us/bin:/mnt/us/libkh/bin:/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin"
TMP_IMG="/tmp/board.png"
CUR_IMG="/tmp/board_current.png"

# 检查 KOReader 目录下的 fbink 是否就绪
if ! command -v fbink >/dev/null 2>&1; then
    eips 4 10 "Error: fbink not found!"
    eips 4 12 "Please check /mnt/us/koreader/fbink"
    exit 1
fi

# 1. 停止原生阅读界面，防止系统自动休眠锁屏覆盖看板
initctl stop lab126_gui >/dev/null 2>&1
lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1

# 2. 识别 Kindle 8 硬件唤醒时钟
if [ -e /dev/rtc1 ]; then
    RTC_DEV="/dev/rtc1"
else
    RTC_DEV="/dev/rtc0"
fi

# 3. 定时唤醒主循环
while true; do
    # 开启 Wi-Fi
    lipc-set-prop com.lab126.wifid enable 1 >/dev/null 2>&1

    # 等待获取局域网 IP（最多等 20 秒）
    WAIT=0
    while [ $WAIT -lt 20 ]; do
        if ifconfig wlan0 2>/dev/null | grep -q "inet addr:"; then
            break
        fi
        sleep 1
        WAIT=$((WAIT + 1))
    done

    # 下载最新看板图片（-k 兼容老系统证书，-f 避免保存错误网页）
    if curl -k -s -f -m 20 "$BOARD_URL" -o "$TMP_IMG"; then
        NEW_MD5=$(md5sum "$TMP_IMG" | awk '{print $1}')
        OLD_MD5=""
        [ -f "$CUR_IMG" ] && OLD_MD5=$(md5sum "$CUR_IMG" | awk '{print $1}')

        # 仅当内容变化时执行全屏无残影刷新（600x800）
        if [ "$NEW_MD5" != "$OLD_MD5" ]; then
            mv "$TMP_IMG" "$CUR_IMG"
            fbink -c -f -g "file=$CUR_IMG,w=600,h=800" >/dev/null 2>&1
        else
            rm -f "$TMP_IMG"
        fi
    fi

    # 关闭 Wi-Fi 并进入硬件深度休眠
    lipc-set-prop com.lab126.wifid enable 0 >/dev/null 2>&1
    sleep 2
    rtcwake -d "$RTC_DEV" -m mem -s "$SLEEP_SEC" >/dev/null 2>&1
done
