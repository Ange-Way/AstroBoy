#!/bin/bash
echo -n  "Comfirm continue！(y/n)"
read confirm
if [ "y" != "$confirm" ] ;then
   exit 0
fi

#记录脚本执行开始时间
startTime=`date +%s`
echo "Start Time ：$(date '+%Y-%m-%d %H:%M:%S')"


isCentOS=`cat /etc/os-release |grep '^NAME=' |grep -i 'centos'|wc -l`
isRedHat=`cat /etc/os-release |grep '^NAME=' |grep -i 'red hat'|wc -l`

osVersion=`cat /etc/os-release |grep 'VERSION_ID' |awk -F '"' '{print $2}'|awk -F . '{print $1}'`

if [ "0" == "$isCentOS" -a "0" == "$isRedHat" ]
then
  echo 'Unsupported OS, Only Support CentOS 6 、CentOS 7、RedHat 6 RedHat 7'
  exit 1
fi
osFilePrefix="CentOS"
cdromGpgkeyFileName="RPM-GPG-KEY-CentOS-$osVersion"
if [ "1" == "$isCentOS" ] ;then
    echo "Current OS : CentOS $osVersion"
else
    echo "Current OS : RedHat $osVersion"
    osFilePrefix="rhel-server"
	cdromGpgkeyFileName="RPM-GPG-KEY-redhat-release"
fi

currDir=`dirname $0`
source $currDir/functions.sh
ip_file=$1

checkCurrentUserIsRoot
if [ $? != 0 ]
then 
   exit 1
fi

#检测传入的ip配置文件

if [ "${ip_file}" == "" ]
then
   echo 'please input a file which  includes ip ,hostname,root-password(eg: master 192.168.1.110 1234)'
   echo 'each line only contain one record,and sepearator is tab space!'
   exit 1
fi

if [ ! -f ${ip_file} ]
then
   echo ${ip_file}' is not a regular file'
   exit 1
fi

#检测是否有重复的IP地址配置，或者hostname配置
ipRepeat=`cat $ip_file|sed  '/^$/d'|awk '{print $1}'|sort|uniq -c|awk '{if($1>1){print "true"}else{print "false"}}'|grep true|wc -l`
hostnameRepeat=`cat $ip_file|sed  '/^$/d'|awk '{print $2}'|sort|uniq -c|awk '{if($1>1){print "true"}else{print "false"}}'|grep true|wc -l`

if [ "1" == "$ipRepeat" ] ;then
   repeatIp=`cat $ip_file|sed  '/^$/d'|awk '{print $1}'|sort|uniq -c|awk '{if($1>1){print "true "$2}else{print "false"}}'|grep true|awk '{print $2}'`
   echo "$ip_file 有重复的ip地址配置:$repeatIp"
   exit 1
fi
if [ "1" == "$hostnameRepeat" ] ;then
   repeatHostname=`cat $ip_file|sed  '/^$/d'|awk '{print $2}'|sort|uniq -c|awk '{if($1>1){print "true "$2}else{print "false"}}'|grep true|awk '{print $2}'`
   echo "$ip_file 有重复的hostname配置:$repeatHostname"
   exit 1
fi


#mount 命令在7系列和6系列上有细微差异
mountCommand="mount -o loop "
if [ $osVersion == 7 ]
then
 mountCommand="mount "
fi

#检测依赖的exp和sh文件是否存在
echo ''
echo 'Check install script dependency file!'
echo ''
checkDependencyFile
if [ $? != 0 ]
then
   exit 1
fi
#检测jdk安装包是否存在
echo "检测jdk安装包是否存在"
jdkFiles=`ls -l $currDir/res/ |grep jdk |awk 'END{print NR}'`
if [ $jdkFiles != 1 ] ;then
   echo 'jdk安装包缺失，或拥有多个安装包，退出！'
   exit 1
fi

echo ''
echo 'Check install package dependency !'
echo ''
checkOS_ISORes $osFilePrefix $osVersion
if [ $? != 0 ]
then
  echo 'Check OS ISO file failed!!'
  exit 1
fi

echo 'Check OS ISO file success!!'

