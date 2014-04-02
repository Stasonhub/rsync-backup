Скрипт для резервного копирования на удаленный сервер с помощью rsync.

<h2>Подготовка сервера бэкапов.</h2>

Общая настройка
Устанавливаем rsync и xinetd:

<code>yum -y install rsync xinetd</code>

Добавляем в атозагрузку сервис xinetd:

<code>chkconfig --add xinetd</code>

Разрешаем rsync

<code>vi /etc/xinetd.d/rsync</code>

Меняем disable = yes на disable = no
и создаем файл конфигурации /etc/rsyncd.conf

И добавляем в него:
pid file = /var/run/rsyncd.pid log file = /var/log/rsyncd.log 
На этом общую настройку заканчиваем и переходим к настройке бэкапа под конкретный сервер.

<h2>Настройка окружения для бэкапа сервера.</h2>

Добавляем пользователя если он не еще не добавлен:
<pre lang="bash"><code>
usernames=backup
useradd -g backups $usernames
rm -f /home/$usernames/.bash*
mkdir /home/$usernames/.ssh /home/$usernames/rsyncbackups
chown -R $usernames:vzbackups /home/$usernames
chown -R root:root /home/$usernames/.ssh
touch /home/$usernames/.ssh/authorized_keys
</pre></code>
Блок с ключом необходимо заменить на сгенерированные данные id_rsa.pub:
no-port-forwarding,no-X11-forwarding,no-pty ssh-rsa ---your-ssh-key-here--- root@backup.example.com

Добавляем в /etc/rsyncd.conf
<pre lang="bash"><code>
cat << EOF >> /etc/rsyncd.conf
[$usernames]
comment = backups for $usernames
path = /home/$usernames/rsyncbackups
use chroot = true
uid = root
gid = root
log file = /var/log/rsyncd/$usernames.log
read only = false
write only = false
hosts allow = 88.198.6.141
hosts deny = *
transfer logging = false
EOF
</pre></code>
где:
<ul>
<li>path = /home/$usernames/rsyncbackups - путь где будут лежать бэкапы</li>
<li>log file = /var/log/rsyncd/$usernames.log - путь к логам</li>
<li>hosts allow = 1.2.3.4 - IP с которого разрешен доступ к данному окружению</li>
</ul>
На этом, настройка серверной части завершена.

<h2>Настройка сервера клиента.</h2>

Для изменения параметров сервера бэкапов, исключений контейнеров из бэкапа, локальной папки (или ее отсутствия) достаточно внести изменения в файл
rsync-backup.local.conf

Исключения

Для исключений существуют файлы со списком исключений, указанных с каждой новой строки без первичного слеша (правила исключений для rsync). 
<pre lang="bash"><code>
srv/southbridge/etc/rsync-backup.exclude.dist - файл с общими исключениями
srv/southbridge/etc/rsync-backup.exclude.local.example - пример названия исключений для локального бэкапа
srv/southbridge/etc/rsync-backup.exclude.remote.example - пример название исключений для удаленного бэкапа
</pre></code>
Cкрипт бэкапа проверяет наличие файлов srv/southbridge/etc/rsync-backup.exclude.local и srv/southbridge/etc/rsync-backup.exclude.remote и при их наличии добавляет исключения при бэкапах. Если локальный бэкап отменили — локальные исключения добавляются в удаленные.

Включения

Особенностью этого скрипта является возможность включения определенных файлов или каталогов из исключенной директории выше иерархией. Для этого нужно создать файлы
<pre lang="bash"><code>
/srv/southbridge/etc/rsync-backup.include.local
/srv/southbridge/etc/rsync-backup.include.remote
</pre></code>
соотвественно для локальных и удаленных включений.
Если нужно включить конкретный файл, то необходимо указать его путь без первичного слеша, к примеру:
var/log/nginx/server.log
если же нужно включить директорию с подпапками и файлами в них то нужно указать включение так:
var/log/nginx/**
Каждое новое включение с новой строки без первичного слеша.

При работе включений будет бэкапиться вся иерархия директорий контейнера даже если раннее было добавлено исключение определенных директорий, но бэкапиться будет именно директории без файлов.
Это особенность работы rsync, к сожалению другого пути пока не нашли. 
Часть скрипта для работы включений:
<pre lang="bash"><code>
     if [ -f "$LOCAL_INCLUDE" ]; then
          e "sync include" 
          e "rsync -ax --include=*/ --include-from=$LOCAL_INCLUDE --exclude=* --link-dest=../../Latest $VZ_PRIVATE/$VEID $LOCAL_DIR/$VEID/$WHICH/Processing$DATE" 
          LLOG=`rsync -ax --include=*/ --include-from=$LOCAL_INCLUDE --exclude=* --link-dest=../../Latest $VZ_PRIVATE/$VEID $LOCAL_DIR/$VEID/$WHICH/Processing$DATE 2>&1`
      fi
</code></pre>

<h2>Дальнейшая работа с бэкапами</h2>

По умолчанию скрипт будет создавать бэкапы: 7 дневных, 4 недельных и 1 месячный для изменения этого в
/srv/centos-admin.ru/etc/rsync-backup.local.conf можно вписать иные цифры следующих параметров
<pre lang="bash"><code>
DAILY=7
WEEKLY=4
MONTHLY=1
</code></pre>
Инкрементальные бэкапы производятся с использованием хардлинков. Поэтому, чтобы сократить объем дискового пространства занимаемого бэкапом, при добавлении исключений, и при чистке бэкапов от этих исключений нужно будет удалить соответствующие директории в каждой папке бэкапов. Конечно можно написать скрипт для автоматизации этой рутины, это в планах.
