set -o vi
stty erase ^?

if [ "`uname`" == "SunOS" ]; then
        PS1="${LOGNAME}@$(hostname) \${PWD} \${ORACLE_SID} \$ "
else
        PS1="${LOGNAME}@$(hostname -s) \${PWD##*/} \${ORACLE_SID} \$ "
fi

# export SPARK_CLASSPATH=/opt/cloudera/parcels/CDH/lib/hive/lib/*:/etc/hive/conf

alias s='sqlplus "/as sysdba"'
if [ "`uname`" == "SunOS" ]; then
        alias la='ls -la'
        alias lt='ls -ltr'
        alias ll='ls -l'
        alias xlogs='sudo find . \( -name "*.log" -o -name "*.trc" \) -mtime -1 | sudo xargs ls -ltr | less -R'
        export ORATAB="/var/opt/oracle/oratab"
        export TERM=ansi
else
        alias la='ls -la --color'
        alias lt='ls -ltr --color'
        alias ll='ls -l --color'
        alias grep='grep --color=auto'
        alias egrep='egrep --color=auto'
        alias fgrep='fgrep --color=auto'
        alias less='less -R'
        alias xlogs='sudo find . \( -name "*.log" -o -name "*.trc" \) -mtime -1 | sudo xargs ls -ltr --color | less -R'
        alias vi=vim
        export ORATAB="/etc/oratab"
fi
alias oh='cd $ORACLE_HOME; pwd'
alias tns='cd $ORACLE_HOME/network/admin; pwd'

alias ki='kinit rdautkhanov@some.domain.COM'
alias bl="beeline -u 'jdbc:hive2://prodhs2.somedomain.com:10000/default;principal=hive/_HOST@HADOOP'"
alias blq="beeline -u 'jdbc:hive2://qahs2.somedomain.com:10000/default;principal=hive/_HOST@HADOOP'"

if [ ! -f ~/.vimrc  -a  -f ~rdautkha/.vimrc ]; then
        cp ~rdautkha/.vimrc ~/.vimrc
fi

if [ -e $ORATAB ]; then
        export GI_HOME=`egrep '\+ASM[1-9]?:' $ORATAB | cut -d: -f2`
        if [ "x$GI_HOME" != "x" ]; then
                export PATH=$PATH:$GI_HOME/bin
                echo "Added GI bin $GI_HOME/bin into PATH"
        fi
fi

# export PATH=$PATH:~rdautkha/bin:/usr/openv/netbackup/bin
export MANPATH=$MANPATH:/usr/share/man
# export MYVIMRC=~rdautkha/.vimrc


echo PMONs are runnining for following SIDs:
ps -ef | grep pmon | grep -v grep | cut -d'_' -f 3,4 | paste - - - -


export ORACLE_SID=


export PDSH_SSH_ARGS="-q"
alias pdsh-hdpp="pdsh -w 'pc1hostpart[1-8]'"
alias pdsh-hdpq="pdsh -w 'qc1hostpart[1-3]'"
alias colmux-hdpp="colmux -addr 'pc1hostpart[1-8]'"
alias colmux-hdpq="colmux -addr 'qc1hostpart[1-3]'"

if [ -d /opt/cloudera/parcels/Anaconda/bin ]; then
        export PYTHONHOME=/opt/cloudera/parcels/Anaconda
        export PATH=$PYTHONHOME/bin:$PATH
fi
alias start-jupyter='jupyter notebook --no-browser --ip=* --port=25025 --notebook-dir=~/.ipython/notebook-dir/'

if [ -d /usr/java/java7 ]; then
        export JAVA_HOME=/usr/java/java7
        export PATH=$JAVA_HOME/bin:$PATH
fi

alias pstree='sudo pstree -pnua|egrep -v "\{\S+\}" | less'
alias du='sudo du -xh --max-depth=1 | sort -h'