echo ''
echo 'Check ambari HDP HDP-UTIL'
echo ''

checkRes centos$osVersion
if [ $? != 0 ]
then
  echo 'Check ambari HDP HDP-UTIL failed'
  exit 1
fi
echo ''
echo 'Check ambari HDP HDP-UTIL success'
echo ''


echoLineSeparator 1 '检测依赖通过，准备挂载系统iso镜像文件，安装expect 和httpd '

mount_iso_file=`ls $currDir/res/${os_file_prefix}-$osVersion*.iso` 
if [ -e /mnt/cdrom -a -d /mnt/cdrom ]
then
   #文件夹已经存在了
   #检测是否已经有挂载的镜像文件
   deviceName=`df -h | grep '/mnt/cdrom' |awk '{print $1}'`
   if [ "" != "$deviceName" ]
   then
     echo '检测到/mnt/cdrom文件夹上有挂载，将取消这个挂载'
     u_msg=`umount $deviceName`
     echo "mount返回值：$?"
     echo "mount msg:$u_msg"
     if [ "" != "$u_msg" ]
     then
        echo '取消挂载/mnt/cdrom上的设备失败！'
        echo '请手动取消挂载，重新执行该脚本！'
        exit 1
     fi
     echo '取消挂载成功，将重新挂载需要的iso文件'
     $mountCommand $mount_iso_file /mnt/cdrom
     if [ $? != 0 ]
     then
       echo 'mount fail,please check mount command excuting output log!!'
     exit 1
      fi

   else
     #没有在/mnt/cdrom上挂载有设备
     echo '没有在/mnt/cdrom上有挂载设备，但是该文件夹已存在'
     echo '重命名该文件件为/mnt/cdrom.bak'
     mv /mnt/cdrom /mnt/cdrom.bak
     ls -l /mnt
     mkdir -p /mnt/cdrom
     echo "ready to mount file $mount_iso_file to /mnt/cdrom directory!!"
     $mountCommand $mount_iso_file /mnt/cdrom
     if [ $? != 0 ]
     then
       echo 'mount fail,please check mount command excuting output log!!'
     exit 1
      fi

   fi 
 else
   #文件夹不存在
   echo '文件夹/mmt/cdrom不存在'
   mkdir -p /mnt/cdrom
   if [ $? != 0 ]
   then
      echo '创建文件夹/mnt/cdrom失败，请查看命令返回log'
      exit  1
   fi

   echo "ready to mount file $mount_iso_file to /mnt/cdrom directory!!"
   $mountCommand $mount_iso_file /mnt/cdrom
   if [ $? != 0 ]
   then
     echo 'mount fail,please check mount command excuting output log!!'
   exit 1
   fi
 fi
 
echoLineSeparator 1 '挂载镜像成功，准备配置当前节点yum源'

