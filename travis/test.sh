#!/bin/bash

git fetch --unshallow
COUNT=$(git rev-list --count HEAD)

#INFO
echo "*** Trigger build ***"


#下载SM
echo "Download sourcemod ..."
wget "http://www.sourcemod.net/latest.php?version=$1&os=linux" -q -O sourcemod.tar.gz
tar -xzf sourcemod.tar.gz


#设置文件为可执行
echo -e "Set compiler env ..."
chmod +x addons/sourcemod/scripting/spcomp


#拷贝文件到编译器文件夹
echo -e "Copy scripts to compiler folder ..."
cp -rf gameserver/scripting/* addons/sourcemod/scripting


#编译...
addons/sourcemod/scripting/spcomp -E -v0 addons/sourcemod/scripting/NewPage.sp
addons/sourcemod/scripting/spcomp -E -v0 addons/sourcemod/scripting/np-stats.sp
addons/sourcemod/scripting/spcomp -E -v0 addons/sourcemod/scripting/np-user.sp
addons/sourcemod/scripting/spcomp -E -v0 addons/sourcemod/scripting/np-vip.sp
