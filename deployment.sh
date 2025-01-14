#!/bin/bash

cd /opt/minecraft/server/
rm -f stop
rm -f start
rm -f monitor

echo -e '#!/bin/bash\n# Variable which sets how long to wait until shutting down after the last player disconnects\n# Do not set this value under 5 minutes (300 seconds). A low value might result in the server shutting down before players can join.\nSSM_SHUTDOWNTIMER=$(aws ssm get-parameter --name "/mc/shutdowntimer" --query "Parameter.Value" --output text)\nDEFAULT_SHUTDOWNTIMER=900\nif [ $? -eq 0 ] && [[ "$SSM_SHUTDOWNTIMER" =~ ^[0-9]+$ ]] && [ "$SSM_SHUTDOWNTIMER" -gt 0 ]; then\nSHUTDOWNTIMER=$SSM_SHUTDOWNTIMER\nelse\nSHUTDOWNTIMER=$DEFAULT_SHUTDOWNTIMER\nfi\n\n# var to track time of last disconnect\nlastdisconnect=0\nwhile true; do\n# Get current connection\nconnections=$(netstat -antp | grep ":25565" | grep ESTABLISHED | wc -l)\nif [ $connections -eq 0 ]; then\necho "0 connections"\nif [ $lastdisconnect -eq 0 ]; then\necho "no players on server, starting timer..."\n# First disconnect, record time\nlastdisconnect=$(date +%s)\nelse\n# Check elapsed time since last disconnect\nnow=$(date +%s)\nelapsed=$((now - lastdisconnect))\necho "no players again, check if timer has reached time"\necho "shutdowntimer: $SHUTDOWNTIMER timer: $elapsed"\nif [ $elapsed -ge $SHUTDOWNTIMER ]; then\necho "timer has reached time, begin shutdown logic"\n# Over time, shutdown\n# Stop Minecraft server\necho "Stop Minecraft server"\nsudo ./stop\nsleep 20\n# Stop EC2 instance\necho "stop ec2 instance"\nsudo shutdown -h now\nbreak\nfi\nfi\nelse\n# Connections exist, reset disconnect timer\necho "connections exist"\nlastdisconnect=0\nfi\n# Check again in 30 seconds\nsleep 30\ndone' >> monitor
chmod +x monitor

# create server start file with SSM or default RAM
echo -e '#!/bin/bash\nRAM=$(aws ssm get-parameter --name "/mc/ram" --query "Parameter.Value" --output text)\nDEFAULT_RAM="1300M"\necho "starting server!"\nif [ $? -eq 0 ] && [[ "$RAM" =~ ^[0-9]+$ ]] && [ "$RAM" -gt 0 ]; then\nram_size="${RAM}M"\nelse\nram_size="$DEFAULT_RAM"\nfi\necho "ram: $ram_size"\njava -Xmx$ram_size -Xms$ram_size -jar server.jar nogui' >> start
chmod +x start

echo -e '#!/bin/bash\necho "/stop" > /run/minecraft.stdin' >> stop
chmod +x stop

cd /etc/systemd/system/
rm -f minecraft.service
rm -f minecraft.socket
rm -f monitor_minecraft.service

echo -e '[Unit]\nDescription=Minecraft Server on start up\n[Service]\nUser=minecraft\nWorkingDirectory=/opt/minecraft/server\nExecStart=/opt/minecraft/server/start\n \
    Restart=on-failure\nSockets=minecraft.socket\nStandardInput=socket\nStandardOutput=journal\nStandardError=journal\n[Install]\nWantedBy=multi-user.target' >> minecraft.service

echo -e '[Unit]\nPartOf=minecraft.service\n[Socket]\nListenFIFO=%t/minecraft.stdin' >> minecraft.socket

echo -e '[Unit]\nDescription=Monitor MC server for network connections\nWants=network-online.target\n[Service]\nUser=ec2-user\nWorkingDirectory=/opt/minecraft/server\n \
    ExecStart=/opt/minecraft/server/monitor\nStandardInput=null\n[Install]\nWantedBy=multi-user.target' >> monitor_minecraft.service

sudo systemctl daemon-reload
sudo systemctl enable minecraft.service
sudo systemctl start minecraft.service
sudo systemctl enable monitor_minecraft.service
sudo systemctl start monitor_minecraft.service