echo '移除 /etc/yum.repos.d文件夹下的所有repo文件'
rm -f /etc/yum.repos.d/*.repo
mineRepo=/etc/yum.repos.d/ambari.repo
echo "[base]"                                        >> $mineRepo
echo "name=centos$osVersion Base"                           >> $mineRepo         
echo "baseurl=file:///mnt/cdrom"                     >> $mineRepo   
echo "gpgcheck=0"                                    >> $mineRepo          
echo "enabled=1"                                     >> $mineRepo       
echo "priority=1"                                    >> $mineRepo

echo "$mineRepo内容如下"
cat $mineRepo
yum clean all && yum repolist

if [ $? != 0 ]
then
  exit 1
fi

 
   echoLineSeparator 1 '检测是否安装expect，如果没安装则自动安装'
   expDep=`rpm -qa|grep expect`
   if [ "" == "$expDep" ] ;then
     echo 'Dependency Check ,current host has not installed [expect]'
     yum install -y expect
     if [ $? != 0 ]
     then
       exit 1
     fi
   fi
   echoLineSeparator 1 '检测是否安装http ,如果没有安装则自动安装'
   httpdDep=`rpm -qa|grep -v 'httpd-tools' |grep httpd`
    if [ "" == "$httpdDep" ] ;then
     echo 'Dependency Check ,current host has not installed [httpd]'
     yum install -y httpd   
     if [ $? != 0 ]
     then
       exit 1
     fi
     chkconfig httpd on    
   fi
   echoLineSeparator 1 'EveryThing is ready !!'
 
   echoLineSeparator 1 '在/var/www/html中创建资源文件夹'
  
   httpHome=/var/www/html
   subDirArray=('cdrom' 'ambari' 'hdp' 'hdp-utils')
   
   for((i=0;i<${#subDirArray[@]};i++))
   do
     sub=${subDirArray[$i]}
     echo "子文件夹：$sub"
     if [ -e $httpHome/$sub ]
     then
       echo "文件(夹)$httpHome/$sub已经存在，将移除文件(夹)"
       echo "rm -rf  $httpHome/$sub "   
       rm -rf $httpHome/$sub 
       
     fi 
        mkdir $httpHome/$sub
    

   done
   ls -l  $httpHome
   
   ambariTarFile=`ls $currDir/res/ambari-*-centos$osVersion.tar.gz`
   hdpTarFile=`ls $currDir/res/HDP-*-centos$osVersion-rpm.tar.gz`
   hdp_utils_tarFile=`ls $currDir/res/HDP-UTILS-*-centos$osVersion.tar.gz`

   
   echo "ambari:$ambariTarFile"
   echo "hdp:$hdpTarFile"
   echo "hdp_utils:$hdp_utils_tarFile"


   echo "挂载成功，copy /mnt/cdrom 到$httpHome目录下"
     cp -r /mnt/cdrom /var/www/html
   echo "解压文件到指定目录"
   echo "tar -zxvf $ambariTarFile -C $httpHome/ambari"
        tar -zxf $ambariTarFile -C $httpHome/ambari
   echo "tar -zxvf $hdpTarFile -C $httpHome/hdp"
       tar -zxf $hdpTarFile -C $httpHome/hdp
   echo "tar -zxf $hdp_utils_tarFile -C $httpHome/hdp-utils"
       tar -zxf $hdp_utils_tarFile -C $httpHome/hdp-utils
   echo "service httpd restart" 
    service httpd restart
    chkconfig httpd on
#打印一行分隔符
echoLineSeparator 1 '开始进行hostname配置，请不要手动打断！'
#所有的节点ip
total_ips=`awk '{print $1}' $ip_file`
#当前所在节点ip
mip=""
for i in  `ip addr |grep inet|grep brd |awk '{print $2}' |awk -F / '{print $1}'`
do
	for j in `awk '{print $1}' ${ip_file}`
	do
	   if [ "$i" == "$j" ] ;then
	      mip="$j"
		  break
	   fi
	done
done

if [ "" == "$mip" ] ;then
   "echo get current ip failed!!!"
    exit 1
fi
#除开当前节点ip
other_ips=`grep -v $mip ${ip_file} |awk '{print $1}' `

allHostNames=`awk '{print $2}' $ip_file`
#配置所有节点的hostname
    for i in $total_ips
    do 
       tmpHs=`getHostNameByIP $ip_file $i`
       psw=`getRootPSWByIP $ip_file $i`
       if [ $tmpHs == "" ]
       then
         echo "can not set empty hostname to $i"
         exit 1
       fi
       if [ "6" == "$osVersion" ]
       then
          #替换hostname命令
          repCMD="sed -i  's/^HOSTNAME.*/HOSTNAME=$tmpHs/g' /etc/sysconfig/network && hostname $tmpHs"
          echo $repCMD
          $currDir/expect_ssh.exp root $i  "$repCMD"  $psw
          if [  $? != 0 ]
          then
             exit 1
          fi  
       elif [ "7" == "$osVersion" ]
       then
         $currDir/expect_ssh.exp root $i  "echo $tmpHs > /etc/hostname  && hostname $tmpHs" $psw
       fi
      
    done    
#打印一行分隔符
echoLineSeparator 1 '完成hostname配置，即将进行下一步！'
echoLineSeparator 1 '修改每个节点系统内核参数'
for i in $total_ips
do
  #修改内核参数
    psw=`getRootPSWByIP $ip_file $i`
    if [ "6" == "$osVersion" ]
       then
         	 	   
          $currDir/expect_ssh.exp root $i  "sed -i '/\* *soft *nproc/d' /etc/security/limits.d/90-nproc.conf && echo '*          soft   nproc     60000' >> /etc/security/limits.d/90-nproc.conf"  $psw
          $currDir/expect_ssh.exp root $i  "sed -i '/root *soft *nproc/d' /etc/security/limits.d/90-nproc.conf && echo 'root       soft    nproc     unlimited' >> /etc/security/limits.d/90-nproc.conf"  $psw

       elif [ "7" == "$osVersion" ]
       then
          $currDir/expect_ssh.exp root $i  "sed -i '/\* *soft *nproc/d' /etc/security/limits.d/20-nproc.conf &&  echo '*          soft   nproc     60000' > /etc/security/limits.d/20-nproc.conf"  $psw
          $currDir/expect_ssh.exp root $i  "sed -i '/root *soft *nproc/d' /etc/security/limits.d/20-nproc.conf && echo 'root       soft    nproc     unlimited' >> /etc/security/limits.d/20-nproc.conf"  $psw 
       fi

          $currDir/expect_ssh.exp root $i  "sed -i '/\* *soft *nofile/d' /etc/security/limits.conf && echo '*  soft nofile  65536' >> /etc/security/limits.conf"  $psw 
          $currDir/expect_ssh.exp root $i  "sed -i '/\* *hard *nofile/d' /etc/security/limits.conf &&echo '*  hard nofile  65536' >> /etc/security/limits.conf"  $psw   
  
done



for i in $other_ips
do
  if [ "$mip" != "$i" ] ;then
    echo "ssh $i 'sysctl -p'"
    psw=`getRootPSWByIP $ip_file $i`
    $currDir/expect_ssh.exp root $i  "sysctl -p"  $psw
          
  fi
done
echo "sysctl -p"
sysctl -p

echoLineSeparartor 1 '完成第一阶段的配置'


#打印一行分隔符
echoLineSeparator 1 '开始进行hostname配置，请不要手动打断！'

echoLineSeparator 1 '开始配置节点之间root用户免密登录,请不要手动打断！'
   #遍历节点，在每个节点执行ssh-keygen命令
   for i in $total_ips
   do
       psw=`getRootPSWByIP $ip_file $i`
       $currDir/expect_ssh.exp root $i  'ssh-keygen -t rsa -P "" -f /root/.ssh/id_rsa' $psw  
   done
   #将其他节点的id_rsa.pub文件copy到当前节点
   for i in $other_ips
   do
       psw=`getRootPSWByIP $ip_file $i`
     $currDir/expect_scp_from_remote.exp root $i $psw  /root/.ssh/id_rsa.pub /root/.ssh/id_scp$i  
   done
   #在当前节点构建/root/.ssh/authorized_key 文件
      cat /root/.ssh/id_scp* /root/.ssh/id_rsa.pub > /root/.ssh/authorized_keys
   #发送authorized_key到每个节点下
      for i in $other_ips
      do
        psw=`getRootPSWByIP $ip_file $i`
        $currDir/expect_scp_to_remote.exp root $i $psw /root/.ssh/authorized_keys /root/.ssh/
      done
   #修改/root/.ssh 文件夹权限
   for i in $total_ips
   do
       $currDir/expect_ssh.exp root $i  'chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys' $psw
   done


echoLineSeparator 1 '完成各个节点之间root用户的免密登录，即将进行下一步！'

echoLineSeparator 1 '开始配置每个节点的hosts文件'
for i in $total_ips
do
   for j in `sed '/^$/d' $ip_file | awk '{printf("%s\47%s\n",$1,$2)}'`
   do
     cip=`echo $j |awk -F "'"  '{print $1}'`
     chs=`echo $j |awk -F "'" '{print $2}'`
     echo "ip映射:$cip $chs"
     ssh $i "sed -i '/${cip}/d' /etc/hosts && sed -i '/${chs}/d' /etc/hosts && echo '${cip} ${chs}' >> /etc/hosts"
   done
   echo "host $i /etc/hosts 文件内容如下："
   ssh $i 'cat /etc/hosts'
   echo "**************************"
done
echoLineSeparator 1 '完成配置每个节点的hosts文件'
echoLineSeparator 1 '测试节点之间免密登录'
for i in $allHostNames
do
    echo "ssh $i"
    $currDir/expect_test_ssh_no_psw.exp $i
done


echoLineSeparator 1 '准备关闭防火墙'
for i in $total_ips
do
       psw=`getRootPSWByIP $ip_file $i`
       if [ "6" == "$osVersion" ]
       then
          $currDir/expect_ssh.exp root $i  "service iptables stop  && chkconfig iptables off"  $psw
       elif [ "7" == "$osVersion" ]
       then
         $currDir/expect_ssh.exp root $i  "systemctl stop firewalld && systemctl disable firewalld && systemctl status firewalld && chkconfig firewalld off" $psw
       fi
           
        $currDir/expect_ssh.exp root $i "sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/sysconfig/selinux"

done
mineRepo=/etc/yum.repos.d/ambari.repo

currHostName=`hostname`
echo "清空$mineRepo文件"

echo '' > $mineRepo
echo '[base]' >> $mineRepo
echo "name=centos$osVersion Base" >> $mineRepo
echo "baseurl=http://$currHostName/cdrom" >> $mineRepo
echo "gpgcheck=0" >> $mineRepo
echo "enabled=1" >> $mineRepo


echo "" >> $mineRepo
echo "" >> $mineRepo

ambari_repo_name=`ls $httpHome/ambari`
echo "ambari_repo_name:$ambari_repo_name"
ambari_repo_res_dir=`ls $httpHome/ambari/$ambari_repo_name/centos$osVersion`
echo "ambari_repo_res_dir:$ambari_repo_res_dir"
ambari_dir="ambari/$ambari_repo_name/centos$osVersion/$ambari_repo_res_dir"
echo "ambari_dir:$ambari_dir"
echo "[ambari]" >> $mineRepo
echo "name=$ambari_repo_name" >> $mineRepo
echo "baseurl=http://$currHostName/$ambari_dir" >> $mineRepo
echo "gpgcheck=0" >> $mineRepo
echo "enabled=1" >> $mineRepo

echo "" >> $mineRepo
echo "" >> $mineRepo

hdp_repo_name=`ls $httpHome/hdp`
echo "hdp_repo_name:$hdp_repo_name"
hdp_repo_res_dir=`ls $httpHome/hdp/$hdp_repo_name/centos$osVersion`
echo "hdp_repo_res_dir:$hdp_repo_res_dir"
hdp_dir="hdp/$ambari_repo_name/centos$osVersion/$hdp_repo_res_dir"
echo '[hdp]' >> $mineRepo
echo "name=hdp Base" >> $mineRepo
echo "baseurl=http://$currHostName/$hdp_dir" >> $mineRepo
echo "gpgcheck=0" >> $mineRepo
echo "enabled=1" >> $mineRepo

echo "" >> $mineRepo
echo "" >> $mineRepo

utils_repo_name=`ls $httpHome/hdp-utils`
echo "utils_repo_name:$utils_repo_name"
utils_repo_res_dir=`ls $httpHome/hdp/$utils_repo_name/centos$osVersion`
echo "utils_repo_res_dir:$utils_repo_res_dir"
utils_dir="hdp/$utils_repo_name/centos$osVersion/$utils_repo_res_dir"
echo '[hdp-utils]' >> $mineRepo
echo "name=hdp-utils Base" >> $mineRepo
echo "baseurl=http://$currHostName/$utils_dir" >> $mineRepo
echo "gpgcheck=0" >> $mineRepo
echo "enabled=1" >> $mineRepo

echo "" >> $mineRepo
echo "" >> $mineRepo

echo '完成所有yum源配置！！！！配置文件类容如下：'
cat $mineRepo
for i in $allHostNames
do
   if [ "$currHostName" != "$i" ] ;then
     ssh $i 'rm -f /etc/yum.repos.d/*.repo'
   fi
done


distributeFilesToNodes $mineRepo $mineRepo
executeCommandOnEachNode 'yum clean all && yum repolist'
echo "加载所有的GPG-KEY"
executeCommandOnEachNode "rpm --import http://$currHostName/cdrom/$cdromGpgkeyFileName"
executeCommandOnEachNode "rpm --import http://$currHostName/hdp/HDP/centos$osVersion/RPM-GPG-KEY/RPM-GPG-KEY-Jenkins"
executeCommandOnEachNode "rpm --import http://$currHostName/hdp-utils/RPM-GPG-KEY/RPM-GPG-KEY-Jenkins"
executeCommandOnEachNode "rpm --import http://$currHostName/$ambari_dir/RPM-GPG-KEY/RPM-GPG-KEY-Jenkins"

echoLineSeparator 1 '配置Ntp时间同步服务'
sed -i "s/server n.*/server $currHostName/g" $currDir/conf/slave-ntp.conf
for i in $allHostNames
do
   ntpRPM=`ssh $i 'rpm -qa|grep ntp'`
  if [ "" == "$ntpRPM" ] ;then
   ssh $i 'yum install -y ntp'
  fi
  if [ "$currHostName" == "$i" ] ;then
     rm -f /etc/ntp.conf &&   cp $currDir/conf/master-ntp.conf /etc/ntp.conf
     echo "当前节点(${i})为ntp服务的主节点"
    service ntpd start && /usr/sbin/ntpdate -u localhost &&    service ntpd restart
  else
     echo "当前节点(${i})为ntp服务的从节点，将于主节点进行时间同步"
    scp $currDir/conf/slave-ntp.conf   $i:/etc/ntp.conf
    ssh $i   "service ntpd start && /usr/sbin/ntpdate -u $currHostName &&  service ntpd restart"
  fi

done
executeCommandOnEachNode 'chkconfig ntpd on && service ntpd restart'


echoLineSeparator 1  '安装自带JDK'
executeCommandOnEachNode "rpm -qa|grep java |awk '{print \"rpm -e --nodeps \"\$0}' |sh"
jdkF=`ls $currDir/res/jdk*.rpm |awk -F / 'END{print $NF}'`
echo '当前节点安装JDK'
rpm -ivh $currDir/res/$jdkF
distributeFilesToNodes  $currDir/res/$jdkF /root
executeCommandOnOtherNodes "rpm -ivh /root/$jdkF"

if [ $osVersion == 7 ] ;then
   echoLineSeparator 1 'CentOS 7 需要卸载冲突的依赖snappy包'
   executeCommandOnEachNode 'yum remove -y snappy-1.1.0-3.el7.x86_64'
   executeCommandOnEachNode 'yum install -y snappy-1.0.5-1.el6.x86_64'
fi
echoLineSeparator 1 '完成自动配置，请手动依次完成以下操作！'
echo "yum install -y ambari-server"
echo "ambari-server setup"
#创建hive元数据库，并修改postgresql数据库访问权限


echo '创建hive元数据库，并修改postgresql数据库访问权限'
echo 'yum install -y postgresql-jdbc* '

echo 'ambari-server setup --jdbc-db=postgres --jdbc-driver=/usr/share/java/postgresql-jdbc.jar'

echo "su - postgres -c \"psql -c 'CREATE DATABASE hive;'\" && su - postgres -c \"psql -c 'CREATE USER hive WITH PASSWORD 'hive';'\" && su - postgres -c \"psql -c 'GRANT ALL PRIVILEGES ON DATABASE hive TO hive;'\""

networkRange=24
getWay=`echo $mip |awk -F . '{print $1"."$2"."$3"."0}'`

echo "echo  'local   all     hive                    trust' >> /var/lib/pgsql/data/pg_hba.conf"
echo "echo  'host    all     hive    $getWay/$networkRange trust' >> /var/lib/pgsql/data/pg_hba.conf"

echo 'service postgresql restart'

endTime=`date +%s`

echo "结束时间：$(date '+%Y-%m-%d %H:%M:%S')"

spend=`expr $endTime - $startTime`
echo "完成自动配置耗时：$spend秒"
echo "请手动执行ambari-server setup"

